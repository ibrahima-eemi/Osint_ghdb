#!/bin/bash

# Fichier de log
LOG_FILE="script.log"

# Fonction pour journaliser les informations
log_info() {
    local message="[INFO] $1"
    echo "$message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $message" >> "$LOG_FILE"
}

# Fonction pour journaliser les erreurs
log_error() {
    local message="[ERREUR] $1"
    echo "$message" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') $message" >> "$LOG_FILE"
}

# Fonction pour journaliser les avertissements
log_warning() {
    local message="[AVERTISSEMENT] $1"
    echo "$message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $message" >> "$LOG_FILE"
}

# Liste des user-agents
user_agents=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
    "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:40.0) Gecko/20100101 Firefox/40.1"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/601.3.9 (KHTML, like Gecko) Version/9.0.2 Safari/601.3.9"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.77 Safari/537.36"
)

# Fonction pour obtenir un user-agent aléatoire
get_random_user_agent() {
    echo "${user_agents[$RANDOM % ${#user_agents[@]}]}"
}

# Vérification de la connexion à Tor
log_info "Vérification de la connexion à Tor"
response=$(curl --socks5-hostname 127.0.0.1:9050 -s https://check.torproject.org/)
if echo "$response" | grep -q "Congratulations. This browser is configured to use Tor."; then
    log_info "Connexion Tor confirmée."
else
    log_error "La connexion Tor ne fonctionne pas correctement."
    exit 1
fi

# Liste des Google Dorks à utiliser
dorks=(
    "filetype:xls OR filetype:xlsx intext:confidential"
    "site:edu filetype:pdf budget OR finance"
    "filetype:txt intext:password"
)

# Boucle sur chaque dork pour effectuer les recherches
for dork in "${dorks[@]}"; do
    log_info "Recherche de fichiers PDF via DuckDuckGo avec le terme : $dork"
    sleep 5 # Pause pour s'assurer que la connexion Tor est stable

    # Encodage de la requête
    query=$(echo "$dork" | sed 's/ /+/g')

    # Exécution de la requête avec gestion des erreurs
    search_results=$(curl --socks5-hostname 127.0.0.1:9050 -s -A "$(get_random_user_agent)" "https://html.duckduckgo.com/html?q=$query")
    if [ $? -ne 0 ]; then
        log_error "Erreur lors de l'exécution du dork : $dork"
        continue
    fi

    # Extraction des URLs de fichiers PDF
    pdf_urls=$(echo "$search_results" | grep -oP 'https?://[^ ]+\.pdf')

    if [ -z "$pdf_urls" ]; then
        log_info "Aucune URL de fichier PDF trouvée pour le dork : $dork."
    else
        log_info "Nombre d'URLs trouvées pour le dork $dork : $(echo "$pdf_urls" | wc -l)"
    fi

    # Boucle sur chaque URL trouvée
    while IFS= read -r url; do
        log_info "Fichier PDF trouvé : $url"

        # Vérification de l'accessibilité de l'URL
        http_status=$(curl --socks5-hostname 127.0.0.1:9050 -o /dev/null -s -w "%{http_code}" -A "$(get_random_user_agent)" "$url")
        if [ "$http_status" -ne 200 ]; then
            log_warning "Impossible d'accéder au fichier $url (HTTP $http_status)"
            continue
        fi

        # Téléchargement du PDF pour analyse
        log_info "Téléchargement du fichier $url"
        curl --socks5-hostname 127.0.0.1:9050 -s -A "$(get_random_user_agent)" -o "temp.pdf" "$url"

        if [ ! -f "temp.pdf" ] || [ ! -s "temp.pdf" ]; then
            log_warning "Le fichier téléchargé est vide ou n'a pas été correctement téléchargé : $url"
            continue
        fi

        # Conversion du PDF en texte
        log_info "Tentative de conversion du fichier PDF en texte avec pdftotext"
        pdftotext temp.pdf temp.txt
        if [ ! -f "temp.txt" ] || [ ! -s "temp.txt" ]; then
            log_warning "pdftotext a échoué. Tentative de conversion avec pdf2txt.py"
            python3 pdf2txt.py -o temp.txt temp.pdf
        fi

        # Si la conversion échoue, tenter l'OCR avec Tesseract
        if [ ! -f "temp.txt" ] || [ ! -s "temp.txt" ]; then
            log_warning "Échec de la conversion en texte, tentative d'extraction avec OCR (Tesseract)"
            pdftoppm temp.pdf temp_image -png
            tesseract temp_image-1.png temp_ocr_output
            mv temp_ocr_output.txt temp.txt
        fi

        if [ ! -f "temp.txt" ] || [ ! -s "temp.txt" ]; then
            log_warning "Échec de la conversion du PDF en texte même après OCR : $url"
            continue
        fi

        # Analyse du texte converti
        if grep -qiE 'confidentiel|usage interne seulement|password' temp.txt; then
            log_info "Fichier sensible détecté : $url"
            echo "$url" >> fichiers_sensibles.txt
        else
            log_info "Fichier non sensible : $url"
        fi

        # Nettoyage des fichiers temporaires
        rm -f temp.pdf temp.txt temp_image*.png temp_ocr_output.txt

        # Pause pour éviter la détection
        sleep_time=$((RANDOM % 6 + 5))
        log_info "Pause de $sleep_time secondes pour éviter la détection"
        sleep "$sleep_time"
    done <<< "$pdf_urls"
done

log_info "Script terminé"
