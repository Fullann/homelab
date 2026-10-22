# 🚀 Tutoriel de Déploiement : De A à Z ou à la carte

Ce guide vous accompagne pas à pas pour déployer l'infrastructure complète ou sélectionner uniquement les modules qui vous intéressent.

---

## Option 1 : Déploiement complet de A à Z

Voici la procédure intégrale pour reconstruire ce serveur depuis zéro :

### 1. Préparation du système & du RAID dans OpenMediaVault
1. Installez Debian 12 puis OpenMediaVault sur le SSD `/dev/sde`.
2. Dans l'interface web OMV, allez dans **Stockage** > **Gestion du RAID** :
   * Cliquez sur le bouton **+** (Créer).
   * Nommez la grappe (ex: `nas-local-openmediavault`).
   * Sélectionnez le niveau **RAID 5** et cochez les 4 disques durs (`sda`, `sdb`, `sdc`, `sdd`).
   * Laissez la synchronisation se terminer.
3. Allez dans **Stockage** > **Systèmes de fichiers** :
   * Cliquez sur **+** > sélectionnez `/dev/md0` > choisissez le système de fichiers `ext4` et validez.
   * Cliquez sur l'icône **Monter** pour activer le point de montage `/srv/dev-disk-by-uuid-...`.
4. Allez dans **Stockage** > **Dossiers partagés** :
   * Créez les dossiers partagés racines : `media`, `nextcloud`, `photoprism`.

### 2. Préparation de Docker et du réseau privé
1. Dans OMV, installez le plugin `omv-extras` puis activez **Docker** et **Portainer**.
2. Connectez-vous en SSH à votre serveur et créez le réseau virtuel :
   ```bash
   docker network create proxy
   ```

### 3. Déploiement du Reverse Proxy (Point de départ obligatoire)
Déployez d'abord Nginx Proxy Manager pour pouvoir router les futurs services :
```bash
cd stacks/nginx-proxy-manager
docker compose up -d
```
Accédez à l'interface d'administration sur `http://IP_DE_VOTRE_SERVEUR:81` (identifiants par défaut : `admin@example.com` / `changeme`) et configurez vos accès.

### 4. Déploiement des stacks applicatives
Pour chaque dossier présent dans `stacks/` :
1. Si un fichier `.env.example` existe, copiez-le en `.env` :
   ```bash
   cp .env.example .env
   # Modifiez les mots de passe et le chemin de votre disque (/srv/dev-disk-by-uuid-...)
   ```
2. Lancez le service :
   ```bash
   docker compose up -d
   ```
3. Dans Nginx Proxy Manager, créez l'hôte de proxy correspondant avec son certificat SSL Let's Encrypt.

---

## Option 2 : Déploiement modulaire (Choisir uniquement une partie)

Vous n'avez pas besoin de tout déployer ! Le dépôt est conçu de façon **100% modulaire**.

### Scénario A : Vous voulez UNIQUEMENT la suite Multimédia (Jellyfin + Arr)
1. Créez le réseau : `docker network create proxy`.
2. Lancez les stacks multimédia :
   ```bash
   cd stacks/jellyfin && docker compose up -d
   cd ../arr && docker compose up -d
   cd ../prowlarr && docker compose up -d
   cd ../transmission && docker compose up -d
   ```
3. **Astuce sans Reverse Proxy** : Si vous ne voulez pas utiliser Nginx Proxy Manager et préférez y accéder directement via l'IP de votre serveur sur votre réseau local, ajoutez simplement la ligne `ports:` dans le `docker-compose.yml` :
   ```yaml
   services:
     jellyfin:
       # ...
       ports:
         - "8096:8096"
   ```

### Scénario B : Déploiement Domotique & Voix Locale (Home Assistant)
1. **Identification de la clé USB Zigbee** :
   Pour éviter les pannes dues à l'inversion aléatoire des ports (`/dev/ttyUSB0` devenant `/dev/ttyUSB1` au redémarrage), identifiez l'adresse persistante par ID de votre contrôleur :
   ```bash
   ls -l /dev/serial/by-id/
   ```
   Exemple de sortie :
   `usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_... -> ../../ttyUSB0`
   
   Dans [`stacks/homeauto/docker-compose.yml`](../stacks/homeauto/docker-compose.yml), utilisez cette référence exacte pour le mappage de Zigbee2MQTT :
   ```yaml
   devices:
     - /dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_...:/dev/ttyUSB0
   ```
2. Rendez-vous dans les dossiers des stacks domotiques :
   ```bash
   cd stacks/homeauto && docker compose up -d
   cd ../wyoming && docker compose up -d
   ```
3. Home Assistant est accessible sur le port interne `8123`.

### Scénario C : Déploiement du Gestionnaire de Mots de Passe (Vaultwarden)
1. Rendez-vous dans `stacks/vaultwarden`.
2. Les navigateurs modernes restreignent les API WebCrypto aux contextes sécurisés : **Vaultwarden nécessite obligatoirement un accès chiffré en HTTPS** :
   * Déployez Nginx Proxy Manager (`stacks/nginx-proxy-manager`).
   * Déployez Vaultwarden (`stacks/vaultwarden`).
   * Configurez un Proxy Host avec certificat SSL actif pointant vers `http://vaultwarden:80`.

---

[← Retour au README principal](../README.md)
