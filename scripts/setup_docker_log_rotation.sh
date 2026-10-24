#!/bin/bash
# ==============================================================================
# 🧹 Script d'Hygiène Système : Limitation & Rotation des Logs Docker
# Prévient la saturation de la partition racine (/) du SSD système 480 Go.
# Conserve au maximum 3 fichiers de 50 Mo par conteneur (150 Mo max par service).
# ==============================================================================

set -euo pipefail

DAEMON_JSON="/etc/docker/daemon.json"

echo "========================================================================"
echo "🚀 Configuration de la politique de rotation des logs Docker..."
echo "========================================================================"

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] ERREUR : Ce script doit être exécuté avec les privilèges root (sudo)."
    exit 1
fi

mkdir -p /etc/docker

if [ -f "$DAEMON_JSON" ]; then
    BACKUP_FILE="${DAEMON_JSON}.bak_$(date +%Y%m%d_%H%M%S)"
    echo "[+] Sauvegarde de la configuration existante vers $BACKUP_FILE..."
    cp "$DAEMON_JSON" "$BACKUP_FILE"
fi

# Application de la configuration de rotation des logs
echo "[+] Écriture de la configuration dans $DAEMON_JSON..."
cat << 'EOF' > "$DAEMON_JSON"
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF

echo "[+] Redémarrage du démon Docker pour appliquer les réglages..."
systemctl restart docker

echo "========================================================================"
echo "✅ Politique de rotation des logs appliquée avec succès !"
echo "   - Taille max par fichier de log : 50 Mo"
echo "   - Nombre max de fichiers archivés : 3"
echo "   - Plafond par conteneur : ~150 Mo"
echo "========================================================================"
