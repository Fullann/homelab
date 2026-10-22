#!/bin/bash
# ==============================================================================
# 💾 Script de Sauvegarde Automatisée - Homelab OpenMediaVault
# Sauvegarde des bases de données SQL, coffres Vaultwarden et configurations clés.
# ==============================================================================

set -euo pipefail

# Répertoire de destination par défaut (sur le RAID ou sur un disque externe USB)
BACKUP_ROOT="${1:-/srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45/backups}"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
TMP_DIR="$BACKUP_ROOT/tmp_$TIMESTAMP"
RETENTION_DAYS=7

mkdir -p "$TMP_DIR"
echo "[$(date +'%T')] 🚀 Démarrage de la sauvegarde du Homelab..."

# 1. Sauvegarde de la base de données Nextcloud (MariaDB)
if docker ps --format '{{.Names}}' | grep -q "^mariadb$"; then
    echo "[$(date +'%T')] 📦 Export SQL de la base Nextcloud..."
    docker exec mariadb mariadb-dump -u root --all-databases > "$TMP_DIR/nextcloud_all_databases.sql" 2>/dev/null || echo "⚠️ Avertissement : échec du dump mariadb"
fi

# 2. Sauvegarde de la base PhotoPrism (MariaDB)
if docker ps --format '{{.Names}}' | grep -q "^photoprism-db$"; then
    echo "[$(date +'%T')] 📦 Export SQL de la base PhotoPrism..."
    docker exec photoprism-db mariadb-dump -u root --all-databases > "$TMP_DIR/photoprism_all_databases.sql" 2>/dev/null || echo "⚠️ Avertissement : échec du dump photoprism-db"
fi

# 3. Sauvegarde à chaud de Vaultwarden (SQLite)
if [ -d "/srv/docker/vaultwarden/data" ]; then
    echo "[$(date +'%T')] 🔒 Sauvegarde du coffre Vaultwarden..."
    mkdir -p "$TMP_DIR/vaultwarden"
    # Copie sécurisée de la base SQLite et des clés de chiffrement RSA
    cp -r /srv/docker/vaultwarden/data/rsa_key* "$TMP_DIR/vaultwarden/" 2>/dev/null || true
    cp -r /srv/docker/vaultwarden/data/attachments "$TMP_DIR/vaultwarden/" 2>/dev/null || true
    # Snapshot propre de SQLite si sqlite3 est disponible, sinon copie standard
    if command -v sqlite3 >/dev/null 2>&1 && [ -f "/srv/docker/vaultwarden/data/db.sqlite3" ]; then
        sqlite3 "/srv/docker/vaultwarden/data/db.sqlite3" ".backup '$TMP_DIR/vaultwarden/db.sqlite3'"
    else
        cp /srv/docker/vaultwarden/data/db.sqlite3* "$TMP_DIR/vaultwarden/" 2>/dev/null || true
    fi
fi

# 4. Sauvegarde des configurations Homepage & Home Assistant
if [ -d "/srv/docker/homepage/config" ]; then
    echo "[$(date +'%T')] 📑 Sauvegarde des fichiers YAML Homepage..."
    cp -r /srv/docker/homepage/config "$TMP_DIR/homepage_config"
fi

if [ -d "/root/homeauto" ]; then
    echo "[$(date +'%T')] 🏠 Sauvegarde des configurations Home Assistant & Zigbee (sans les logs/db)..."
    tar -czf "$TMP_DIR/homeauto_configs.tar.gz" \
        --exclude="*.db" \
        --exclude="*.db-wal" \
        --exclude="*.db-shm" \
        --exclude="*.log" \
        -C /root homeauto
fi

# 5. Compression finale de l'archive
ARCHIVE_NAME="homelab_backup_$TIMESTAMP.tar.gz"
echo "[$(date +'%T')] 🗜️ Création de l'archive finale : $ARCHIVE_NAME..."
tar -czf "$BACKUP_ROOT/$ARCHIVE_NAME" -C "$BACKUP_ROOT" "tmp_$TIMESTAMP"
rm -rf "$TMP_DIR"

# 6. Rotation des sauvegardes (conserve les 7 derniers jours)
echo "[$(date +'%T')] 🧹 Nettoyage des anciennes sauvegardes (> $RETENTION_DAYS jours)..."
find "$BACKUP_ROOT" -name "homelab_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete

echo "[$(date +'%T')] ✅ Sauvegarde terminée avec succès dans : $BACKUP_ROOT/$ARCHIVE_NAME"
