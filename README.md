## Ajouter les dépôts de Tor :

### Ajoutez les dépôts de Tor dans votre fichier de sources. Ouvrez le fichier sources.list avec un éditeur de texte :

```bash
sudo nano /etc/apt/sources.list
```

### Ajoutez les lignes suivantes :

```plaintext
deb https://deb.torproject.org/torproject.org kali-rolling main
```

### Ajoutez la clé de signature des dépôts Tor :

* Téléchargez et ajoutez la clé pour authentifier les paquets Tor :

```bash
sudo apt install dirmngr
gpg --keyserver keys.openpgp.org --recv 74A941BA219EC810
gpg --export 74A941BA219EC810 | sudo apt-key add -
```

### Installez Tor depuis les dépôts :

* Après avoir ajouté les dépôts et la clé, mettez à jour les paquets et installez Tor :

```bash
sudo apt update
sudo apt install tor
```
### Lancer Tor :

* Une fois Tor installé, démarrez le service avec la commande :

```bash
sudo systemctl start tor
```

* Vous pouvez également vérifier si Tor fonctionne avec :

```bash
systemctl status tor
```
