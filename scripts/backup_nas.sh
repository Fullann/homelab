#!/bin/bash
# ==============================================================================
# 💾 Script de Sauvegarde Hebdomadaire Rapide sur Disque Externe USB (2 To)
# Conçu pour être exécuté manuellement ou automatiquement dès le branchement du disque.
# Vitesse optimisée : Rsync incrémental + snapshot BDD + exclusion des caches.
# ==============================================================================

set -uo pipefail

START_TIME=$SECONDS

# ==============================================================================
# 1. CONFIGURATION & CHEMINS
# ==============================================================================
# Fichier d'environnement optionnel pour sécuriser les mots de passe (recommandé)
ENV_FILE="/etc/homelab-backup.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

DATE=$(date +'%Y-%m-%d_%Hh%M')

# Point de montage du disque dur externe USB (2 To)
MOUNT_POINT="${MOUNT_POINT:-/media/disque_externe}"
DEST_BASE="$MOUNT_POINT/backups_nas"

# Répertoires de destination sur le disque externe
BACKUP_DB="$DEST_BASE/databases"
BACKUP_CONFIGS="$DEST_BASE/configurations"
BACKUP_NEXTCLOUD="$DEST_BASE/nextcloud"
BACKUP_PHOTOPRISM="$DEST_BASE/photoprism"
BACKUP_TRASH="$DEST_BASE/corbeille_suppressions"

# Répertoire source du volume RAID 5 OpenMediaVault
DISK_ROOT="/srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45"
DATA_NEXTCLOUD="$DISK_ROOT/nextcloud"
DATA_PP_STORAGE="$DISK_ROOT/photoprism"
DATA_PP_IMPORT="$DISK_ROOT/media/PHOTO_IMPORT"

# Identifiants bases de données (avec valeurs par défaut si non définies dans /etc/homelab-backup.env)
NC_DB_CONTAINER="${NC_DB_CONTAINER:-mariadb}"
NC_DB_USER="${NC_DB_USER:-nextcloud_usr}"
NC_DB_PASS="${NC_DB_PASS:-change_me_user_password}"
NC_DB_NAME="${NC_DB_NAME:-nextcloud_db}"

PP_DB_CONTAINER="${PP_DB_CONTAINER:-photoprism-db}"
PP_DB_USER="${PP_DB_USER:-photoprism}"
PP_DB_PASS="${PP_DB_PASS:-change_me_db_password}"
PP_DB_NAME="${PP_DB_NAME:-photoprism}"

# Durée de rétention des archives et corbeille (en jours)
RETENTION_DAYS=60        # ~8 semaines d'historique pour les dumps BDD et configs
TRASH_RETENTION_DAYS=30  # Les fichiers effacés sont conservés 30 jours avant purge

# ==============================================================================
# 2. VÉRIFICATIONS PRÉALABLES
# ==============================================================================
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "[-] ERREUR : Le disque externe 2 To n'est pas monté sur $MOUNT_POINT !"
    echo "    Veuillez brancher et monter le disque avant d'exécuter la sauvegarde."
    exit 1
fi

mkdir -p "$BACKUP_DB" "$BACKUP_CONFIGS" "$BACKUP_NEXTCLOUD" "$BACKUP_PHOTOPRISM" "$BACKUP_TRASH"
echo "========================================================================"
echo "🚀 Démarrage de la sauvegarde hebdomadaire ($DATE)"
echo "   Cible : $DEST_BASE"
echo "========================================================================"

# ==============================================================================
# 3. SÉCURITÉ : SORTIE SYSTÉMATIQUE DU MODE MAINTENANCE NEXTCLOUD
# ==============================================================================
# Détection de l'utilisateur interne Nextcloud (www-data, 48 ou 33)
NC_USER="www-data"
if docker ps --format '{{.Names}}' | grep -q "^nextcloud$"; then
    if ! docker exec nextcloud id www-data >/dev/null 2>&1; then
        NC_USER="48"
    fi
fi

cleanup() {
    if docker ps --format '{{.Names}}' | grep -q "^nextcloud$"; then
        echo "[+] [Sécurité] Désactivation du mode maintenance Nextcloud..."
        docker exec -u "$NC_USER" nextcloud php /app/www/public/occ maintenance:mode --off >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# ==============================================================================
# 4. EXPORT DES BASES DE DONNÉES (Rapide & non bloquant)
# ==============================================================================
# Nextcloud : Passage en mode maintenance bref pour figer l'état
if docker ps --format '{{.Names}}' | grep -q "^nextcloud$"; then
    echo "[+] [1/6] Activation temporaire du mode maintenance Nextcloud..."
    docker exec -u "$NC_USER" nextcloud php /app/www/public/occ maintenance:mode --on >/dev/null 2>&1 || true
fi

# Export SQL Nextcloud (sans exposer le mot de passe dans 'ps aux' via MYSQL_PWD)
if docker ps --format '{{.Names}}' | grep -q "^${NC_DB_CONTAINER}$"; then
    echo "[+] [2/6] Export SQL de la base Nextcloud (mariadb)..."
    docker exec -e MYSQL_PWD="$NC_DB_PASS" "$NC_DB_CONTAINER" mariadb-dump \
        -u "$NC_DB_USER" \
        --single-transaction \
        --quick \
        "$NC_DB_NAME" | gzip -1 > "$BACKUP_DB/nextcloud_${DATE}.sql.gz"
fi

# Réouverture immédiate de Nextcloud dès que le dump SQL est terminé pour minimiser l'interruption
if docker ps --format '{{.Names}}' | grep -q "^nextcloud$"; then
    echo "[+] [Nextcloud] Réactivation de l'accès utilisateur..."
    docker exec -u "$NC_USER" nextcloud php /app/www/public/occ maintenance:mode --off >/dev/null 2>&1 || true
fi

# Export SQL PhotoPrism
if docker ps --format '{{.Names}}' | grep -q "^${PP_DB_CONTAINER}$"; then
    echo "[+] [3/6] Export SQL de la base PhotoPrism..."
    docker exec -e MYSQL_PWD="$PP_DB_PASS" "$PP_DB_CONTAINER" mariadb-dump \
        -u "$PP_DB_USER" \
        --single-transaction \
        --quick \
        "$PP_DB_NAME" | gzip -1 > "$BACKUP_DB/photoprism_${DATE}.sql.gz"
fi

# ==============================================================================
# 5. SAUVEGARDE DES COMPOSANTS CRITIQUES (Vaultwarden, HA, NPM, Homepage)
# ==============================================================================
echo "[+] [4/6] Archivage rapide des configurations et coffres..."

# A. Vaultwarden (Base de données SQLite transactionnelle & clés RSA)
if [ -d "/srv/docker/vaultwarden/data" ]; then
    echo "    - Coffre Vaultwarden (mots de passe & clés chiffrées)..."
    TMP_VW="$BACKUP_CONFIGS/tmp_vaultwarden"
    mkdir -p "$TMP_VW"
    cp -r /srv/docker/vaultwarden/data/rsa_key* "$TMP_VW/" 2>/dev/null || true
    cp -r /srv/docker/vaultwarden/data/attachments "$TMP_VW/" 2>/dev/null || true
    if command -v sqlite3 >/dev/null 2>&1 && [ -f "/srv/docker/vaultwarden/data/db.sqlite3" ]; then
        sqlite3 "/srv/docker/vaultwarden/data/db.sqlite3" ".backup '$TMP_VW/db.sqlite3'"
    else
        cp /srv/docker/vaultwarden/data/db.sqlite3* "$TMP_VW/" 2>/dev/null || true
    fi
    tar -czf "$BACKUP_CONFIGS/vaultwarden_${DATE}.tar.gz" -C "$TMP_VW" .
    rm -rf "$TMP_VW"
fi

# B. Domotique (Home Assistant & Zigbee2MQTT - sans logs volumineux)
HA_PATH="/srv/docker/homeauto"
[ -d "/root/homeauto" ] && HA_PATH="/root/homeauto"
if [ -d "$HA_PATH" ]; then
    echo "    - Domotique Home Assistant & Zigbee ($HA_PATH)..."
    tar -czf "$BACKUP_CONFIGS/homeauto_${DATE}.tar.gz" \
        --exclude="*.db" \
        --exclude="*.db-wal" \
        --exclude="*.db-shm" \
        --exclude="*.log" \
        -C "$HA_PATH" . 2>/dev/null || true
fi

# C. Certificats SSL Nginx Proxy Manager
if [ -d "/srv/docker/nginx-proxy-manager" ]; then
    echo "    - Certificats SSL et proxys NPM..."
    tar -czf "$BACKUP_CONFIGS/npm_ssl_${DATE}.tar.gz" \
        -C /srv/docker/nginx-proxy-manager letsencrypt 2>/dev/null || true
fi

# D. Tableaux de bord Homepage
if [ -d "/srv/docker/homepage/config" ]; then
    echo "    - Dashboard Homepage..."
    tar -czf "$BACKUP_CONFIGS/homepage_${DATE}.tar.gz" \
        -C /srv/docker/homepage/config . 2>/dev/null || true
fi

# E. Volumes Docker internes Nextcloud & MariaDB (si présents)
if docker volume inspect nextcloud_config >/dev/null 2>&1; then
    docker run --rm -v nextcloud_config:/source:ro -v "$BACKUP_CONFIGS":/target \
        alpine tar -czf "/target/nextcloud_volume_config_${DATE}.tar.gz" -C /source . 2>/dev/null || true
fi
if docker volume inspect mariadb_config >/dev/null 2>&1; then
    docker run --rm -v mariadb_config:/source:ro -v "$BACKUP_CONFIGS":/target \
        alpine tar -czf "/target/mariadb_volume_config_${DATE}.tar.gz" -C /source . 2>/dev/null || true
fi

# ==============================================================================
# 6. SYNCHRONISATION INCRÉMENTALE RSYNC DES DONNÉES (Ultra rapide)
# ==============================================================================
echo "[+] [5/6] Synchronisation incrémentale des fichiers vers le disque 2 To..."

# Flags rsync :
# -a : Archive (préserve permissions, propriétaires, dates, liens symboliques)
# -H : Conserve les hardlinks
# -v : Affiche les modifications
# --delete : Supprime les fichiers supprimés de la source
# --backup + --backup-dir : Déplace les fichiers effacés vers une corbeille datée (sécurité anti-suppression)
RSYNC_OPTS="-aHv --delete --backup --backup-dir=$BACKUP_TRASH/$DATE"

# Synchronisation Nextcloud Data (exclusion des prévisualisations pour aller 10x plus vite)
if [ -d "$DATA_NEXTCLOUD" ]; then
    echo "    -> Synchronisation des données Nextcloud..."
    rsync $RSYNC_OPTS \
        --exclude="appdata_*/preview/*" \
        --exclude="*.log" \
        "$DATA_NEXTCLOUD/" "$BACKUP_NEXTCLOUD/data/"
fi

# Synchronisation PhotoPrism
if [ -d "$DATA_PP_STORAGE" ]; then
    echo "    -> Synchronisation de la photothèque PhotoPrism..."
    rsync $RSYNC_OPTS \
        --exclude="cache/*" \
        "$DATA_PP_STORAGE/" "$BACKUP_PHOTOPRISM/storage/"
fi

if [ -d "$DATA_PP_IMPORT" ]; then
    echo "    -> Synchronisation du dossier import photos..."
    rsync $RSYNC_OPTS \
        "$DATA_PP_IMPORT/" "$BACKUP_PHOTOPRISM/import/"
fi

# ==============================================================================
# 7. ROTATION ET NETTOYAGE
# ==============================================================================
echo "[+] [6/6] Rotation des sauvegardes..."
# Suppression des dumps et configs plus vieux que la période de rétention (~8 semaines)
find "$BACKUP_DB" -type f -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
find "$BACKUP_CONFIGS" -type f -name "*.tar.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true

# Suppression des dossiers de la corbeille anti-suppression plus vieux que 30 jours
find "$BACKUP_TRASH" -mindepth 1 -maxdepth 1 -type d -mtime +"$TRASH_RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true

# ==============================================================================
# 8. VIDAGE DU CACHE EN RAM VERS LE DISQUE PHYSIQUE (Indispensable USB)
# ==============================================================================
echo "[+] Vidage des tampons d'écriture en cours (sync)..."
sync

ELAPSED=$(( SECONDS - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo "========================================================================"
echo "✅ Sauvegarde terminée avec succès en ${MINUTES}m ${SECS}s !"
echo ""
echo "📊 Espace restant sur le disque externe 2 To :"
df -h "$MOUNT_POINT" | awk 'NR==1 || NR==2 {print "   " $0}'
echo ""
echo "💡 Vous pouvez maintenant débrancher votre disque en toute sécurité :"
echo "   sudo umount $MOUNT_POINT"
echo "========================================================================"
