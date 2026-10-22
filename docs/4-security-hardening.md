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

### C. Nettoyage régulier de Docker (Éviter la saturation du SSD)
Au fur et à mesure des mises à jour d'images, Docker conserve les anciennes versions périmées. Pour libérer plusieurs gigaoctets sur votre SSD :
```bash
# Supprime les conteneurs arrêtés, les réseaux orphelins et les images non utilisées
docker system prune -a --volumes=false
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

## 6. Détection d'intrusion & Bannissement IP (Fail2ban / CrowdSec)

Exposer un reverse proxy signifie que des robots vont inévitablement scanner vos sous-domaines à la recherche de failles :

* **Principe** : En couplant Nginx Proxy Manager à **CrowdSec** ou **Fail2ban**, les journaux d'accès (`access.log` et `error.log`) sont analysés en temps réel.
* **Action automatique** : Dès qu'une adresse IP enchaîne plusieurs tentatives de connexion échouées (ex: 3 erreurs 401 sur Nextcloud ou Home Assistant), son adresse IP est automatiquement bannie au niveau du pare-feu `iptables` / `nftables` du serveur hôte pendant plusieurs heures.

---

## 7. Accès distant d'administration : VPN Mesh (Tailscale / WireGuard)

* **Règle d'or** : Ne rendez **JAMAIS** vos interfaces d'administration accessibles publiquement sur Internet (pas de sous-domaine public pour Portainer, OpenMediaVault, PufferPanel, ni pour le port 81 de Nginx Proxy Manager).
* **La méthode recommandée** :
  * Seuls les services destinés à un usage grand public (Jellyfin, Nextcloud, Vaultwarden) passent par le Reverse Proxy avec un sous-domaine.
  * Pour administrer le serveur depuis l'extérieur, installez un VPN moderne de type **Tailscale** ou **WireGuard**. Vous accédez à toutes les interfaces locales via une IP privée chiffrée de bout en bout, sans ouvrir le moindre port d'administration sur votre box Internet.

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

[← Retour au README principal](../README.md)
