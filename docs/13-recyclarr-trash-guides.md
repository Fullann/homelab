# 📦 Guide d'Optimisation Radarr & Sonarr : Recyclarr & TRaSH Guides

La configuration par défaut de Radarr et Sonarr se contente souvent de filtrer par résolution (ex: 1080p ou 2160p). Sans critères précis, ils risquent de télécharger des versions de mauvaise qualité (son mono, encodages approximatifs, CAM/Telesync, fausses releases ou profils Dolby Vision sans couche de compatibilité SDR/HDR10 provoquant des écrans violets ou verts).

**Recyclarr** automatise l'injection des règles de référence mondiales issues des **TRaSH Guides** directement dans les bases de données de Radarr et Sonarr via leurs APIs.

---

## 1. Bénéfices apportés par les TRaSH Guides

Grâce aux profils synchronisés par Recyclarr :
* **Priorité aux pistes audio haut de gamme** : Dolby Atmos, Dolby TrueHD, DTS-HD MA, DTS:X, DD+ Atmos.
* **Sélection vidéo optimale** : Prise en charge intelligente du Dolby Vision (avec profil 7 / 8 rétrocompatible HDR10) et HDR10+.
* **Élimination automatique des rejets indésirables** : Bannissement systématique des CAM, TS (Telesync), versions sur-échantillonnées artificiellement (*Upscaled*), releases corrompues ou tags trompeurs.
* **Maîtrise des tailles de fichiers** : Ajustement automatique des débits minimum/maximum par minute de vidéo pour éviter à la fois les fichiers sous-compressés immenses (> 80 Go) et la bouillie de pixels ultra-compressée (< 1 Go).

---

## 2. Déploiement de la Stack Recyclarr

La stack est déclarée dans [`stacks/recyclarr/docker-compose.yml`](../stacks/recyclarr/docker-compose.yml) :
* Elle s'exécute sur le réseau Docker privé `proxy` pour communiquer directement avec les conteneurs `http://radarr:7878` et `http://sonarr:8989`.
* Elle intègre une planification cron native (`CRON_SCHEDULE=0 3 * * *`) pour maintenir les profils à jour chaque nuit à 03h00 sans redémarrage.

### A. Renseigner les clés API Radarr et Sonarr
1. Dans votre navigateur, ouvrez **Radarr** :
   * Rendez-vous dans *Paramètres* > *Général* > section *Sécurité*.
   * Copiez la **Clé API**.
2. Ouvrez **Sonarr** :
   * Rendez-vous dans *Paramètres* > *Général* > section *Sécurité*.
   * Copiez la **Clé API**.
3. Éditez le fichier de configuration [`stacks/recyclarr/config/recyclarr.yml`](../stacks/recyclarr/config/recyclarr.yml) :
   * Remplacez `VOTRE_CLE_API_RADARR` par votre clé Radarr.
   * Remplacez `VOTRE_CLE_API_SONARR` par votre clé Sonarr.

### B. Déployer et exécuter la première synchronisation
Dans le terminal de votre serveur hôte :
```bash
# Démarrer le conteneur en arrière-plan
docker compose -f stacks/recyclarr/docker-compose.yml up -d

# Lancer immédiatement une première synchronisation manuelle
docker compose -f stacks/recyclarr/docker-compose.yml run --rm recyclarr sync
```

Dès la fin de la commande, rendez-vous dans Radarr et Sonarr sous *Paramètres* > *Profils* : vous verrez apparaître les nouveaux profils clés en main :
* **Radarr** : `HD Bluray + WEB`, `UHD Bluray + WEB` (4K Atmos / DV), `Remux-1080p`.
* **Sonarr** : `WEB-1080p`, `WEB-2160p`.

---

## 3. Gestion des Doublons de Dossiers Films (Identifiant TMDB identique)

### A. Origine du problème
Vous pouvez observer dans votre stockage `/data/movies` deux dossiers pour un même film, par exemple :
* `/data/movies/F1-(2025)-911430/F1-(2025)-911430.mkv`
* `/data/movies/F1 The Movie-(2025)-911430/F1-(2025)-911430.mkv`

**Pourquoi cela arrive-t-il ?**
1. **Évolution des métadonnées TMDB** : Lors de l'annonce d'un film, son titre provisoire sur TheMovieDB était par exemple "F1". Radarr a créé le premier dossier. Par la suite, la fiche officielle TMDB a été renommée "F1 The Movie".
2. **Mise à niveau (*Upgrade*) sans suppression de l'ancien dossier** : Lorsque Radarr télécharge une version de meilleure qualité ou effectue un rafraîchissement avec renommage, il crée le dossier cible selon le nouveau titre officiel. Si l'ancien fichier ou l'ancien dossier n'a pas été purgé (dossier non vide ou option désactivée), les deux dossiers persistent côte-à-côte avec le même ID TMDB (`911430`).

### B. Diagnostic automatique avec le script dédié
Un script non destructif est disponible dans [`scripts/find_duplicate_movies.sh`](../scripts/find_duplicate_movies.sh) :
```bash
./scripts/find_duplicate_movies.sh
```
Ce script :
1. Scanne l'ensemble de vos dossiers films.
2. Détecte les identifiants TMDB dupliqués.
3. Affiche pour chaque occurrence la taille du dossier (`du -sh`), le nom exact du fichier `.mkv`, son poids et sa date de modification.

### C. Résolution propre et sécurisée
1. Exécutez le script ci-dessus pour inspecter les deux versions.
2. Identifiez la meilleure version (généralement la plus récente ou la plus volumineuse correspondant à votre profil de qualité).
3. Supprimez l'ancien dossier obsolète :
   ```bash
   rm -rf "/srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45/media/movies/F1-(2025)-911430"
   ```
4. Dans **Radarr** :
   * Rendez-vous dans *Paramètres* > *Gestion des médias* (*Media Management*).
   * Cochez l'option **Supprimer les dossiers vides** (*Delete Empty Folders*).
   * Cliquez sur **Médiathèque** > bouton **Rafraîchir et analyser** (*Refresh & Scan*). Radarr reliera immédiatement le film à son unique dossier propre.

---

## 4. Maintenance Automatique du SSD Système (Docker Garbage Collection)

Sur un serveur homelab fonctionnant en continu avec Watchtower, chaque mise à jour de conteneur télécharge de nouvelles images Docker. Sans maintenance, les anciennes couches d'images non étiquetées (*dangling*) et les caches de construction peuvent occuper 30 à 60 Go sur le SSD système de 480 Go.

### La solution mise en œuvre (Zéro perte de données)

1. **Watchtower avec purge immédiate** ([`stacks/watchtower/docker-compose.yml`](../stacks/watchtower/docker-compose.yml)) :
   * `WATCHTOWER_CLEANUP=true` : Supprime l'ancienne image Docker dès que le conteneur est redémarré avec succès sous sa nouvelle version.
   * `WATCHTOWER_SCHEDULE=0 0 4 * * *` : Planifie les vérifications à 04h00 chaque nuit pour éviter les redémarrages imprévus en journée.
2. **Conteneur `docker-gc` (Docker Garbage Collection)** :
   * Conteneur ultra-léger basé sur `docker:cli` qui tourne en tâche de fond.
   * Exécute toutes les 24 heures la purge des images orphelines et caches de construction âgés de plus de 7 jours (`docker image prune -af --filter "until=168h"`).
   * **Sécurité garantie** : Les volumes de données (`--volumes=false`) ne sont **JAMAIS** touchés. Seules les images non utilisées sont nettoyées.
3. **Script manuel hôte** ([`scripts/docker_system_clean.sh`](../scripts/docker_system_clean.sh)) :
   * Permet d'exécuter à la demande un diagnostic complet avec affichage de l'espace disque libéré avant/après.

---

[← Retour au README principal](../README.md)
