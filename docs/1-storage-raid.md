# 💾 Stockage & Matériel : OpenMediaVault & Grappe RAID 5

Ce document détaille l'architecture matérielle et la configuration du stockage de notre serveur personnel sous **OpenMediaVault (Debian)**.

---

## 1. Configuration physique & Architecture des disques

Le serveur dispose d'une séparation claire entre le système d'exploitation et le volume de données :

| Disque | Capacité | Rôle & Type | Système de fichiers | Point de montage |
| :--- | :---: | :--- | :---: | :--- |
| **`/dev/sde`** | **480 Go** | **SSD Système (OS)** : Héberge Debian, OpenMediaVault et les moteurs Docker. | `ext4` + `vfat` (EFI) | `/` (438 Go) et `/boot/efi` |
| **`/dev/sda`** | **4 To** (3.6 TiB) | Membre 1 de la grappe RAID 5 (`linux_raid_member`) | mdadm RAID | Agrégé dans `/dev/md0` |
| **`/dev/sdb`** | **4 To** (3.6 TiB) | Membre 2 de la grappe RAID 5 (`linux_raid_member`) | mdadm RAID | Agrégé dans `/dev/md0` |
| **`/dev/sdc`** | **4 To** (3.6 TiB) | Membre 3 de la grappe RAID 5 (`linux_raid_member`) | mdadm RAID | Agrégé dans `/dev/md0` |
| **`/dev/sdd`** | **4 To** (3.6 TiB) | Membre 4 de la grappe RAID 5 (`linux_raid_member`) | mdadm RAID | Agrégé dans `/dev/md0` |
| **`/dev/md0`** | **12 To** (10.9 TiB) | **Volume RAID 5 fusionné** : Espace de stockage sécurisé. | `ext4` | `/srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45` |

---

## 2. Fonctionnement et avantages du RAID 5

La grappe `/dev/md0` regroupe les 4 disques durs de 4 To grâce au sous-système noyau Linux **mdadm** :

* **Capacité brute totale** : $4 \times 4\text{ To} = 16\text{ To}$
* **Capacité utile réelle** : $(N - 1) \times 4\text{ To} = 12\text{ To}$ (soit **10.92 TiB** utile formaté en `ext4`).
* **Tolérance aux pannes (Redondance)** : Le système calcule et distribue des blocs de parité sur l'ensemble des 4 disques. **Si un disque dur tombe en panne physique complète, aucune donnée n'est perdue.** Le serveur continue de fonctionner normalement en mode dégradé, et il suffit de remplacer le disque défectueux pour que la grappe se reconstruise automatiquement.
* **État de santé de la grappe** : `[4/4] [UUUU]` (Les 4 disques sont synchronisés, 0 disque en échec).
* **Consommation d'espace actuelle** : 5.0 To occupés sur 11 To (environ 46% d'utilisation).

---

## 3. Arborescence et exploitation par Docker

OpenMediaVault monte automatiquement le volume RAID 5 sous son identifiant UUID unique :
`/srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45/`

Ce volume est ensuite segmenté en dossiers partagés dédiés que les conteneurs Docker consomment via des points de montage :

```text
/srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45/
├── media/                     <-- Données partagées Jellyfin / Arr / Transmission
│   ├── FILM/                  <-- Films gérés par Radarr
│   ├── SERIE/                 <-- Séries TV gérées par Sonarr
│   ├── MUSIC/                 <-- Albums gérés par Lidarr
│   ├── BOOK/                  <-- Ebooks & Audiobooks gérés par Readarr
│   ├── PHOTO_IMPORT/          <-- Dossier tampon d'ingestion PhotoPrism
│   └── transcode/             <-- Cache temporaire pour le transcodage Jellyfin
├── nextcloud/                 <-- Données personnelles des utilisateurs Nextcloud
├── photoprism/                <-- Stockage des miniatures, index et originaux
└── photoprism-database/       <-- Base de données relationnelle MariaDB (fichiers tables)
```

---

## 4. Gestion des permissions Linux (PUID, PGID et Umask)

Dans un environnement où plusieurs conteneurs (Transmission, Radarr, Sonarr, Jellyfin) et services (partages SMB) manipulent la même arborescence `/media`, les conflits de permissions sont la cause n°1 d'erreurs (fichiers non déplaçables, accès refusé, suppression impossible).

### Le standard OpenMediaVault (Debian)
* **UID 1000** : L'identifiant du premier utilisateur administrateur créé dans OMV.
* **GID 100** : Le groupe système `users` sous Debian, auquel appartiennent tous les utilisateurs de partages créés via l'interface OMV.

### Application dans les conteneurs Docker
Chaque conteneur manipulant les médias est configuré avec ces variables d'environnement :
```yaml
environment:
  - PUID=1000
  - PGID=100
```

### Le rôle de l'Umask (Transmission)
Par défaut, de nombreux clients torrent écrivent les fichiers avec un umask `022` (`rw-r--r--`), interdisant l'écriture aux autres membres du groupe.
Dans [`stacks/transmission/docker-compose.yml`](../stacks/transmission/docker-compose.yml), la variable suivante est définie :
```yaml
environment:
  - TRANSMISSION_UMASK=2
```
Avec `TRANSMISSION_UMASK=2` (umask `002`), les fichiers téléchargés reçoivent les droits `rw-rw-r--` et les dossiers `rwxrwxr-x`. Radarr, Sonarr et vos partages réseau peuvent immédiatement modifier, renommer ou déplacer les fichiers sans blocage.

### Commande de maintenance des droits
Pour réinitialiser les droits sur l'arborescence en cas d'anomalie :
```bash
sudo chown -R 1000:100 /srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45/media
sudo chmod -R 775 /srv/dev-disk-by-uuid-eaad3822-db12-4b70-9e31-59bc10826a45/media
```

---

[← Retour au README principal](../README.md)
