# 🎮 Guide : Serveur Minecraft avec PufferPanel & Domaine `mc.domaine.com`

Ce tutoriel explique comment déployer un serveur Minecraft (Java ou Bedrock) via **PufferPanel** sur votre Homelab et configurer votre zone DNS pour que vos amis puissent se connecter avec l'adresse **`mc.mondomaine.com`** sans avoir à taper de numéro de port.

---

## 1. Pourquoi Minecraft ne passe PAS par Nginx Proxy Manager ?

Nginx Proxy Manager est un **Reverse Proxy HTTP/HTTPS** (ports 80 et 443) pour les sites web. 

Le jeu Minecraft utilise son propre protocole réseau direct en **TCP** sur le port **`25565`**. Le trafic des joueurs doit donc aller directement de votre box Internet vers le port 25565 de votre serveur OpenMediaVault, sans passer par NPM.

---

## 2. Configuration du Serveur dans PufferPanel

### A. Comment PufferPanel gère Docker (Zéro modification de compose)
PufferPanel est connecté au socket Docker du serveur via `/var/run/docker.sock`. 

Quand vous créez un serveur Minecraft dans PufferPanel :
* PufferPanel ne fait pas tourner le jeu à l'intérieur de son propre conteneur.
* Il demande directement au moteur Docker de votre NAS de **créer un nouveau conteneur dédié à côté** (un conteneur frère).
* Ce conteneur Minecraft dédié possède **déjà automatiquement son port `25565:25565` ouvert et mappé sur l'hôte**.
* Vous n'avez donc **absolument rien à modifier dans le `docker-compose.yml` de PufferPanel** !

### B. Création du serveur via l'interface PufferPanel
1. Connectez-vous sur votre panneau PufferPanel.
2. Allez dans **Templates** :
   * Vérifiez que le template **Minecraft (Paper)** ou **Purpur** est présent (recommandés car 5 à 10 fois plus optimisés et stables que le serveur *Vanilla* officiel de Mojang).
3. Allez dans **Servers** > Cliquez sur **+** (Add Server) :
   * **Name** : `MonServeurMinecraft`
   * **Template** : Choisissez `Minecraft - Paper`
   * **Port** : `25565`
   * **Memory (RAM)** : Allouez entre 4 Go (`4096M`) et 8 Go (`8192M`) selon les ressources de votre NAS.
4. Cliquez sur **Create Server** et laissez PufferPanel télécharger automatiquement les fichiers.

### C. Accepter l'accord de licence (EULA)
1. Lancez le serveur une première fois : il va s'arrêter au bout de quelques secondes en affichant *"You need to agree to the EULA"*.
2. Allez dans l'onglet **Files** de votre serveur dans PufferPanel.
3. Ouvrez le fichier **`eula.txt`**.
4. Remplacez `eula=false` par **`eula=true`** et sauvegardez.
5. Relancez le serveur : il est désormais prêt et écoute sur le port 25565 !

---

## 3. Redirection du port sur votre Box Internet (Routeur)

Pour que vos amis puissent vous rejoindre depuis l'extérieur, votre box doit faire suivre le trafic du port 25565 vers votre NAS :

1. Connectez-vous à l'interface de votre box Internet (192.168.1.1).
2. Allez dans **Réseau** > **Redirection de ports (NAT / PAT)**.
3. Ajoutez une règle :
   * **Nom** : `Minecraft`
   * **Protocole** : `TCP`
   * **Port externe** : `25565`
   * **Port interne** : `25565`
   * **Équipement / IP cible** : L'adresse IP locale de votre NAS (ex: `192.168.1.3`).

---

## 4. Configuration de la Zone DNS (`mc.mondomaine.com`)

Chez votre registrar de nom de domaine (OVH, Cloudflare, Infomaniak, etc.) :

### Méthode 1 : Simple & Directe (Enregistrement A ou CNAME)

Comme le jeu Minecraft interroge par défaut le port `25565` lorsqu'aucun port n'est spécifié, il suffit de faire pointer `mc.mondomaine.com` vers votre IP publique :

* **Si vous avez déjà un sous-domaine `home.mondomaine.com`** (ou DDNS) :
  Créez un enregistrement **CNAME** :
  ```text
  mc.mondomaine.com.   IN CNAME   home.mondomaine.com.
  ```
* **Si vous préférez pointer directement vers votre IP publique fixe** :
  Créez un enregistrement **A** :
  ```text
  mc.mondomaine.com.   IN A       <VOTRE_IP_PUBLIQUE>
  ```

Dans Minecraft, vos joueurs tapent simplement dans l'adresse du serveur :
👉 **`mc.mondomaine.com`**

---

### Méthode 2 : L'enregistrement SRV (Recommandé par les pros)

L'enregistrement **SRV** est un type de DNS spécifique qui indique explicitement au jeu Minecraft quel est le protocole et le numéro de port, même si vous décidez un jour de changer de port (ex: `25570`) :

Dans la zone DNS de votre registrar, ajoutez une entrée **SRV** avec ces paramètres :

| Champ | Valeur à renseigner |
| :--- | :--- |
| **Type** | `SRV` |
| **Service** | `_minecraft` |
| **Protocole** | `_tcp` |
| **Nom / Hôte** | `mc` (ce qui donne `_minecraft._tcp.mc.mondomaine.com`) |
| **Priorité** | `0` |
| **Poids** | `5` |
| **Port** | `25565` (ou votre port personnalisé) |
| **Cible / Host** | `home.mondomaine.com` (ou `mc.mondomaine.com`) |
| **TTL** | `3600` (ou Auto) |

---

## 5. Test et Connexion depuis le jeu

1. Ouvrez votre jeu Minecraft (Java Edition).
2. Allez dans **Multijoueur** > **Nouveau serveur**.
3. **Nom du serveur** : `Mon Homelab`
4. **Adresse du serveur** : `mc.mondomaine.com`
5. Cliquez sur **Valider** : le voyant passe au vert avec le ping et vous pouvez vous connecter !

---

[← Retour au README principal](../README.md)
