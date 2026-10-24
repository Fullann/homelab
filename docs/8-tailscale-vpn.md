# Guide : Accès Distant Sécurisé via VPN Mesh (Tailscale)

Ce document décrit l'installation et la configuration de **Tailscale** sur le serveur OpenMediaVault en tant que **Subnet Router** et **Exit Node**.

---

## 1. Rôle du Subnet Router Tailscale

Dans cette infrastructure, les interfaces d'administration internes (OpenMediaVault, Portainer, port 81 d'administration Nginx Proxy Manager, PufferPanel) ne sont pas exposées sur Internet.

Le mode **Subnet Router** permet :
* D'établir un tunnel chiffré WireGuard vers le réseau local sans ouvrir de port sur la passerelle Internet (traversée NAT automatique).
* D'accéder aux adresses IP privées du sous-réseau local (`192.168.1.0/24`) depuis n'importe quel équipement distant authentifié sur le tailnet.
* D'utiliser le serveur comme **Exit Node** pour router le trafic sortant des clients distants via la connexion réseau du homelab.

---

## 2. Étape 1 : Activer le routage IP sur l'hôte (Debian / OMV)

Pour autoriser le noyau Linux à relayer les paquets entre le tunnel Tailscale et le sous-réseau local (`192.168.1.0/24`), activez l'IP Forwarding :

```bash
# Activation de l'IP Forwarding IPv4 et IPv6
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf

# Application immédiate sans redémarrage
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

---

## 3. Étape 2 : Générer une clé d'authentification Tailscale

1. Connectez-vous sur la console d'administration [Tailscale](https://login.tailscale.com/admin/settings/keys).
2. Rendez-vous dans **Settings** > **Keys**.
3. Cliquez sur **Generate auth key** :
   * **Description** : `homelab-omv`
   * **Reusable** : activé (permet de recréer le conteneur sans régénérer de clé)
   * **Expiration** : 90 jours (ou selon votre politique)
   * **Pre-authorized** : activé (enregistrement direct sans validation manuelle supplémentaire)
4. Copiez la clé générée (`tskey-auth-...`).

---

## 4. Étape 3 : Déploiement de la Stack Docker

La configuration se trouve dans [`stacks/tailscale/`](../stacks/tailscale/) :

1. Accédez au répertoire de la stack :
   ```bash
   cd /srv/docker/stacks/tailscale
   ```
2. Créez le fichier d'environnement :
   ```bash
   cp .env.example .env
   ```
3. Renseignez la clé Tailscale dans `.env` :
   ```bash
   TS_AUTHKEY=tskey-auth-votre_cle_ici
   TS_ROUTES=192.168.1.0/24
   TS_EXTRA_ARGS=--advertise-exit-node
   ```
   > [!IMPORTANT]
   > Ne mettez pas de guillemets autour de `192.168.1.0/24`. Le parser réseau de Tailscale échoue avec une erreur `unexpected character` si des guillemets sont présents.

4. Démarrez le service :
   ```bash
   docker compose up -d
   ```
5. Contrôlez l'état d'enregistrement :
   ```bash
   docker logs tailscale
   ```
   Le journal doit indiquer `Success.` et confirmer l'enregistrement du nœud.

---

## 5. Étape 4 : Approuver le sous-réseau dans la console Tailscale

Par défaut, un nœud annonçant des routes réseau nécessite une approbation explicite de l'administrateur :

1. Ouvrez la liste des machines dans la console [Tailscale Machines](https://login.tailscale.com/admin/machines).
2. Repérez la machine `homelab-omv`.
3. Cliquez sur le menu contextuel (`...`) > **Edit route settings...**.
4. Cochez :
   * `192.168.1.0/24` (Subnet routes)
   * `Use as exit node` (optionnel)
5. Enregistrez la modification.

---

## 6. Étape 5 : Validation de l'Accès Distant

1. Installez le client Tailscale sur le terminal distant (iOS, Android, macOS, Linux, Windows).
2. Connectez-vous avec le même compte d'administration Tailscale.
3. Activez la connexion Tailscale.
4. Coupez le Wi-Fi local du client pour basculer sur un réseau externe (données cellulaires 4G/5G).
5. Testez la joignabilité directe des services internes :
   * Administration Nginx Proxy Manager : `http://192.168.1.3:81`
   * Interface OpenMediaVault : `http://192.168.1.3`
   * Portainer : `http://192.168.1.3:9000`

---

## 7. Commandes de Diagnostic

```bash
# Vérifier l'état de la connexion et les pairs actifs
docker exec tailscale tailscale status

# Tester la connectivité DERP et le NAT traversal
docker exec tailscale tailscale netcheck

# Afficher l'adresse IP Tailscale du nœud
docker exec tailscale tailscale ip -4
```

---

[← Retour au README principal](../README.md)
