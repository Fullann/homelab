#!/bin/bash
# ==============================================================================
# 🔐 Sauvegarde Distante Chiffrée (Zero-Knowledge) vers o2switch via SFTP & Restic
# Conçu pour :
#   - Exporter à chaud les bases de données (MariaDB, PhotoPrism, Vaultwarden)
#   - Chiffrer de bout en bout en AES-256 / ChaCha20 avant transmission
#   - Synchroniser en incrémental dédupliqué via SFTP vers o2switch
#   - Purger les snapshots selon la politique de rétention
#   - Notifier en push via ntfy (succès et alertes)
# ==============================================================================

set -uo pipefail

START_TIME=$SECONDS
ENV_FILE="/etc/homelab-restic.env"

# 1. Chargement de la configuration
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "[-] ERREUR : Le fichier de configuration $ENV_FILE est introuvable !"
    echo "    Copiez scripts/restic.env.example vers $ENV_FILE et complétez vos identifiants."
    exit 1
fi

export RESTIC_PASSWORD="${RESTIC_PASSWORD:?Mot de passe Restic manquant}"
SFTP_USER="${SFTP_USER:?Utilisateur SFTP o2switch manquant}"
SFTP_HOST="${SFTP_HOST:?Hôte SFTP o2switch manquant}"
SFTP_PORT="${SFTP_PORT:-22}"
SFTP_PATH="${SFTP_PATH:-/home/${SFTP_USER}/backups_homelab}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/root/.ssh/id_o2switch}"
NTFY_URL="${NTFY_URL:-http://localhost:2586/homelab-backups}"

# Configuration automatique de l'alias SSH dans ~/.ssh/config si absent
SSH_CONFIG_FILE="/root/.ssh/config"
if ! grep -q "Host o2switch-backup" "$SSH_CONFIG_FILE" 2>/dev/null; then
    mkdir -p /root/.ssh
    cat <<EOF >> "$SSH_CONFIG_FILE"

Host o2switch-backup
    Hostname ${SFTP_HOST}
    User ${SFTP_USER}
    Port ${SFTP_PORT}
    IdentityFile ${SSH_KEY_PATH}
    StrictHostKeyChecking accept-new
EOF
    chmod 600 "$SSH_CONFIG_FILE"
fi

RESTIC_REPO="sftp:o2switch-backup:${SFTP_PATH}"

TMP_DUMP_DIR="/tmp/restic_dumps_$$"

# Fonction d'envoi d'alerte ntfy
notify_ntfy() {
    local title="$1"
    local message="$2"
    local priority="$3"
    local tags="$4"

    if [ -n "$NTFY_URL" ]; then
        curl -s \
            -H "Title: $title" \
            -H "Priority: $priority" \
            -H "Tags: $tags" \
            -d "$message" \
            "$NTFY_URL" >/dev/null 2>&1 || true
    fi
}

# Gestion des erreurs
trap 'echo "[-] ERREUR critique à la ligne $LINENO"; notify_ntfy "⚠️ Échec Sauvegarde Distante o2switch" "Une erreur est survenue lors de la sauvegarde chiffrée (ligne $LINENO)." "urgent" "warning,skull"; rm -rf "$TMP_DUMP_DIR"; exit 1' ERR

echo "========================================================================"
echo "[$(date +'%T')] 🚀 Démarrage de la sauvegarde chiffrée distante vers o2switch..."
echo "========================================================================"

mkdir -p "$TMP_DUMP_DIR"

# 2. Exports SQL et Snapshots cohérents des bases de données
echo "[+] [1/4] Snapshot des bases de données en cours..."

# A. Nextcloud (MariaDB)
if docker ps --format '{{.Names}}' | grep -q "^mariadb$"; then
    echo "    -> Export SQL Nextcloud MariaDB..."
    docker exec mariadb mariadb-dump -u root --all-databases > "$TMP_DUMP_DIR/nextcloud_databases.sql" 2>/dev/null || true
fi

# B. PhotoPrism (MariaDB)
if docker ps --format '{{.Names}}' | grep -q "^photoprism-db$"; then
    echo "    -> Export SQL PhotoPrism MariaDB..."
    docker exec photoprism-db mariadb-dump -u root --all-databases > "$TMP_DUMP_DIR/photoprism_databases.sql" 2>/dev/null || true
fi

# C. Coffre-fort Vaultwarden (SQLite)
if [ -d "/srv/docker/vaultwarden/data" ]; then
    echo "    -> Snapshot cohérent du coffre Vaultwarden..."
    mkdir -p "$TMP_DUMP_DIR/vaultwarden"
    cp -r /srv/docker/vaultwarden/data/rsa_key* "$TMP_DUMP_DIR/vaultwarden/" 2>/dev/null || true
    cp -r /srv/docker/vaultwarden/data/attachments "$TMP_DUMP_DIR/vaultwarden/" 2>/dev/null || true
    if command -v sqlite3 >/dev/null 2>&1 && [ -f "/srv/docker/vaultwarden/data/db.sqlite3" ]; then
        sqlite3 "/srv/docker/vaultwarden/data/db.sqlite3" ".backup '$TMP_DUMP_DIR/vaultwarden/db.sqlite3'"
    else
        cp /srv/docker/vaultwarden/data/db.sqlite3* "$TMP_DUMP_DIR/vaultwarden/" 2>/dev/null || true
    fi
fi

# 3. Exécution de la sauvegarde Restic
echo "[+] [2/4] Chiffrement local et transmission incrémentale SFTP vers o2switch..."

# Liste des répertoires sensibles à sauvegarder
BACKUP_TARGETS=("$TMP_DUMP_DIR")

# Ajout des configurations Docker (compose, .env, configs yaml)
if [ -d "/srv/docker" ]; then
    BACKUP_TARGETS+=("/srv/docker")
fi

# Ajout des configurations domotiques Home Assistant
if [ -d "/root/homeauto" ]; then
    BACKUP_TARGETS+=("/root/homeauto")
fi

# Exécution de Restic avec chiffrement côté client
restic -r "$RESTIC_REPO" \
       backup "${BACKUP_TARGETS[@]}" \
       --exclude="*.log" \
       --exclude="*.tmp" \
       --exclude="cache" \
       --exclude="Cache" \
       --tag "homelab-sensitive" \
       --verbose

# 4. Nettoyage du dossier temporaire
rm -rf "$TMP_DUMP_DIR"

# 5. Rotation et purge des anciens snapshots Restic
echo "[+] [3/4] Application de la politique de rétention des snapshots..."
restic -r "$RESTIC_REPO" \
       forget \
       --keep-daily "${KEEP_DAILY:-7}" \
       --keep-weekly "${KEEP_WEEKLY:-4}" \
       --keep-monthly "${KEEP_MONTHLY:-6}" \
       --prune

ELAPSED=$(( SECONDS - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo "========================================================================"
echo "✅ Sauvegarde chiffrée distante terminée avec succès en ${MINUTES}m ${SECS}s !"
echo "========================================================================"

# 6. Notification ntfy
notify_ntfy "🔐 Sauvegarde Distante o2switch Réussie" \
            "Données sensibles chiffrées (Zero-Knowledge) et synchronisées vers o2switch en ${MINUTES}m ${SECS}s." \
            "default" \
            "lock,shield,white_check_mark"
