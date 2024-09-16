# PowerShell Script: OsintScrapper.ps1

# Liste des user-agents
$userAgents = @(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3",
    "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:40.0) Gecko/20100101 Firefox/40.1",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/601.3.9 (KHTML, like Gecko) Version/9.0.2 Safari/601.3.9",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.77 Safari/537.36"
)

# Fonction pour choisir un user-agent aléatoire
function Get-RandomUserAgent {
    return $userAgents | Get-Random
}

# Fonction pour journaliser les informations
function Log-Info {
    $message = "[INFO] $args"
    Write-Output $message
    Add-Content -Path "script.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
}

# Fonction pour journaliser les erreurs
function Log-Error {
    $message = "[ERREUR] $args"
    Write-Output $message
    Add-Content -Path "script.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
}

# Fonction pour journaliser les avertissements
function Log-Warning {
    $message = "[AVERTISSEMENT] $args"
    Write-Output $message
    Add-Content -Path "script.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message"
}

# Vérification de la connexion Tor
Log-Info "Vérification de la connexion à Tor"
try {
    $torCheck = Invoke-WebRequest -Uri "https://check.torproject.org/" -UseBasicParsing -Proxy "http://127.0.0.1:9050" -ProxyUseDefaultCredentials
    if ($torCheck.Content -notmatch "Congratulations. This browser is configured to use Tor.") {
        Log-Error "La connexion Tor ne fonctionne pas correctement."
        exit 1
    } else {
        Log-Info "Connexion Tor confirmée."
    }
} catch {
    Log-Error "Impossible de vérifier la connexion Tor."
    exit 1
}

# Démarrage du script
Log-Info "Démarrage du script de scraping avec Tor"

# Liste des Google Dorks à utiliser
$dorks = @(
    "filetype:xls OR filetype:xlsx intext:confidential",
    "site:edu filetype:pdf budget OR finance",
    "filetype:txt intext:password"
)

# Boucle sur chaque dork pour effectuer les recherches
foreach ($dork in $dorks) {
    Log-Info "Recherche de fichiers PDF via DuckDuckGo avec le terme : $dork"
    Start-Sleep -Seconds 5  # Pause pour s'assurer que la connexion Tor est stable

    try {
        # Exécution de la requête avec journalisation détaillée
        $searchResults = Invoke-WebRequest -Uri "https://html.duckduckgo.com/html?q=${dork -replace ' ', '+'}" -Headers @{ 'User-Agent' = (Get-RandomUserAgent) } -Proxy "http://127.0.0.1:9050" -UseBasicParsing -ProxyUseDefaultCredentials
        $pdfUrls = Select-String -InputObject $searchResults.Content -Pattern 'https?://\S+\.pdf' -AllMatches | ForEach-Object { $_.Matches.Value }

        if ($pdfUrls.Count -eq 0) {
            Log-Info "Aucune URL de fichier PDF trouvée pour le dork : $dork."
        } else {
            Log-Info "Nombre d'URLs trouvées pour le dork $dork : $($pdfUrls.Count)"
        }

        # Boucle sur chaque URL trouvée
        foreach ($url in $pdfUrls) {
            Log-Info "Fichier PDF trouvé : $url"

            # Vérification de l'accessibilité de l'URL
            try {
                $httpStatus = (Invoke-WebRequest -Uri $url -Method HEAD -Proxy "http://127.0.0.1:9050" -UseBasicParsing -ProxyUseDefaultCredentials).StatusCode
                if ($httpStatus -ne 200) {
                    Log-Warning "Impossible d'accéder au fichier $url (HTTP $httpStatus)"
                    continue
                }
            } catch {
                Log-Warning "Impossible d'accéder au fichier $url"
                continue
            }

            # Téléchargement du PDF pour analyse
            Log-Info "Téléchargement du fichier $url"
            Invoke-WebRequest -Uri $url -OutFile "temp.pdf" -Headers @{ 'User-Agent' = (Get-RandomUserAgent) } -Proxy "http://127.0.0.1:9050" -UseBasicParsing -ProxyUseDefaultCredentials

            if (-not (Test-Path "temp.pdf" -PathType Leaf)) {
                Log-Warning "Le fichier téléchargé est vide ou n'a pas été correctement téléchargé : $url"
                continue
            }

            # Essayer de convertir avec pdftotext
            Log-Info "Tentative de conversion du fichier PDF en texte avec pdftotext"
            Start-Process -FilePath "pdftotext" -ArgumentList "temp.pdf temp.txt" -NoNewWindow -Wait
            if (-not (Test-Path "temp.txt" -PathType Leaf)) {
                Log-Warning "pdftotext a échoué. Tentative de conversion avec pdf2txt.py"
                Start-Process -FilePath "pdf2txt.py" -ArgumentList "-o temp.txt temp.pdf" -NoNewWindow -Wait
            }

            # Si la conversion échoue toujours, essayez l'OCR avec tesseract
            if (-not (Test-Path "temp.txt" -PathType Leaf)) {
                Log-Warning "Échec de la conversion en texte, tentative d'extraction avec OCR (tesseract)"
                Start-Process -FilePath "pdftoppm" -ArgumentList "-png temp.pdf temp_image" -NoNewWindow -Wait
                Start-Process -FilePath "tesseract" -ArgumentList "temp_image-1.png temp_ocr_output" -NoNewWindow -Wait
                Get-Content "temp_ocr_output.txt" | Out-File "temp.txt"
            }

            if (-not (Test-Path "temp.txt" -PathType Leaf)) {
                Log-Warning "Échec de la conversion du PDF en texte même après OCR : $url"
                continue
            }

            # Analyse du texte converti
            $text = Get-Content -Path "temp.txt" -Raw
            if ($text -match 'confidentiel|usage interne seulement|password') {
                Log-Info "Fichier sensible détecté : $url"
                $url | Out-File -Append -FilePath "fichiers_sensibles.txt"
            } else {
                Log-Info "Fichier non sensible : $url"
            }

            # Nettoyage des fichiers temporaires
            Remove-Item "temp.pdf", "temp.txt", "temp_image*.png", "temp_ocr_output.txt" -Force

            # Pause pour éviter la détection
            $sleepTime = Get-Random -Minimum 5 -Maximum 10
            Log-Info "Pause de $sleepTime secondes pour éviter la détection"
            Start-Sleep -Seconds $sleepTime
        }
    } catch {
        Log-Error "Erreur lors de l'exécution du dork : $dork"
        continue
    }
}

Log-Info "Script terminé"
