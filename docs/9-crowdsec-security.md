# Guide : Détection d'Intrusions & Bannissement IP Automatique (CrowdSec)

Ce document décrit l'installation de **CrowdSec** pour l'analyse des journaux HTTP/HTTPS de **Nginx Proxy Manager** et des accès **SSH** sur le serveur hôte Debian/OpenMediaVault.

---

## 1. Principes de Fonctionnement

CrowdSec est un système de détection et prévention d'intrusions (IDS/IPS) :
1. **Acquisition locale des journaux :** Lecture en continu des fichiers de logs Nginx Proxy Manager (`proxy-host-*_access.log`) et du service SSH (`/var/log/auth.log`).
2. **Détection par scénarios :** Identification des attaques applicatives courantes (tentatives d'accès aux fichiers sensibles `.env`, traversées de répertoires, scans de vulnérabilités, force brute SSH).
3. **Remédiation au niveau du pare-feu hôte (Firewall Bouncer) :** Le bouncer ajoute les adresses IP identifiées comme malveillantes directement dans `iptables` / `nftables` via des jeux `ipset`. Les paquets réseau sont rejetés en amont du reverse proxy.
4. **Réputation communautaire :** Synchronisation périodique avec la liste de consensus partagée des adresses IP malveillantes.

---

## 2. Déploiement du Moteur CrowdSec (Docker)

La configuration se trouve dans [`stacks/crowdsec/`](../stacks/crowdsec/) :

1. Accédez au répertoire de la stack :
   ```bash
   cd /srv/docker/stacks/crowdsec
   ```
2. Initialisez les variables d'environnement :
   ```bash
   cp .env.example .env
   ```
3. Démarrez le service :
   ```bash
   docker compose up -d
   ```
4. Vérifiez la présence des collections requises :
   ```bash
   docker exec crowdsec cscli collections list
   ```
   La sortie doit lister `crowdsecurity/nginx`, `crowdsecurity/sshd` et `crowdsecurity/http-cve`.

---

## 3. Installation du Bouncer Pare-Feu sur l'Hôte (Debian / OMV)

Le conteneur analyse les événements, tandis que le bouncer applique les règles de blocage dans la table de filtrage du système hôte :

1. Installez le paquet du bouncer via le dépôt officiel :
   ```bash
   curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash
   
   # Sur Debian 13 / Trixie (base OMV moderne), ajuster la source vers bookworm :
   sudo sed -i 's/trixie/bookworm/g' /etc/apt/sources.list.d/crowdsec_crowdsec.list
   sudo apt update

   sudo apt install -y crowdsec-firewall-bouncer-iptables
   ```
2. Enregistrez un nouveau bouncer auprès de la LAPI CrowdSec :
   ```bash
   docker exec crowdsec cscli bouncers add host-firewall
   ```
   Conservez la clé d'API générée.

3. Renseignez la clé d'API et le port d'écoute dans le fichier de configuration du bouncer :
   ```bash
   sudo nano /etc/crowdsec/bouncers/crowdsec-firewall-bouncer-iptables.yaml
   ```
   Ajustez les paramètres :
   ```yaml
   api_url: http://127.0.0.1:8085/
   api_key: <CLE_API_GENEREE>
   ```
4. Redémarrez le service du bouncer :
   ```bash
   sudo systemctl restart crowdsec-firewall-bouncer-iptables
   ```
5. Contrôlez l'état de validation :
   ```bash
   docker exec crowdsec cscli bouncers list
   ```
   L'enregistrement `host-firewall` doit présenter l'état `Valid`.

---

## 4. Commandes d'Administration et Supervision

```bash
# Lister les adresses IP actuellement bannies
docker exec crowdsec cscli decisions list

# Lister l'historique des alertes déclenchées
docker exec crowdsec cscli alerts list

# Supprimer manuellement un bannissement (adresse IP)
docker exec crowdsec cscli decisions delete --ip 1.2.3.4

# Afficher les métriques de parsing et d'acquisition de logs
docker exec crowdsec cscli metrics
```

---

[← Retour au README principal](../README.md)
