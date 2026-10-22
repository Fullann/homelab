# 🌐 Architecture Réseau, "Zéro Port Exposé" & Split-DNS

Ce guide explique la stratégie réseau adoptée pour sécuriser les flux, éliminer l'ouverture aveugle de ports et optimiser la résolution DNS locale et distante.

---

## 1. Principe du "Zéro Port Exposé" (Réseau privé Docker)

Dans une installation classique non sécurisée, chaque service expose son port sur l'hôte (`ports: 8096:8096`, etc.), ce qui rend chaque application vulnérable aux scans et aux attaques directes.

### La solution : Le réseau bridge virtuel `proxy`

Tous les conteneurs sont connectés à un réseau privé virtuel Docker nommé **`proxy`** (`docker network create proxy`) :

1. **Aucun port sur l'hôte** : Aucun conteneur applicatif ne possède de directive `ports:`. Leurs ports ne sont écoutés qu'à **l'intérieur** du réseau virtuel Docker.
2. **DNS interne Docker** : Les conteneurs communiquent entre eux en utilisant simplement leur **nom de conteneur** (ex: `http://jellyfin:8096`, `http://nextcloud:80`, `http://vaultwarden:80`).
3. **Point d'entrée unique & sécurisé (SSL)** : Seul **Nginx Proxy Manager** écoute sur les ports `80` et `443` de l'hôte. Il gère le chiffrement HTTPS et redirige les requêtes en interne.

---

## 2. Les rares exceptions de ports exposés

Certains services nécessitent d'ouvrir un port direct sur l'hôte car ils ne communiquent pas en HTTP/HTTPS standard :

| Port Hôte | Service | Protocole | Pourquoi cette ouverture est obligatoire ? |
| :--- | :--- | :--- | :--- |
| **`80 / 443`** | **Nginx Proxy Manager** | TCP (HTTP/HTTPS) | Unique point d'entrée pour le trafic web chiffré et le renouvellement des certificats SSL. |
| **`51413`** | **Transmission** | TCP & UDP (BitTorrent) | Le téléchargement P2P nécessite que les autres pairs (peers) d'Internet puissent se connecter directement à votre client. |
| **`1883`** | **Mosquitto** | TCP (MQTT) | Permet aux capteurs domotiques physiques (ESP32, microcontrôleurs) du réseau local de publier leurs données de télémétrie. |
| **`5657`** | **PufferPanel** | TCP (SFTP) | Protocole de transfert de fichiers pour modifier les fichiers des serveurs de jeux. |
| **`53`** | **AdGuard Home** | UDP & TCP (DNS) | Serveur DNS pour intercepter et filtrer les requêtes de tous les appareils du réseau local. |

---

## 3. Configuration du Nom de Domaine chez le Registrar

Pour joindre votre Homelab depuis l'extérieur, un nom de domaine (acheté chez OVH, Cloudflare, Infomaniak, etc.) est configuré comme suit :

### A. Avec une adresse IP Publique Fixe
1. Créez une entrée **A** principale :
   ```text
   home.mondomaine.com.   IN A   <VOTRE_IP_PUBLIQUE>
   ```
2. Créez une entrée **CNAME Wildcard** :
   ```text
   *.mondomaine.com.      IN CNAME   home.mondomaine.com.
   ```
   *Grâce à cette wildcard `*`, n'importe quel sous-domaine (`jellyfin.mondomaine.com`, `nextcloud.mondomaine.com`, `vaultwarden.mondomaine.com`) pointe automatiquement vers votre box sans devoir créer 50 entrées DNS manuelles.*

### B. Avec une adresse IP Publique Dynamique (DDNS)
Si votre fournisseur d'accès change régulièrement votre adresse IP :
1. Utilisez un service DDNS (DuckDNS, No-IP ou Cloudflare DDNS).
2. Faites pointer votre wildcard dessus :
   ```text
   home.mondomaine.com.   IN CNAME   monhomelab.duckdns.org.
   *.mondomaine.com.      IN CNAME   home.mondomaine.com.
   ```

---

## 4. Fonctionnement du Split-DNS avec AdGuard Home

### Le problème sans Split-DNS : Le NAT Loopback (Hairpinning)
Si un client local sur le réseau Wi-Fi/LAN interroge `jellyfin.mondomaine.com` sans DNS local :
* Le client interroge les résolveurs DNS publics sur Internet.
* Le DNS renvoie l'adresse IP publique de la box.
* Le routeur/box doit renvoyer les paquets vers lui-même (*NAT Loopback / Hairpinning*). Selon le modèle de box, ce mécanisme est souvent instable, bridé en débit ou totalement désactivé.

### Solution avec AdGuard Home
AdGuard Home résout les requêtes DNS directement au sein du réseau local :
1. Dans l'interface AdGuard Home : **Filtres** > **Réécritures DNS** (*DNS Rewrites*).
2. Ajouter une règle :
   * **Domaine** : `*.mondomaine.com`
   * **Adresse IP** : `<IP_LOCALE_DU_SERVEUR>` (ex: `192.168.1.3`)

### Comportement réseau :
* **Accès extérieur (4G/5G/WAN)** : Résolution DNS publique -> IP WAN -> Routeur NAT ports 80/443 -> Nginx Proxy Manager.
* **Accès local (LAN/Wi-Fi)** : AdGuard Home résout immédiatement vers l'IP interne (`192.168.1.3`). Le trafic reste confiné au switch local à débit maximal (Gigabit/10G), tout en conservant la validité du certificat SSL Let's Encrypt.

---

## 5. Domaines purement locaux (`.home` ou `.local`)

Pour créer des adresses réservées exclusivement au réseau local (non accessibles depuis Internet) :

1. **Dans AdGuard Home** :
   * Ajoutez une réécriture DNS : `*.home` -> `192.168.1.100`.
2. **Dans Nginx Proxy Manager** :
   * Créez un Proxy Host avec le nom `portainer.home` pointant vers `http://portainer:9000`.
3. **Filtrage par Access Lists (NPM)** :
   Pour obtenir un certificat SSL valide sur une interface d'administration tout en bloquant l'accès externe, configurez une **Access List** dans NPM autorisant uniquement le sous-réseau local (`192.168.1.0/24`) et rejetant toute autre provenance (`Deny all`).

---

## 6. Intégration Reverse Proxy : Le cas Nextcloud (`config.php`)

Nextcloud intègre des contrôles stricts sur les en-têtes HTTP et les domaines de provenance. Lorsqu'il est placé derrière Nginx Proxy Manager, des avertissements ou des boucles de redirection surviennent si le fichier `config/config.php` n'est pas adapté.

### Paramètres indispensables dans `config/config.php`
Ajoutez ou ajustez les directives suivantes dans le tableau `$CONFIG` :

```php
  'trusted_domains' => 
  array (
    0 => '192.168.1.3:8080',
    1 => 'cloud.mondomaine.com',
  ),
  'trusted_proxies' => 
  array (
    0 => '172.16.0.0/12',    # Plage d'adresses du réseau Docker bridge
    1 => '192.168.1.0/24',    # Réseau local hôte
  ),
  'forwarded_for_headers' => 
  array (
    0 => 'HTTP_X_FORWARDED_FOR',
  ),
  'overwritehost' => 'cloud.mondomaine.com',
  'overwriteprotocol' => 'https',
  'overwritewebroot' => '',
  'overwrite.cli.url' => 'https://cloud.mondomaine.com',
```

* **`trusted_proxies`** : Autorise NPM à relayer la véritable adresse IP du client (nécessaire pour la détection brute-force de Nextcloud).
* **`overwriteprotocol => 'https'`** : Empêche Nextcloud de générer des URL internes en `http://`, ce qui résout les boucles de redirection et les erreurs de contenu mixte (*Mixed Content*).

### Configuration dans Nginx Proxy Manager
Dans l'hôte de proxy Nextcloud :
1. Onglet **Details** : Activer *Websockets Support* et *Block Common Exploits*.
2. Onglet **Custom locations** ou **Advanced** : Ajouter la résolution des services `.well-known` et la taille max d'envoi de fichiers :
   ```nginx
   client_max_body_size 10G;

   location /.well-known/carddav {
       return 301 $scheme://$host/remote.php/dav;
   }
   location /.well-known/caldav {
       return 301 $scheme://$host/remote.php/dav;
   }
   location /.well-known/webfinger {
       return 301 $scheme://$host/index.php/.well-known/webfinger;
   }
   location /.well-known/nodeinfo {
       return 301 $scheme://$host/index.php/.well-known/nodeinfo;
   }
   ```

---

## 7. 🛡️ Matrice d'Exposition : Services Internet vs Réseau Local

La règle élémentaire de sécurisation consiste à n'exposer publiquement que les services prévus pour la mobilité.

Voici la classification détaillée conteneur par conteneur :

### 🌐 Catégorie 1 : Exposable publiquement sur Internet (via Nginx Proxy Manager)
Ces services sont conçus dès l'origine pour une utilisation en mobilité et disposent d'un système robuste d'authentification et de gestion de sessions :

| Service | Sous-domaine recommandé | Pourquoi l'exposer ? | Précautions indispensables |
| :--- | :--- | :--- | :--- |
| **Jellyfin** | `jellyfin.mondomaine.com` | Permet le streaming de vos films/séries sur smartphone 4G ou TV chez des proches. | Mots de passe utilisateurs robustes, pas d'accès invité sans mot de passe. |
| **Jellyseerr** | `demandes.mondomaine.com` | Portail de requêtes moderne conçu pour être partagé avec vos amis/famille sans leur donner accès au serveur. | Authentification via comptes Jellyfin, limiter les quotas de requêtes. |
| **Nextcloud** | `cloud.mondomaine.com` | Synchronisation automatique des photos du téléphone, accès aux fichiers, contacts et agenda partout. | **Double authentification (2FA) obligatoire**, brute-force protection active. |
| **Collabora Online** | `office.mondomaine.com` | Nécessaire pour que Nextcloud puisse afficher et éditer des documents Office en direct. | Restreint au domaine Nextcloud via la variable `domain` dans le compose. |
| **PhotoPrism** | `photos.mondomaine.com` | Consultation de votre photothèque personnelle en déplacement. | Mot de passe administrateur fort, limiter les partages publics. |
| **Vaultwarden** | `passwords.mondomaine.com` | Synchronisation de votre coffre-fort de mots de passe sur vos mobiles/navigateurs. | **HTTPS obligatoire**, `- SIGNUPS_ALLOWED=false` pour bloquer les inscriptions, **2FA obligatoire**. |

---

### ⚠️ Catégorie 2 : Exposable avec précautions strictes (2FA / VPN recommandé)
Ces services sont utiles à distance mais présentent un risque si le mot de passe est faible :

| Service | Précautions nécessaires si exposé publiquement |
| :--- | :--- |
| **Home Assistant** | **Contrôle physique de votre domicile** (chauffage, lumières, volets, serrures). Si vous l'exposez : **2FA impératif**, mot de passe très complexe, et bannissement IP avec Fail2ban. *(Beaucoup d'utilisateurs préfèrent y accéder via VPN Tailscale pour zéro risque).* |
| **Uptime Kuma** | L'interface d'administration ne doit **PAS** être exposée. En revanche, Uptime Kuma permet de créer une **Page de Statut publique** (ex: `status.mondomaine.com`) pour afficher la disponibilité de vos services sans risque. |
| **PufferPanel** | Utile uniquement si des amis gèrent des serveurs de jeux avec vous. Nécessite des mots de passe robustes et le port SFTP 5657 doit être surveillé. |

---

### 🔒 Catégorie 3 : À garder STRICTEMENT EN LOCAL (ou via VPN Tailscale/WireGuard)
Ces conteneurs ne doivent **JAMAIS avoir de nom de domaine public** ni de port redirigé sur votre box Internet. Une intrusion sur l'un d'eux donnerait le contrôle de votre serveur ou de vos données privées :

| Service | Pourquoi il ne faut JAMAIS l'exposer sur Internet ? |
| :--- | :--- |
| **Portainer CE** | Donne un accès graphique direct à tout votre moteur Docker. Un attaquant qui y entre peut créer des conteneurs malveillants et prendre les droits root sur l'hôte. |
| **OpenMediaVault (WebUI)** | Panneau de contrôle maître de votre stockage et de votre RAID 5. Doit rester confiné au LAN. |
| **Homepage** | Fournit la cartographie complète de votre serveur, la liste de tous vos services, votre météo et votre topologie réseau. |
| **Radarr, Sonarr, Lidarr, Readarr** | Outils d'administration et d'automatisation backend. L'utilisateur final ne doit utiliser que **Jellyseerr** en façade. |
| **Prowlarr** | Contient l'ensemble de vos clés d'API et vos comptes de trackers torrent privés. |
| **Transmission (WebUI)** | L'interface web de téléchargement (9091) doit rester privée. Seul le port de transfert P2P (51413) écoute sur Internet. |
| **FlareSolverr** | Proxy interne sans aucune authentification. S'il était exposé, n'importe qui pourrait l'utiliser comme proxy ouvert. |
| **AdGuard Home (Web & DNS)** | Si vous exposez le port DNS 53 sur Internet, votre serveur devient un **Open DNS Resolver**, immédiatement exploité par des hackers pour lancer des attaques DDoS massives par amplification. |
| **Docker Socket Proxy** | API système Docker brute sans mot de passe. Réservée exclusivement aux conteneurs internes. |
| **MariaDB (Nextcloud & PhotoPrism)** | Bases de données relationnelles. Aucune raison d'avoir une ouverture extérieure. |
| **Mosquitto (MQTT)** | Ne doit écouter que sur le réseau local LAN pour vos capteurs ESP32. |
| **ESPHome** | Outil de flashage et programmation de microcontrôleurs. |
| **Wyoming (Piper/Whisper/WakeWord)** | Moteurs d'IA vocale internes sans interface utilisateur, dédiés à Home Assistant. |
| **Watchtower** | Service d'arrière-plan sans interface web. |

---

[← Retour au README principal](../README.md)

