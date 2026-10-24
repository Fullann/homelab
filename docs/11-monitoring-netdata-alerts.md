# Guide : Supervision Système Temps Réel (Netdata) & Alerting Push (Telegram / ntfy)

Ce document décrit le déploiement de **Netdata** pour la télémétrie matérielle et la santé de la grappe RAID 5, ainsi que la centralisation des notifications d'alertes critiques sur smartphone via **Telegram** ou **ntfy**.

---

## 1. Rôle et Architecture de Netdata

Tandis qu'**Uptime Kuma** vérifie la disponibilité applicative (requêtes HTTP 200 sur les sites web), **Netdata** assure la télémétrie matérielle et système en temps réel à la seconde près :
* **Surveillance du processeur & RAM :** Détection des goulots d'étranglement et de la saturation de la mémoire swap.
* **Intégrité de la grappe RAID 5 (`mdadm`) :** Détection immédiate d'un disque dégradé ou d'une reconstruction en cours sur `/dev/md0`.
* **Attributs S.M.A.R.T. et températures :** Surveillance continue de la température et du compteur de secteurs réalloués (*Reallocated Sector Count*) des 4 disques durs de 4 To.
* **I/O Wait du stockage :** Détection des ralentissements d'écriture sur le SSD système ou la grappe de stockage.

---

## 2. Déploiement de la Stack Netdata (Docker)

La configuration se trouve dans [`stacks/netdata/`](../stacks/netdata/) :

1. Accédez au répertoire de la stack :
   ```bash
   cd /srv/docker/stacks/netdata
   ```
2. Démarrez le service :
   ```bash
   docker compose up -d
   ```
3. Vérifiez les journaux d'exécution :
   ```bash
   docker logs netdata
   ```

### Accès au tableau de bord
* **Accès direct local :** `http://192.168.1.3:19999`
* **Accès via nom de domaine interne :** Dans Nginx Proxy Manager, créez un hôte `netdata.local` pointant vers `192.168.1.3:19999` (réservé au réseau local / Tailscale).

---

## 3. Centralisation des Alertes Push sur Smartphone (Telegram)

La mise en place d'un canal Telegram permet de recevoir instantanément les alertes du homelab sans coût et sans impacter la batterie de votre smartphone.

### Étape A : Créer un Bot Telegram
1. Ouvrez l'application **Telegram** et recherchez l'utilisateur officiel **`@BotFather`**.
2. Envoyez la commande `/newbot`.
3. Donnez un nom à votre bot (ex: `Homelab Monitor`) puis un identifiant unique (ex: `mon_homelab_alert_bot`).
4. `@BotFather` vous délivre un jeton d'API (*API Token*) sous la forme : `123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ`.
5. Ouvrez une conversation avec votre nouveau bot et appuyez sur **Démarrer** (`/start`).

### Étape B : Récupérer votre identifiant de discussion (`CHAT_ID`)
1. Recherchez l'utilisateur **`@userinfobot`** sur Telegram et envoyez un message.
2. Le bot vous répond avec votre `Id` numérique (ex: `987654321`).

---

## 4. Configuration des Alertes Netdata

1. Ouvrez un terminal dans le conteneur Netdata pour éditer la configuration d'alarme :
   ```bash
   docker exec -it netdata /etc/netdata/edit-config health_alarm_notify.conf
   ```
2. Renseignez les paramètres Telegram :
   ```bash
   # Activer l'envoi via Telegram
   SEND_TELEGRAM="YES"

   # Jeton du bot obtenu via @BotFather
   TELEGRAM_BOT_TOKEN="123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ"

   # Votre Chat ID obtenu via @userinfobot
   DEFAULT_RECIPIENT_TELEGRAM="987654321"
   ```
3. Testez l'envoi d'une alerte de test :
   ```bash
   docker exec -it netdata su -s /bin/bash netdata -c "/usr/libexec/netdata/plugins.d/alarm-notify.sh test"
   ```
   Vous recevez immédiatement un message d'alerte sur votre téléphone.

---

## 5. Intégration Telegram dans Uptime Kuma

Pour que les pannes applicatives arrivent dans le même canal Telegram :

1. Dans **Uptime Kuma** (`http://kuma.local/`), ouvrez **Paramètres** > **Notifications** > **Configurer une notification**.
2. Type de notification : **Telegram**.
3. Renseignez le **Bot Token** et le **Chat ID**.
4. Cliquez sur **Tester** puis **Sauvegarder**.
5. Cochez cette notification comme notification par défaut pour toutes vos sondes de surveillance.

---

## 6. Intégration Telegram dans le Script de Sauvegarde (`backup_nas.sh`)

Pour recevoir une notification automatique à la fin de chaque sauvegarde nocturne :

```bash
# Exemple d'appel en fin de script de sauvegarde
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
     -d chat_id="${TELEGRAM_CHAT_ID}" \
     -d text="✅ Sauvegarde Homelab réussie le $(date +'%d/%m/%Y à %H:%M')"
```

---

[← Retour au README principal](../README.md)
