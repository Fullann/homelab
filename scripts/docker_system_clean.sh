#!/usr/bin/env bash
# ==============================================================================
# Script de maintenance préventive du SSD hôte (Docker Garbage Collection)
# 
# Objectif :
#   Purger les couches d'images orphelines, anciennes versions de conteneurs
#   et caches de build qui consomment inutilement l'espace du SSD de 480 Go,
#   SANS JAMAIS TOUCHER AUX DONNÉES PERSISTANTES DU RAID (volumes préservés).
#
# Fréquence recommandée : Hebdomadaire (via cron ou exécution manuelle)
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo "🧹 MAINTENANCE DOCKER - GARBAGE COLLECTION DU SSD SYSTÈME"
echo "=========================================================="
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Démarrage du diagnostic..."

# 1. État avant nettoyage
echo ""
echo "📊 Utilisation du disque système (/):"
df -h / | awk 'NR==1 || NR==2'

echo ""
echo "📦 Utilisation de l'espace par Docker avant purge :"
docker system df

# 2. Purge sécurisée
echo ""
echo "🚀 Exécution du nettoyage des couches obsolètes..."

# Supprime les images non associées à un conteneur actif et créées il y a plus de 7 jours (168h)
echo "  -> Purge des images orphelines (> 7 jours)..."
docker image prune -af --filter "until=168h"

# Supprime le cache de construction Docker BuildKit périmé (> 7 jours)
echo "  -> Purge des caches de build orphelins (> 7 jours)..."
docker builder prune -af --filter "until=168h"

# Supprime les réseaux Docker personnalisés orphelins (qui ne sont plus utilisés)
echo "  -> Purge des réseaux Docker résiduels non utilisés..."
docker network prune -f

# 3. État après nettoyage
echo ""
echo "=========================================================="
echo "✅ Nettoyage terminé avec succès !"
echo "=========================================================="
echo "📊 Utilisation finale de l'espace par Docker :"
docker system df

echo ""
echo "💾 Espace restant sur le SSD système (/):"
df -h / | awk 'NR==1 || NR==2'
echo "=========================================================="
