# Guide : Tableau de Bord Unifié & Widgets Dynamiques (Homepage)

Ce document décrit la configuration du portail d'accueil **Homepage** ([`stacks/homepage/`](../stacks/homepage/)), la gestion du double adressage réseau (services locaux en `.local` vs services publics en `domaine.com`), et l'interfaçage des widgets via les API applicatives.

---

## 1. Architecture du Double Adressage Réseau

Homepage regroupe l'accès à l'ensemble de votre infrastructure selon une logique de sécurité stricte :

| Zone d'accès | Domaine / URL | Exemples de services | Règle d'exposition |
| :--- | :--- | :--- | :--- |
| **Zone Privée Locale** | `http://<service>.local` | Radarr, Sonarr, Transmission, Prowlarr, OMV, Portainer, Netdata | Accessible uniquement depuis le LAN ou à distance via **Tailscale**. Aucune exposition sur Internet. |
| **Zone Publique Sécurisée** | `https://<service>.domaine.com` | Nextcloud, PhotoPrism, Vaultwarden, Authelia | Accessible sur Internet via Nginx Proxy Manager avec certificat SSL et 2FA. |

---

## 2. Fonctionnement des Widgets Dynamiques

Homepage utilise une double communication :
1. **Lien de navigation (`href`) :** C'est l'URL sur laquelle votre navigateur clique (`http://radarr.local` ou `https://cloud.domaine.com`).
2. **Liaison API interne (`widget.url`) :** Homepage communique directement de conteneur à conteneur via le réseau Docker partagé (`proxy`), par exemple `http://radarr:7878` ou `http://transmission:9091`. Cette communication est instantanée et n'utilise pas votre bande passante internet.

---

## 3. Où Récupérer les Clés d'API de vos Services ?

Pour que les widgets affichent les statistiques en direct dans [`stacks/homepage/config/services.yaml`](../stacks/homepage/config/services.yaml) :

### A. Radarr & Sonarr
1. Ouvrez l'interface (ex: `http://radarr.local/`).
2. Rendez-vous dans **Settings** > **General** > section **Security**.
3. Copiez la valeur du champ **API Key**.
4. Collez la clé dans `services.yaml` sous le champ `key:` du widget.

### B. Prowlarr
1. Rendez-vous dans **Settings** > **General** > **API Key**.
2. Copiez la clé et collez-la sous `key:` pour le widget Prowlarr.

### C. Jellyfin
1. Rendez-vous dans le tableau de bord administrateur (**Administration** > **Tableau de bord**).
2. Dans le menu de gauche, cliquez sur **Clés d'API**.
3. Cliquez sur **+** pour créer une clé nommée `Homepage`.
4. Copiez la clé générée et collez-la sous `key:`.

### D. Jellyseerr
1. Rendez-vous dans **Paramètres** > **Général**.
2. Copiez la **Clé d'API** générée.

### E. Transmission
Transmission n'utilise pas de clé d'API. Le widget interroge directement le port RPC interne :
```yaml
widget:
  type: transmission
  url: http://transmission:9091
```

---

## 4. Surveillance du Stockage RAID 5 (12 To) & SSD Système

Grâce au montage en lecture seule dans [`stacks/homepage/docker-compose.yml`](../stacks/homepage/docker-compose.yml) :
* Le SSD système 480 Go est surveillé sur `/`.
* La grappe RAID 5 de 12 To (`/dev/md0`) est montée sur `/data`.

Dans [`stacks/homepage/config/widgets.yaml`](../stacks/homepage/config/widgets.yaml), le widget affiche l'état en temps réel des deux disques dans la barre d'en-tête :

```yaml
- resources:
    label: Système
    cpu: true
    memory: true
    celsius: true
    disk:
      - /
      - /data
```

---

## 5. Application des Modifications

Après avoir renseigné vos clés d'API dans `services.yaml` :

```bash
cd /srv/docker/stacks/homepage
docker compose restart homepage
```

## 6. Résolution des Problèmes Courants (Dépannage des Widgets)

| Problème / Message d'erreur | Cause technique | Solution à appliquer dans `services.yaml` |
| :--- | :--- | :--- |
| **AdGuard : `ENOTFOUND adguardhome`** | AdGuard Home utilise `network_mode: host` et ne possède pas de nom d'hôte sur le réseau Docker virtuel `proxy`. | Remplacer `http://adguardhome:80` par l'adresse IP physique du NAS et son port web : `http://192.168.1.3:3000`. |
| **Jellyfin : `Unexpected end of JSON input`** | Les versions récentes de Jellyfin ont supprimé le préfixe d'API `/emby/`. Homepage v1 interroge ces anciennes routes qui renvoient une réponse vide (0 octet). | Ajouter `version: 2` et `enableBlocks: true` dans le bloc widget de Jellyfin. |
| **Uptime Kuma : `Unexpected token '<'`** | Le widget Homepage exige une **Page de Statut** publique. Si aucune page avec le slug indiqué (`default`) n'existe, Kuma renvoie une page 404 en HTML (`<html>...`). | Dans Uptime Kuma, créer une page de statut nommée `default` (ou adapter le champ `slug:` dans `services.yaml`). |
| **Portainer : Dossier `config/` introuvable** | Les chemins relatifs `./config` créés dans l'éditeur de Portainer sont stockés dans un sous-dossier obscur de `/var/lib/docker/volumes/...`. | Dans Portainer, utiliser un chemin absolu : `/srv/docker/homepage/config:/app/config`. |

---

[← Retour au README principal](../README.md)
