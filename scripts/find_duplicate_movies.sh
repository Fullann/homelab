#!/usr/bin/env bash
# ==============================================================================
# Script de détection des doublons de films par identifiant TMDB
# 
# Contexte :
#   Lorsqu'un film change de titre sur TheMovieDB (ex: "F1" devient "F1 The Movie"),
#   Radarr peut créer un second dossier avec le même identifiant TMDB (ex: 911430)
#   au lieu de remplacer l'ancien dossier. Cela gaspille des dizaines de gigaoctets.
#
# Ce script :
#   - Scanne le répertoire des films sans JAMAIS modifier ni supprimer de fichier (100% sécurisé)
#   - Extrait l'identifiant TMDB à la fin des noms de dossiers (ex: -911430)
#   - Identifie les dossiers en doublon partageant le même ID
#   - Affiche les tailles (du -sh) et dates pour identifier la release la plus récente/optimale
# ==============================================================================

set -euo pipefail

# Définition du chemin cible
DEFAULT_PATH="/srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45/media/movies"

# Si le dossier par défaut n'existe pas, tenter /data/movies ou accepter un argument
TARGET_DIR="${1:-$DEFAULT_PATH}"

if [ ! -d "$TARGET_DIR" ]; then
    # Tentative avec /data/movies (si exécuté dans un conteneur)
    if [ -d "/data/movies" ]; then
        TARGET_DIR="/data/movies"
    elif [ -d "/data/FILM" ]; then
        TARGET_DIR="/data/FILM"
    else
        echo "❌ Le dossier spécifié n'existe pas : $TARGET_DIR"
        echo "Usage : $0 [/chemin/vers/dossier/films]"
        exit 1
    fi
fi

echo "=========================================================="
echo "🔍 ANALYSE DES DOUBLONS TMDB DANS : $TARGET_DIR"
echo "=========================================================="

TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

# Parcourt tous les dossiers de niveau 1
find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
    dirname=$(basename "$dir")
    # Extraction de l'ID TMDB (cherche les chiffres après un tiret en fin de chaîne ou tmdbid-XXX)
    if [[ "$dirname" =~ -([0-9]{4,8})$ ]]; then
        tmdb_id="${BASH_REMATCH[1]}"
        echo "$tmdb_id|$dir" >> "$TMP_FILE"
    elif [[ "$dirname" =~ tmdbid-([0-9]{4,8}) ]]; then
        tmdb_id="${BASH_REMATCH[1]}"
        echo "$tmdb_id|$dir" >> "$TMP_FILE"
    fi
done

# Recherche des identifiants apparaissant plus d'une fois
duplicate_ids=$(cut -d'|' -f1 "$TMP_FILE" | sort | uniq -d)

if [ -z "$duplicate_ids" ]; then
    echo "✅ Aucun doublon TMDB détecté dans la bibliothèque !"
    echo "=========================================================="
    exit 0
fi

count_groups=$(echo "$duplicate_ids" | wc -l | tr -d ' ')
echo "⚠️  $count_groups groupe(s) de films en doublon détecté(s) :"
echo ""

echo "$duplicate_ids" | while read -r id; do
    echo "----------------------------------------------------------"
    echo "🎬 ID TMDB : $id"
    grep "^$id|" "$TMP_FILE" | cut -d'|' -f2- | while read -r folder; do
        folder_size=$(du -sh "$folder" 2>/dev/null | cut -f1)
        echo "  📁 Dossier : $folder (Taille totale: $folder_size)"
        
        # Liste les fichiers vidéo principaux à l'intérieur
        find "$folder" -maxdepth 2 -type f \( -name "*.mkv" -o -name "*.mp4" \) -printf "     ↳ Fichier : %f | Taille: %s octets | Modifié le: %TY-%Tm-%Td %TH:%TM\n" 2>/dev/null || true
    done
done

echo ""
echo "=========================================================="
echo "💡 CONSEILS POUR RÉSOUDRE LES DOUBLONS DANS RADARR :"
echo "1. Comparez la taille et la qualité des fichiers ci-dessus."
echo "2. Conservez le dossier contenant la meilleure version (ex: 4K Remux / TrueHD Atmos)."
echo "3. Supprimez manuellement le dossier obsolète avec : rm -rf \"/chemin/vers/dossier_a_supprimer\""
echo "4. Dans Radarr :"
echo "   - Allez dans Paramètres > Gestion des médias > activez 'Supprimer les dossiers vides'."
echo "   - Lancez un 'Rafraîchir et analyser' (Refresh & Scan) de la bibliothèque."
echo "=========================================================="
