# 🛡️ Guide des Bonnes Pratiques de Sécurité (Hardening)

Un homelab bien conçu ne doit pas seulement être pratique, il doit être **résistant aux intrusions, étanche et maintenable dans le temps**.

Ce guide compile les configurations de sécurité appliquées sur notre serveur hôte OpenMediaVault/Debian et au niveau de nos conteneurs Docker.

---

## 1. Sécurisation avancée de l'accès SSH

L'accès SSH est la porte maîtresse de votre serveur. Il doit être verrouillé contre les attaques par force brute :

### A. Utiliser des clés modernes Ed25519 (Bannir les mots de passe)
Générez une clé sur votre machine locale (Mac / Linux / Windows WSL) :
```bash
ssh-keygen -t ed25519 -C "admin-homelab"
```
Copiez la clé publique sur le serveur :
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@IP_SERVEUR
```

### B. Durcir la configuration du démon SSH (`/etc/ssh/sshd_config`)
Éditez le fichier de configuration SSH sur le serveur (`sudo nano /etc/ssh/sshd_config`) et appliquez ces réglages stricts :
```text
# Interdire formellement l'authentification par mot de passe
PasswordAuthentication no

# N'autoriser root que via une clé cryptographique
PermitRootLogin prohibit-password

# Désactiver les méthodes d'authentification obsolètes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
```
Redémarrez le service SSH pour appliquer les changements :
```bash
sudo systemctl restart ssh
```

> [!CAUTION]
> Gardez votre session SSH active et ouvrez un second terminal pour tester votre connexion avec la clé avant de fermer la première session !

### C. Ne JAMAIS ouvrir le port 22 sur votre Box Internet
Le port SSH ne doit **JAMAIS** être redirigé vers l'extérieur. Si vous devez vous connecter en SSH hors de chez vous, passez exclusivement par un VPN sécurisé (**Tailscale** ou **WireGuard**).

---

## 2. Maintenance et Mises à jour du Système Hôte (Debian / OMV)

Les conteneurs Docker n'assurent pas la mise à jour du noyau Linux ni des paquets système de base de Debian.

### A. La routine de mise à jour mensuelle
Connectez-vous en SSH et appliquez les correctifs de sécurité :
```bash
sudo apt update && sudo apt upgrade -y
```

### B. Activer les mises à jour de sécurité automatiques (`unattended-upgrades`)
Pour que les failles critiques de Debian soient colmatées automatiquement sans votre intervention :
```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades
```

### C. Nettoyage et Garbage Collection Docker (Éviter la saturation du SSD de 480 Go)
Au fur et à mesure des mises à jour continues par Watchtower, Docker accumule d'anciennes couches d'images et caches de compilation qui finissent par saturer le SSD système hôte.

Une triple stratégie sans risque pour vos données est en place :
1. **Purge automatique Watchtower** : Dans [`stacks/watchtower/docker-compose.yml`](../stacks/watchtower/docker-compose.yml), la variable `WATCHTOWER_CLEANUP=true` supprime instantanément l'ancienne image dès qu'un conteneur est mis à jour avec succès.
2. **Conteneur périodique `docker-gc`** : Un conteneur léger de Garbage Collection tourne en arrière-plan et purge toutes les 24h les images orphelines et caches de build âgés de plus de 7 jours (`docker image prune -af --filter "until=168h"`). Vos volumes de données persistantes ne sont **JAMAIS** impactés (`--volumes=false`).
3. **Script de maintenance manuelle** : Pour lancer un nettoyage à la demande et constater l'espace libéré :
```bash
./scripts/docker_system_clean.sh
```

---

## 3. Pare-feu du Socket Docker (`docker-socket-proxy`)

* **Le risque méconnu** : De nombreux tutoriels recommandent de monter directement le socket Docker sur des conteneurs :
  ```yaml
  # ⚠️ DANGEREUX : Donne un accès ROOT complet à l'hôte si le conteneur est compromis
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  ```
  Si un pirate trouve une faille dans un conteneur web, il peut s'échapper du conteneur (*container escape*) et prendre le contrôle total du serveur Debian/OMV.
* **La solution appliquée** : Utiliser un intermédiaire sécurisé comme `tecnativa/docker-socket-proxy`. Il agit comme un pare-feu applicatif API :
  * Il autorise uniquement les requêtes en lecture seule (`GET /containers`) pour lister les statuts.
  * Il bloque formellement les opérations sensibles (`POST`, création de volumes privilégiés, montages de disques système).

---

## 4. Principe du moindre privilège (`PUID` / `PGID`)

* **Le principe** : Par défaut, les processus à l'intérieur d'un conteneur Docker s'exécutent souvent en tant qu'utilisateur `root` (UID 0).
* **La bonne pratique** : Les images (notamment celles de *LinuxServer.io*) permettent de spécifier des identifiants non-root :
  ```yaml
  environment:
    - PUID=1000 # Utilisateur non privilégié sur l'hôte
    - PGID=1000 # Groupe partagé dédié
  ```
  Même si un attaquant réussit à exécuter du code arbitraire dans Jellyfin ou Sonarr, ses droits sur le système de fichiers du RAID 5 restent strictement limités à ceux de cet utilisateur standard.

---

## 5. Blindage de Vaultwarden (Gestionnaire de mots de passe)

Le coffre-fort de mots de passe est le composant le plus critique de votre Homelab :

1. **Désactiver les nouvelles inscriptions** :
   ```yaml
   environment:
     - SIGNUPS_ALLOWED=false # Empêche quiconque de créer un compte à votre insu
   ```
2. **Double Authentification (2FA / MFA) obligatoire** : Activez impérativement l'authentification à deux facteurs (via application TOTP comme *Aegis*, *2FAS*, *Ente Auth* ou clés matérielles FIDO2/WebAuthn YubiKey).
3. **Protection de la page admin** : Si vous utilisez la console d'administration (`/admin`), définissez un `ADMIN_TOKEN` très complexe (au moins 48 caractères générés aléatoirement) ou désactivez-la totalement.
4. **HTTPS impératif** : Les navigateurs modernes refusent de communiquer avec l'API WebCrypto de Bitwarden sans certificat SSL valide.

---

## 6. Détection d'intrusion & Authentification Unifiée (CrowdSec & Authelia)

Exposer un reverse proxy signifie que des robots scannent continuellement vos sous-domaines à la recherche de failles :

* **CrowdSec (Détection et bannissement temps réel)** : En couplant Nginx Proxy Manager à CrowdSec ([`stacks/crowdsec/`](../stacks/crowdsec/)), les journaux d'accès (`access.log` et `error.log`) et de SSH (`auth.log`) sont analysés en continu. Les adresses IP agressives sont immédiatement bannies au niveau du pare-feu `nftables` du serveur hôte.
  * Consultez le guide complet : [**Guide Détection d'Intrusions CrowdSec**](9-crowdsec-security.md).
* **Authelia (SSO & 2FA Unifié)** : Pour les applications qui ne disposent pas d'une double authentification native robuste (Radarr, Sonarr, Prowlarr, Transmission), **Authelia** ([`stacks/authelia/`](../stacks/authelia/)) intercepte les requêtes dans Nginx et exige un mot de passe + TOTP ou Passkey avant d'autoriser l'accès.
  * Consultez le guide complet : [**Guide Authentification Unique & 2FA Authelia**](10-authelia-sso-2fa.md).

---

## 7. Accès distant d'administration : VPN Mesh (Tailscale / WireGuard)

* **Règle d'or** : Ne rendez **JAMAIS** vos interfaces d'administration accessibles publiquement sur Internet (pas de sous-domaine public pour Portainer, OpenMediaVault, PufferPanel, ni pour le port 81 de Nginx Proxy Manager).
* **La méthode appliquée** :
  * Seuls les services destinés à un usage grand public (Jellyfin, Nextcloud, Vaultwarden) passent par le Reverse Proxy avec un sous-domaine.
  * Pour administrer le serveur depuis l'extérieur, nous déployons **Tailscale en mode Subnet Router** ([`stacks/tailscale/`](../stacks/tailscale/)). Vous accédez à toutes les interfaces locales via une IP privée chiffrée de bout en bout, sans ouvrir le moindre port d'administration sur votre box Internet.
  * Consultez le guide pas à pas complet : [**Guide Tailscale VPN & Subnet Router**](8-tailscale-vpn.md).

---

## 8. Le RAID 5 n'est PAS une sauvegarde (SMART & Règle 3-2-1)

> [!WARNING]
> Une grappe RAID 5 assure la **continuité de service matérielle**, mais elle **ne protège pas** contre les ransomwares, les erreurs humaines (`rm -rf`), les pannes simultanées de 2 disques ou les sinistres (vol, foudre, dégât des eaux).

1. **Surveillance S.M.A.R.T. et alertes automatiques** :
   * Dans OpenMediaVault (**Stockage** > **Disques** > **S.M.A.R.T.**), activez la surveillance de vos 4 disques de 4 To.
   * Planifiez des auto-tests courts quotidiens et un auto-test étendu mensuel.
   * Configurez les notifications par e-mail dans OMV (**Système** > **Notifications**) pour être prévenu à la première alerte de secteur défectueux (*Reallocated Sector Count*).
2. **La stratégie de sauvegarde 3-2-1** :
   * **3** copies de vos données les plus précieuses (bases de données Nextcloud, coffre Vaultwarden, photos de famille).
   * **2** supports différents (votre grappe RAID 5 locale + un disque dur externe branché périodiquement).
   * **1** copie hors-site (sauvegarde chiffrée envoyée sur un stockage cloud distant ou chez un proche avec des outils comme *Restic*, *BorgBackup* ou *Duplicati*).

---

---

## 9. Stratégie de Sauvegarde : Quotidienne locale & Hebdomadaire USB externe

Pour respecter la règle 3-2-1 sans complexité inutile, deux scripts complémentaires sont fournis dans le dossier [`scripts/`](../scripts/) :

### A. Sauvegarde hebdomadaire rapide sur disque externe USB 2 To ([`scripts/backup_nas.sh`](../scripts/backup_nas.sh))

Ce script est spécifiquement optimisé pour le disque externe branché une fois par semaine :
* **Performance maximale (2 à 5 minutes chrono)** : Utilise `rsync` incrémental pour ne transférer que les nouveaux fichiers créés dans la semaine (Nextcloud et PhotoPrism).
* **Zéro compression inutile sur les médias** : Les photos et vidéos étant déjà compressées, elles sont copiées directement. Seuls les dumps SQL et configurations textuelles sont compressés.
* **Exclusion stricte des caches** : Évite les centaines de milliers de fichiers temporaires de prévisualisation (`appdata_*/preview/*`), accélérant le transfert.
* **Couverture complète** : Sauvegarde MariaDB (Nextcloud et PhotoPrism), Vaultwarden (SQLite `.backup`), Home Assistant / Zigbee2MQTT et les certificats Nginx Proxy Manager.
* **Corbeille anti-suppression accidentelle (`--backup-dir`)** : Si un fichier a été supprimé sur le NAS, il est déplacé dans une corbeille datée sur le disque externe et conservé 30 jours au lieu d'être immédiatement perdu.
* **Sécurité à l'éjection** : Exécute automatiquement `sync` à la fin pour vider les tampons de mémoire vive vers le disque USB physique avant démontage.

**Utilisation** :
```bash
# 1. Brancher un disque USB sur le serveur (monté sur /media/disque_externe)
# 2. Lancer la sauvegarde :
sudo /srv/docker/scripts/backup_nas.sh

# 3. Démonter proprement à la fin :
sudo umount /media/disque_externe
```

### B. Sauvegarde quotidienne interne planifiée ([`scripts/backup.sh`](../scripts/backup.sh))

Pour automatiser la sauvegarde quotidienne des bases de données et configurations sur le volume de stockage local :

1. Dans l'interface OMV, allez dans **Système** > **Tâches planifiées** (*Scheduled Tasks*).
2. Cliquez sur **+** (Créer) :
   * **Activé** : Coché
   * **Minute** : `0` | **Heure** : `3` (03:00 du matin)
   * **Utilisateur** : `root`
   * **Commande** :
     ```bash
     /srv/docker/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
     ```
   * **Commentaire** : `Sauvegarde quotidienne locale des bases et configurations`
3. Enregistrez et appliquez les modifications.

---

## 10. Bonnes pratiques pour le versioning Git

Pour maintenir le dépôt public ou privé sans risque de fuite de données :
* **Vérifier `.gitignore`** : Ne jamais commiter de fichiers `.env`, clés privées (`.pem`, `.key`), bases de données (`.db`, `.sqlite3`) ou archives de sauvegarde.
* **Modèles `.env.example`** : Documenter systématiquement les variables requises avec des valeurs génériques.
* **Anonymisation** : Utiliser des noms de domaine fictifs (`mondomaine.com`) et masquer les adresses IP publiques dans la documentation.

---

## 11. Hygiène Système : Limitation & Rotation des Logs Docker

Par défaut, Docker stocke les journaux d'exécution de chaque conteneur au format JSON dans `/var/lib/docker/containers/...` **sans aucune limite de taille**.

### Le risque sur le SSD Système 480 Go
Des conteneurs générant beaucoup d'activité (Home Assistant, Ollama, AdGuard Home ou Watchtower) peuvent accumuler des dizaines de gigaoctets de logs au fil des mois, jusqu'à saturer totalement la partition racine (`/`). Une partition racine pleine paralyse Debian, bloque MariaDB et empêche le démarrage des conteneurs.

### La solution : Rotation centralisée (`/etc/docker/daemon.json`)
Pour plafonner automatiquement les logs de l'ensemble des conteneurs sans devoir éditer chaque `docker-compose.yml` individuellement :

1. Créez ou modifiez le fichier `/etc/docker/daemon.json` sur l'hôte :
   ```json
   {
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "50m",
       "max-file": "3"
     }
   }
   ```
2. Redémarrez le service Docker pour appliquer la politique :
   ```bash
   sudo systemctl restart docker
   ```

* **Effet immédiat** : Chaque conteneur ne conserve que **3 fichiers de 50 Mo au maximum** (soit un plafond garanti de **150 Mo maximum par service**).

> [!TIP]
> Un script d'application automatisé en une seule commande est disponible dans le dépôt :
> ```bash
> sudo /srv/docker/scripts/setup_docker_log_rotation.sh
> ```

---

## 12. Optimisation Mémoire : Réglage de la Swappiness & Dimensionnement du Swap

Par défaut, Debian utilise un paramètre de déclenchement du swap (`vm.swappiness`) réglé à **60** et crée une partition swap minimale (~976 Mo).

### Le problème avec les conteneurs Docker
Sur un serveur exécutant de multiples conteneurs, une swappiness élevée pousse le noyau Linux à décharger prématurément des pages mémoire vers le swap, saturant rapidement une petite partition et déclenchant des alarmes critiques de supervision (ex: Netdata), même avec plus de 10 Go de mémoire vive libre.

### Les bonnes pratiques appliquées
1. **Abaisser la swappiness à 10** pour forcer l'usage prioritaire de la mémoire vive physique :
   ```bash
   sudo sysctl vm.swappiness=10
   echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
   ```
2. **Dimensionner un fichier swap de 4 Go** sur le SSD système pour absorber les pics ponctuels de charge sans saturation :
   ```bash
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

---

[← Retour au README principal](../README.md)
