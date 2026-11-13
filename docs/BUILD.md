# Construire LineageOS 16.0 pour l'UJC201, pas à pas

*English: [BUILD.en.md](BUILD.en.md)*

De zéro jusqu'aux **images `system`, `boot` et `vendor`** à flasher, sur un serveur **Proxmox VE 8 ou 9** avec un
conteneur LXC dédié (exemple : 2 × Xeon E5-2699 v3, 72 threads, 256 Go de RAM, NVMe 1 To). Sur un PC déjà sous
Ubuntu 20.04, sauter l'étape 1.

> **État** : l'arbre compile (premier build complet par la CI le 12/11/2026, section 0). Ce build n'a pas encore été
> démarré sur l'unité. Erreur de build sur votre machine : envoyer le log (étape 6), l'arbre sera corrigé.

| Étape | Où | Durée (estimation, pas une mesure) |
|---|---|---|
| 1. Conteneur LXC | hôte Proxmox | 10 min |
| 2. Système Ubuntu 20.04 | conteneur, root | 10 min |
| 3. Outils de build | conteneur, utilisateur `build` | 10 min |
| 4. Sources LineageOS + arbre | conteneur | environ 1 h (limité par les serveurs, pas par la fibre) |
| 5. Fichiers de l'unité | PC + unité sous TWRP, puis conteneur | 20 min |
| 6. Build : images | conteneur | 1 à 2 h la première fois, 15 à 30 min ensuite (ccache) |
| 7. Récupérer les fichiers | PC | 5 min |
| 8. Installer | PC + unité | 15 min |

**Pourquoi Ubuntu 20.04** : LineageOS 16.0 veut `python` = Python 2 et `libncurses5`, et son guide de build n'est
testé que sur Ubuntu 20.04 ([wiki LineageOS](https://wiki.lineageos.org/devices/f1f/build/)). Ubuntu 20.04 a les
deux (`python-is-python2`, `libncurses5`, toujours sur archive.ubuntu.com) ; Ubuntu 24.04 n'a plus Python 2. Pas de
Java à installer : l'OpenJDK 9 de LineageOS 16.0 vient avec les sources (même page du wiki).

**Ne jamais publier** les données propres à l'unité : adresses MAC Bluetooth et Wi-Fi, numéro de série, certificat
Apple MFi (CarPlay), donc ni `nvram`, `nvdata`, `proinfo` tels quels, ni `persist` / `metazone` sans vérification.
Les fichiers propriétaires Jancar / Autochips / MediaTek côté `/system` sont publiés dans le dépôt
[android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo) (cloné par le
manifest local, étape 4) ; `vendor.img` et `system-stock.img` restent chez vous (trop gros, propres à l'unité).

## 0. Sans PC de build : la CI de GitHub

Le dépôt compile lui-même LineageOS 16.0 sur GitHub Actions (`.github/workflows/lineage-build.yml`, runners gratuits
des dépôts publics : 4 CPU, 16 Go de RAM, 6 h par job) à chaque push de la branche `lineage-16.0` dont le message
contient `[build]`. Mêmes étapes que ce guide (sections 4 à 6), `systemimage` seulement : le vendor reste celui de
l'unité (jamais publié). Deux différences sans effet sur les images : `SKIP_ABI_CHECKS=true` (pas de vérification
d'ABI des bibliothèques VNDK, environ 1 h de moins sur le runner) et le build dans un cgroup mémoire de 13 Gio (s'il
manque de mémoire, c'est un processus du build qui est tué et le journal le dit, au lieu de perdre le runner et le
journal avec lui). Le disque du runner (146 Go) est juste : les objets Git des sources sont supprimés après la
synchronisation (le build ne lit pas Git) et le swap fait 8 Go. Dans l'onglet **Actions** du dépôt → le run → **Artifacts** (compte GitHub nécessaire) :
- `lineage-images` : **`LibreHU-LineageOS-16.0-ac8257_demo-<date>.zip`** (à flasher dans TWRP, section 8),
  `system.img.zst` (`zstd -d` puis `fastboot flash system`), `boot-librehu.img` et `boot-librehu-bootmenu.img`
  (noyau LibreHU avec `androidboot.selinux=permissive`), `SHA256SUMS` ;
- `lineage-build-log` : le journal complet du build.

## 1. Conteneur LXC (shell root de l'hôte Proxmox)

**Modèle Ubuntu 20.04.** Proxmox 8 le liste encore, Proxmox 9 ne liste plus que 24.04 et 26.04
([index PVE 8](http://download.proxmox.com/images/aplinfo-pve-8.dat), [index PVE 9](http://download.proxmox.com/images/aplinfo-pve-9.dat)),
mais le fichier est toujours en ligne et Proxmox 9 accepte 20.04
([`known_versions` de pve-container](https://git.proxmox.com/?p=pve-container.git;a=blob;f=src/PVE/LXC/Setup/Ubuntu.pm)).
Même commande pour les deux versions, empreinte SHA-512 de l'index Proxmox :
```bash
cd /var/lib/vz/template/cache
wget http://download.proxmox.com/images/system/ubuntu-20.04-standard_20.04-1_amd64.tar.gz
echo "9ebcf6cce7c3b760d27c2bfe03d00acf3d40a489cd98230b9ab8dd436f82f4ae8dc2de69b012dcd0affae62ffe4ab4863f624a665f3493983d330e6c015a26dd  ubuntu-20.04-standard_20.04-1_amd64.tar.gz" | sha512sum -c -
```

**Stockage du NVMe** : son nom dans Proxmox (ici `nvme`) :
```bash
pvesm status
```
Si le NVMe n'est pas encore un stockage : *nœud > Disks > LVM-Thin > Create: Thinpool* (**efface le disque**).

**Création** (ID 160, libre à vous) :
```bash
pct create 160 local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz \
  --hostname lineage-build --unprivileged 1 --features nesting=1 \
  --cores 72 --memory 131072 --swap 16384 \
  --rootfs nvme:600 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp
pct start 160
pct enter 160
```

| Option | Pourquoi |
|---|---|
| `--unprivileged 1` | le build n'a besoin d'aucun droit sur l'hôte ; l'unité n'est jamais branchée au serveur (étape 5 : depuis un PC) |
| `--features nesting=1` | demandé par systemd pour isoler ses services ([doc `pct`](https://pve.proxmox.com/pve-docs/pct.1.html)) |
| `--cores 72` | tous les threads ; en mettre moins si d'autres VM doivent tourner pendant le build |
| `--memory 131072 --swap 16384` | 128 Go + 16 Go de swap ; le wiki LineageOS demande 16 Go jusqu'à la 17.1 |
| `--rootfs nvme:600` | 600 Gio sur le NVMe : le wiki compte 200 Go (sources + sortie) jusqu'à la 17.1, plus ccache (50 Go) et de la marge ; agrandissable ensuite : `pct resize 160 rootfs +100G` |

## 2. Système (dans le conteneur, root)

```bash
apt update && apt full-upgrade -y
apt install -y sudo openssh-server locales
locale-gen en_US.UTF-8 fr_FR.UTF-8
adduser build
usermod -aG sudo build
ip -4 -br addr show eth0      # adresse IP du conteneur, pour ssh et scp
```
La suite se fait en `build` : `ssh build@<ip>` depuis le PC (ou `su - build`).

## 3. Outils de build (utilisateur `build`)

Paquets du [wiki LineageOS](https://wiki.lineageos.org/devices/f1f/build/), avec ceux qu'il ajoute pour une Ubuntu
antérieure à 23.10 (`lib32ncurses5-dev libncurses5 libncurses5-dev` ; sur 20.04, `lib32ncurses5-dev` s'appelle
`lib32ncurses-dev`) et Python 2 par défaut (`python-is-python2`, LineageOS 11.0 à 16.0). En plus : `python3`
(`repo`, scripts de l'arbre), `unzip` et `e2fsprogs` (`debugfs`), pour les scripts de l'arbre. Tous présents dans
l'index d'Ubuntu 20.04 (vérifié le 07/11/2026).
```bash
sudo apt install -y bc bison build-essential ccache curl erofs-utils flex g++-multilib gcc-multilib git git-lfs \
  gnupg gperf imagemagick kmod protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev \
  libelf-dev libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
  squashfs-tools xsltproc xxd zip zlib1g-dev \
  lib32ncurses-dev libncurses5 libncurses5-dev python-is-python2 python3 unzip e2fsprogs
python --version              # doit afficher Python 2.7.x
mkdir -p ~/bin ~/android/lineage
curl -o ~/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
chmod a+x ~/bin/repo
cat >> ~/.bashrc <<'EOF'

# LineageOS (docs/BUILD.md)
export PATH="$HOME/bin:$PATH"
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache
EOF
source ~/.bashrc
ccache -M 50G
git config --global user.name "Votre nom"
git config --global user.email "vous@exemple.com"
```

## 4. Sources LineageOS 16.0 et arbre de l'UJC201

```bash
cd ~/android/lineage
repo init -u https://github.com/LineageOS/android.git -b lineage-16.0 --depth=1
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/ujc201.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="LibreHU/android_device_alps_ac8257_demo" path="device/alps/ac8257_demo"
           remote="github" revision="lineage-16.0" />
  <project name="LibreHU/android_vendor_jancar_ac8257_demo" path="vendor/jancar/ac8257_demo"
           remote="github" revision="lineage-16.0" />
</manifest>
EOF
repo sync -c -j16 --no-tags --no-clone-bundle
(cd external/chromium-webview/prebuilt/arm64 && git lfs install --local && git lfs pull)
device/alps/ac8257_demo/tools/patch_lineage_sources.sh
```
- `tools/patch_lineage_sources.sh` (**après chaque `repo sync`**, qui remet les fichiers d'origine) corrige deux
  fichiers de LineageOS. Sans lui, l'init s'arrête et l'unité redémarre en fastboot juste après le menu de démarrage
  (essais du 12/11/2026) :
  - `system/core/fs_mgr/fs_mgr.cpp` : `fs_mgr_is_device_unlocked()` voit l'unité déverrouillée, sauf
    `androidboot.vbmeta.device_state=locked` explicite. Le LK de Jancar annonce `verifiedbootstate=green` même
    déverrouillé (et aucun `androidboot.vbmeta.*` avec `--disable-verification`) ; fs_mgr croyait l'unité verrouillée
    et refusait le vbmeta modifié par fastboot : `/vendor` ne se montait pas.
  - `device/lineage/sepolicy/common/private/genfs_contexts` : retire `genfscon fuseblk / u:object_r:vfat:s0`. La
    politique SELinux du vendor Jancar étiquette déjà `fuseblk` en `sdcardfs` ; au démarrage, l'init compile la
    politique system + vendor avec `secilc`, qui refuse deux `genfscon` différents pour le même chemin.

  - `frameworks/native` (`tools/lineage-patches`) : la dalle est en portrait (720 × 1280) montée en paysage ; le stock
    la tourne avec `persist.sf.hwrotation=90` (SurfaceFlinger de MediaTek), que LineageOS ignore. SurfaceFlinger et
    l'InputReader lisent `persist.librehu.display_rotation`, sinon `ro.librehu.display_rotation` (90, `device.mk`) :
    image et tactile tournent ensemble.
  - `frameworks/base` (`tools/lineage-patches`) : rétroéclairage Jancar inversé (`lcd-backlight` 0 = maximum, 179 =
    minimum) ; `LightsService` convertit la luminosité d'Android (`ro.librehu.backlight_inverted`).

  Sans ce script, le build s'arrête dès `lunch` (messages dans le [dépannage](#dépannage)).
- WebView : son APK précompilé (`external/chromium-webview/prebuilt/arm64/webview.apk`, 243 Mo) est un fichier
  Git LFS ; `repo sync` n'en pose que le pointeur, d'où la commande `git lfs pull` (paquet `git-lfs`).
- `--depth=1` : sans l'historique, beaucoup moins à télécharger.
- `-j16` : 16 dépôts à la fois (LineageOS met 4 par défaut). Les serveurs AOSP de Google limitent chaque adresse IP
  ([source.android.com](https://source.android.com/docs/setup/download/troubleshoot-sync), qui conseille aussi de
  simplement relancer) : en cas d'erreurs, relancer la même commande, avec `-j4` si elles reviennent ; les dépôts
  déjà téléchargés ne sont pas refaits.

## 5. Fichiers de l'unité (une seule fois)

Le build reprend la **partition vendor** de votre unité. Les fichiers propriétaires de son **/system stock**
(`proprietary-files.txt` : interfaces HIDL Autochips, `autochips.jar` et ses JNI) viennent du dépôt vendor, cloné à
l'étape 4 (ROM stock V1.151R6) ; l'image `system` ne sert que de sauvegarde, ou pour un autre firmware. On les lit
depuis un **PC** (Windows, macOS ou Linux, avec les
[platform-tools](https://developer.android.com/tools/releases/platform-tools)), l'unité démarrée sous **TWRP**
(adb root) et branchée en USB :
```bash
adb devices
adb pull /dev/block/platform/bootdevice/by-name/vendor vendor.img
adb pull /dev/block/platform/bootdevice/by-name/system system-stock.img
```
Tailles attendues : `vendor.img` = **2 147 483 648** octets, `system-stock.img` = **3 221 225 472** octets
(table des partitions, `BoardConfig.mk`). Lecture seule : rien n'est écrit sur l'unité. Garder ces deux fichiers :
ils servent aussi de sauvegarde.

Les copier dans le conteneur :
```bash
scp vendor.img system-stock.img build@<ip>:
```

Dans le conteneur :
```bash
cd ~/android/lineage
mkdir -p vendor/jancar/ac8257_demo
mv ~/vendor.img vendor/jancar/ac8257_demo/vendor.img
stat -c %s vendor/jancar/ac8257_demo/vendor.img        # 2147483648
debugfs -R "cat /build.prop" vendor/jancar/ac8257_demo/vendor.img 2>/dev/null | grep ro.vndk.version   # 28

# Fichiers propriétaires côté /system (interfaces HIDL Autochips, autochips.jar et ses JNI) : déjà dans le dépôt
# vendor (manifest local, étape 4), repris de la ROM stock V1.151R6. Autre firmware : les reprendre du vôtre
# (autochips.jar, épinglé, reste celui du dépôt) :
#   mkdir -p ~/stock && debugfs -R "rdump /system $HOME/stock" ~/system-stock.img
#   (cd device/alps/ac8257_demo && ./extract-files.sh ~/stock)

cd device/alps/ac8257_demo
tools/vendor_add_viper.sh             # pilote ViPERFX_RE dans vendor.img (copie vendor.img.orig gardée)
tools/fetch_kernel.sh                 # noyau LibreHU stable-4.9.337 : images de boot + modules Wi-Fi / BT / GPS / FM
                                      # (+ androidboot.selinux=permissive dans l'en-tête des images de boot)
tools/vendor_add_conn_modules.sh      # ces modules dans vendor.img (le noyau LibreHU refuse ceux du stock)
librehu/fetch_apks.sh                 # derniers APK LibreHU (toutes en priv-app ; vérifie leur liste blanche)
                                      # + gestionnaire KernelSU Next v3.4.2 (empreinte vérifiée)
cd ~/android/lineage
rm -rf ~/stock                        # si vous l'avez fait : plus utile
```
`debugfs rdump` affiche des erreurs « while changing ownership » : il ne peut pas donner les fichiers à root sans
être root. Sans importance, le contenu est bien copié.

## 6. Build : les images

```bash
cd ~/android/lineage
export LC_ALL=C
source build/envsetup.sh
lunch lineage_ac8257_demo-userdebug
mka systemimage bootimage vendorimage 2>&1 | tee ~/build-$(date +%Y%m%d-%H%M).log
```
`mka` répartit le build sur tous les cœurs.

**Premier essai** : prendre l'image de boot sans menu, une inconnue de moins si Android ne démarre pas (le menu de
démarrage n'a été essayé que sous la ROM stock) : `export LIBREHU_BOOT_IMAGE=plain` avant `lunch`. TWRP reste
accessible par `adb reboot recovery` (adb répond dès le démarrage).

**En cas d'erreur** : envoyer le log (`~/build-*.log`), ou au moins ses 200 dernières lignes :
`tail -n 200 ~/build-*.log`.

**Résultat**, dans `out/target/product/ac8257_demo/` :

| Fichier | Contenu |
|---|---|
| `system.img` | image system (sparse) |
| `boot.img` | copie de `prebuilt/boot-librehu-bootmenu.img` (ou `boot-librehu.img` avec `LIBREHU_BOOT_IMAGE=plain`) : image de boot de la CI du noyau LibreHU, avec le **pied AVB du boot stock** sans lequel le LK la refuse, et `androidboot.selinux=permissive` ajouté à la ligne de commande de son en-tête par `tools/fetch_kernel.sh` |
| `vendor.img` | votre vendor avec ViPERFX_RE et les modules du noyau LibreHU (copie de `vendor/jancar/ac8257_demo/vendor.img`) ; **jamais publié** |

Les trois vont ensemble : `vendor.img` contient les modules de **ce** noyau (le noyau stock les refuse), et seul ce
`boot.img` met SELinux en permissif (sans lui, `mcu_ready` ne peut pas envoyer PC_READY et le MCU coupe le SoC).

**Pas de zip flashable**, vérifié dans les sources de LineageOS 16.0 : son générateur de zip refuse un appareil non
A/B sans recovery (« target build has specified no recovery »,
[`ota_from_target_files.py`](https://github.com/LineageOS/android_build/blob/lineage-16.0/tools/releasetools/ota_from_target_files.py#L1984-L1986)),
et `mka bacon` n'a rien à empaqueter quand l'image de boot n'est pas construite par LineageOS
(`TARGET_NO_KERNEL` : `build_ota_package := false`,
[`core/Makefile`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/Makefile#L2579-L2581)). Or l'arbre ne
construit volontairement ni recovery (TWRP reste en place) ni `boot.img` (un `boot.img` de LineageOS n'aurait pas le
pied AVB du boot stock : le LK le refuse et l'unité redémarre au logo).

## 7. Récupérer les fichiers (sur le PC)

```bash
for f in system boot vendor; do scp build@<ip>:android/lineage/out/target/product/ac8257_demo/$f.img .; done
```
Depuis l'hôte Proxmox, `pct pull 160 <fichier> <destination>` fait la même chose.

## 8. Installer

> Builds publies (releases GitHub) et guide d'installation pour l'utilisateur, avec vbmeta, flash, mises a jour et
> depannage : [INSTALL.md](INSTALL.md). Cette section reste celle des images construites soi-meme.

**Avant la première installation** :
1. **Sauvegarde TWRP complète** sur une clé USB ou une microSD : System Image, Vendor, Boot, Data et les partitions
   propres à l'unité. Garder aussi `vendor.img` et `system-stock.img` de l'étape 5.
2. **vbmeta**, une seule fois, **à la main** (jamais fait par ces outils), **avec les deux options**, même si
   `--disable-verity` seul a déjà été passé pour le noyau LibreHU sous stock :
   ```bash
   fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
   ```
   `vbmeta.img` = celui du stock (sauvegarde, ou `images/vbmeta.img` d'un rapport LibreHU Helper). Pourquoi les deux :
   le vbmeta stock **chaîne la partition `system`** (descripteurs `chain recovery`, `chain system`, `hashtree vendor`,
   `hash dtbo`, `hash boot`, lus le 09/11/2026 dans un rapport Helper). Le LK, puis l'init au montage de `vendor`
   (drapeau `avb` du fstab du DT), lisent alors le vbmeta du pied AVB de `system`. Le `system.img` de LineageOS n'en a
   pas (`BOARD_AVB_ENABLE := false`, la clé Jancar n'est pas disponible) : libavb rend `ERROR_INVALID_METADATA`, fatal
   même déverrouillé (`external/avb/libavb/avb_slot_verify.c` d'Android 9 ; `system/core/fs_mgr/fs_mgr_avb.cpp`), et
   l'unité redémarre au logo sans journal. Avec `--disable-verification`, le drapeau `VERIFICATION_DISABLED` fait
   ignorer la chaîne. Retour au stock : possible avec ce vbmeta tel quel.

**Installation avec le zip de la CI (TWRP)** : après la sauvegarde et le vbmeta ci-dessus :
1. **Première installation** : *Wipe > Format Data*, taper `yes` (LineageOS ne démarre pas sur les données de la ROM
   stock). **Avant** le zip : il sauvegarde `boot` et les modules dans la mémoire interne, que *Format Data* efface.
2. Copier le zip sur une clé USB ou la microSD (pas dans la mémoire interne : *Format Data* l'efface aussi), TWRP :
   *Install* → le zip. Il écrit `system` (vérifié en relisant toute la partition), `boot` (noyau LibreHU, SELinux
   permissif ; mettre `bootmenu` dans le nom du zip pour l'image avec le menu de démarrage) et les modules Wi-Fi / BT /
   GPS / FM de ce noyau dans `/vendor/lib/modules` (originaux sauvegardés dans
   `/sdcard/LibreHU/backup/conn-modules-orig`). Il s'arrête **sans rien écrire** si la vérification de vbmeta n'est
   pas désactivée, et ne touche jamais vbmeta ni `/data` (il rappelle *Format Data* si `/data` vient d'une autre ROM).
3. *Reboot > System*. Au premier démarrage, Android demande l'écran d'accueil : **LibreHU Launcher**, *Toujours*
   (Trebuchet reste en secours si LibreHU Launcher ne démarrait pas).

**Installation** :
1. TWRP : *Wipe > Format Data*, taper `yes` (**première installation seulement** : LineageOS ne démarre pas sur les
   données de la ROM stock).
2. `adb reboot bootloader` (ou TWRP : *Reboot > Bootloader*), puis sur le PC :
   ```bash
   fastboot flash system system.img
   fastboot flash boot boot.img
   fastboot flash vendor vendor.img
   fastboot reboot
   ```
   Sans PC pour `system` et `boot` : TWRP, *Install > Install Image* (`system.img` > *System Image*, `boot.img` >
   *Boot*) ; `vendor.img` demande fastboot (le fstab de TWRP n'a pas d'entrée image pour vendor).

**Après le premier démarrage**, depuis le PC :
```bash
adb shell getenforce                                               # Permissive
adb shell getprop persist.sys.usb.config                           # contient adb
adb shell getprop ro.control_privapp_permissions                   # log
adb shell 'echo $BOOTCLASSPATH' | tr ':' '\n' | grep autochips      # /system/framework/autochips.jar
adb shell ls /system/priv-app/LibreHUAndroidAuto/lib/arm64         # bibliothèques d'Android Auto
adb shell dmesg | grep mcu_ready                                   # le MCU a reçu PC_READY
adb logcat -d | grep 'not in privapp-permissions whitelist'        # rien attendu (sinon : à ajouter à la liste)
```
Le téléphone doit voir l'autoradio comme une **voiture** (icône voiture dans sa liste Bluetooth) et lui envoyer la
musique (A2DP) et les appels (HFP). Ensuite : adb actif sans autorisation, `adb root` autorisé, journaux dans
`/data/misc/logd/`, gestionnaire KernelSU Next installé tout seul (y autoriser LibreHU-service) ; détails, root, MTP :
[README](../README.md#5-installer). **Retour arrière** : restaurer la sauvegarde TWRP.

## 9. Builds suivants

```bash
cd ~/android/lineage
repo sync -c -j16 --no-tags --no-clone-bundle
device/alps/ac8257_demo/tools/patch_lineage_sources.sh
device/alps/ac8257_demo/librehu/fetch_apks.sh
device/alps/ac8257_demo/tools/fetch_kernel.sh
device/alps/ac8257_demo/tools/vendor_add_conn_modules.sh
export LC_ALL=C
source build/envsetup.sh
lunch lineage_ac8257_demo-userdebug
mka systemimage bootimage vendorimage 2>&1 | tee ~/build-$(date +%Y%m%d-%H%M).log
```
**Builds faits avant le 09/11/2026** : `vendor/jancar/ac8257_demo/` existait déjà (votre `vendor.img`, et
`proprietary/` d'`extract-files.sh`) et n'est pas un dépôt git, `repo sync` refuse donc d'y cloner le dépôt vendor.
Une seule fois, à la place du `repo sync` ci-dessus (garde `vendor.img` et sa copie `vendor.img.orig`) :
```bash
cd ~/android/lineage
mv vendor/jancar/ac8257_demo/vendor.img* ~/
rm -rf vendor/jancar/ac8257_demo
repo sync -c -j16 --no-tags --no-clone-bundle
device/alps/ac8257_demo/tools/patch_lineage_sources.sh
mv ~/vendor.img* vendor/jancar/ac8257_demo/
```

Installation : `fastboot flash system system.img` et `fastboot flash boot boot.img` (ou TWRP, *Install Image*),
**sans** *Format Data*. Si `tools/fetch_kernel.sh` a pris un nouveau noyau, reflasher aussi `vendor.img` : ses
modules doivent venir du même build que le noyau de `boot`. L'étape 5 n'est pas à refaire
(`vendor/jancar/ac8257_demo/` reste).

## Dépannage

| Symptôme | Solution |
|---|---|
| `repo sync` : erreurs de téléchargement, 429, `RESOURCE_EXHAUSTED` | relancer la même commande, avec `-j4` si ça revient |
| Dès `lunch` : `genfscon fuseblk de LineageOS en conflit avec le vendor Jancar` ou `fs_mgr de LineageOS non corrige (LK Jancar : verifiedbootstate=green)` | `device/alps/ac8257_demo/tools/patch_lineage_sources.sh` depuis la racine des sources (à refaire après chaque `repo sync`) |
| Menu de démarrage, puis l'unité **redémarre en fastboot** | l'init d'Android a rencontré une erreur fatale (son `LOG(FATAL)` redémarre en bootloader), avant le logo LineageOS : `/vendor` refusé par fs_mgr (LK Jancar en `green`) puis politique SELinux qui ne compile pas (essais du 12/11/2026, corrigés par `tools/patch_lineage_sources.sh`), ou autre montage de la première étape. Pour revenir : `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img`, puis TWRP par le menu |
| Image et tactile **à l'envers** (tournés de 180°) | `adb root`, puis `adb shell setprop persist.librehu.display_rotation 270` et `adb reboot` (90 par défaut, 0 pour revenir au portrait) |
| Tactile hors de l'écran | calibration de la dalle absente : `adb logcat -s LibreHU-Touch` (service `librehu_touchcal` au démarrage), identifiant de la dalle `adb shell head -c 19 /proc/gt9xx_config` à chercher dans `/jancar/config/pointercal*.xml` |
| Plus de menu de démarrage, l'unité **reste sur le logo** du constructeur | vbmeta du stock **avec** vérification et `system` de LineageOS (sans pied AVB) : le LK refuse de démarrer (section 8). Si `fastboot devices` répond : `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img`. Sinon : SP Flash Tool, onglet *Download*, **Download Only**, uniquement `vbmeta`, avec une copie de `vbmeta.img` dont l'octet 123 vaut 3 (jamais *Format All + Download*) |
| `python` introuvable, ou `SyntaxError` dans un script du build | `python --version` doit donner 2.7 : `sudo apt install python-is-python2` |
| `flex` ou `bison` : `Assertion ... loadlocale.c` | `export LC_ALL=C` avant `source build/envsetup.sh` |
| `libncurses.so.5: cannot open shared object file` | `sudo apt install libncurses5` |
| `debugfs manquant` | `sudo apt install e2fsprogs` |
| `extract-files.sh` : `!! file not found in source` | (autre firmware seulement) `~/stock/system/lib64/...` absent : refaire le `rdump` de l'étape 5 |
| `repo sync` : `vendor/jancar/ac8257_demo` existe déjà / n'est pas un dépôt git | dossier d'un build d'avant le 09/11/2026 : voir *Builds suivants* (garder `vendor.img`, supprimer le dossier, `repo sync`) |
| `No rule to make target 'vendor/jancar/ac8257_demo/proprietary/...'` | dépôt vendor absent ou pas à jour : manifest local de l'étape 4, puis `repo sync` |
| Au démarrage, `ClassNotFoundException` (`com.autochips.*`) ou `UnsatisfiedLinkError` (`lib*_jni.so`) dans logcat | `echo $BOOTCLASSPATH` (adb shell) doit contenir `/system/framework/autochips.jar` ; sinon dépôt vendor pas à jour au build : `repo sync` et rebuild ; envoyer le logcat |
| Android Auto absent, ou s'arrête dès son ouverture | `adb shell ls /system/priv-app/LibreHUAndroidAuto/lib/arm64` doit lister ses bibliothèques : relancer `librehu/fetch_apks.sh` (il lance `native_libs.py`) puis rebuild. Builds d'avant le 09/11/2026 au soir : le build recompressait son APK et retirait sa signature v2 (PackageManager le refusait) |
| Pas de son | `adb logcat -d \| grep APM::Serializer` doit montrer la lecture de `/vendor/etc/audio_policy_configuration.xml` ; builds d'avant le 09/11/2026 au soir : `USE_XML_AUDIO_POLICY_CONF` absent, l'audio lisait la configuration de l'émulateur |
| Le téléphone ne voit pas l'autoradio comme une voiture, ou pas de musique Bluetooth | builds d'avant le 09/11/2026 au soir (classe d'appareil smartphone, A2DP sink non compilé) ; sinon `adb shell settings get global bluetooth_class_of_device` doit répondre `null` (une valeur posée passe avant la classe « Car audio ») ; oublier l'appareil côté téléphone puis l'associer à nouveau |
| `fetch_kernel.sh` : `'str' object has no attribute 'removeprefix'` | corrigé le 07/11/2026 (Python 3.8 d'Ubuntu 20.04) : `repo sync` |
| `prebuilt/boot-librehu-bootmenu.img absent` (avertissement au `lunch`), puis `No rule to make target ... boot-librehu` | lancer `tools/fetch_kernel.sh` (depuis le 09/11/2026 il prend aussi les images de boot) |
| `fetch_apks.sh` : `privapp-permissions-librehu.xml is short` | une appli demande une nouvelle permission privilégiée : ajouter les lignes affichées à `librehu/privapp-permissions-librehu.xml` (depuis le 09/11/2026 la ROM est en `log` comme le stock : la permission est accordée et l'oubli journalisé ; les builds d'avant, en `enforce`, arrêtaient `system_server` : `Signature|privileged permissions not in privapp-permissions whitelist`) |
| L'unité redémarre au logo, sans journal du noyau | d'abord **vbmeta** : passé avec `--disable-verity` seul, le LK suit la chaîne `system` du vbmeta stock et refuse le `system.img` de LineageOS (étape 8) : `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img`. Sinon `boot.img` sans pied AVB (builds d'avant le 09/11/2026) : flasher `prebuilt/boot-librehu-bootmenu.img` (ou le zip `kernel-stable` de LibreHU Apps) dans `boot` |
| L'unité repart en mode fastboot (ou TWRP) juste après le logo ; `last_kmsg` : `avb_slot_verify failed` ou `Failed to mount required partitions early` | même cause, vue par l'init au montage de `vendor` : vbmeta à repasser avec les deux options (étape 8) |
| Animation de démarrage sans fin, rien ne se lance ; `logcat` : `Failed to mount an un-encryptable or wiped partition on ... at /jancar` | builds d'avant le 09/11/2026 : `/jancar` absent de la racine de `system`, `mount_all` échoue et init ne lance pas zygote ; `repo sync` et rebuild |
| Android démarre puis l'unité redémarre au bout d'une dizaine de secondes ; ou `adb shell getenforce` répond `Enforcing` | d'abord `persist.vendor.connsys.chipid` (ligne suivante), cause la plus probable sur un `/data` vide. Images de boot prises avant le correctif SELinux du 09/11/2026 au soir (en-tête sans `androidboot.selinux=permissive`) : `repo sync`, relancer `tools/fetch_kernel.sh` (il l'ajoute), rebuild, reflasher `boot`. Builds d'avant le 09/11/2026 : `mcu_ready` sans domaine SELinux, jamais lancé par init (PC_READY absent : le MCU coupe le SoC 10 s après une sortie de veille, 15 min à froid) ; `repo sync` et rebuild. `adb shell dmesg \| grep mcu_ready` (ou `last_kmsg`) dit si le MCU a répondu. Sinon, envoyer le journal du noyau du démarrage raté (ci-dessous) |
| Boucle de redémarrages dès que le Wi-Fi s'allume (Android Auto l'allume tout seul) | `persist.vendor.connsys.chipid` vaut `0x0000` : `su -c 'getprop persist.vendor.connsys.chipid'` ; builds d'avant le 09/11/2026 (sans `rootdir/etc/init/librehu.rc`) : Wi-Fi coupé, `su -c 'setprop persist.vendor.connsys.chipid 0x8257'` puis redémarrer ; corrigé aussi dans le noyau `stable-4.9.337` depuis le 13/11/2026 (`tools/fetch_kernel.sh`) |
| `fetch_apks.sh` : `sha256sum: WARNING: 1 computed checksum did NOT match` sur `KernelSUNext.apk` | téléchargement abîmé : relancer ; si ça revient, la release v3.4.2 de KernelSU Next a changé, ne pas contourner |
| Gestionnaire KernelSU Next absent après le premier démarrage | `adb logcat -d -s LibreHU-KSU` (raison du refus de `pm install`) ; `ksunext/KernelSUNext.apk` absent au build : relancer `fetch_apks.sh` |
| `FAILED: bacon` | normal avec cet arbre : `TARGET_NO_KERNEL := true` (image de boot du noyau LibreHU) met `build_ota_package := false` (`core/Makefile` de LineageOS 16.0), la règle `bacon` n'a donc aucun zip à copier (`ln -f` sans source). Construire les images (`mka systemimage bootimage vendorimage`, section 6) ou prendre le zip TWRP de la CI (section 0) ; tout ce qui précède `bacon` dans le journal est bon |
| `FAILED: .../webview_intermediates/package.apk`, `java.util.zip.ZipException: zip END header not found` | le WebView précompilé est resté un pointeur Git LFS : `cd external/chromium-webview/prebuilt/arm64 && git lfs install --local && git lfs pull` (paquet `git-lfs`), puis relancer le build |
| `Killed` ou manque de mémoire | plus de RAM au conteneur (`pct set 160 --memory 196608` sur l'hôte) ou moins de tâches : `m -j36 systemimage bootimage vendorimage` |
| `No space left on device` | `df -h ~`, puis sur l'hôte `pct resize 160 rootfs +100G` |

**Journal d'un démarrage raté** : le noyau LibreHU garde la fin (256 Kio) du journal du démarrage précédent dans
pstore (ramoops, zone réservée `0x47c90000`, `CONFIG_PSTORE_RAM`) : `/sys/fs/pstore/console-ramoops`, repris dans
`/proc/last_kmsg` derrière l'en-tête de la console RAM MediaTek. Ce journal ne survit qu'à un redémarrage à chaud
(panique, chien de garde, `reboot`) : une coupure d'alimentation du SoC (le MCU qui le coupe, contact coupé) efface la
RAM, et on n'y trouve alors que le début du démarrage en cours (console pstore précoce du noyau). Juste après le
redémarrage raté, dès que `adb` répond (Android stock ou LineageOS ; TWRP si son noyau l'expose aussi) :
`adb shell cat /sys/fs/pstore/console-ramoops > last_kmsg.txt` (ou `/proc/last_kmsg`).
Android le range aussi dans le dropbox (`SYSTEM_LAST_KMSG`), que LibreHU-service lit à son démarrage. Avec le menu de
démarrage, choisir **TWRP** évite de relancer Android (et d'écraser ce journal) avant de l'avoir lu.

**Journaux d'Android** (builds depuis le 09/11/2026) : logcat est enregistré en continu dans `/data/misc/logd/`
(`persist.logd.logpersistd=logcatd`), donc gardé après un redémarrage. adb répond sans autorisation dès le démarrage et
`adb root` est autorisé par défaut : `adb root` puis `adb pull /data/misc/logd`.

## Sources

- Wiki LineageOS, guide de build d'un appareil en 16.0 (Ubuntu 20.04, paquets, Python 2, OpenJDK 9, ccache, `repo`) :
  https://wiki.lineageos.org/devices/f1f/build/
- Proxmox VE : [`pct`](https://pve.proxmox.com/pve-docs/pct.1.html) (création, `nesting`, `rootfs`, `pct enter`,
  `pct resize`, `pveam`), [index des modèles PVE 8](http://download.proxmox.com/images/aplinfo-pve-8.dat) et
  [PVE 9](http://download.proxmox.com/images/aplinfo-pve-9.dat),
  [versions Ubuntu acceptées](https://git.proxmox.com/?p=pve-container.git;a=blob;f=src/PVE/LXC/Setup/Ubuntu.pm)
- AOSP, quotas par adresse IP : https://source.android.com/docs/setup/download/troubleshoot-sync
- LineageOS 16.0, adb et journaux : [`WITH_ADB_INSECURE`](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-16.0/config/common.mk#L19-L30),
  [`post_process_props.py`](https://github.com/LineageOS/android_build/blob/lineage-16.0/tools/post_process_props.py#L40-L54),
  [`ALLOW_ADBD_NO_AUTH`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/adb/Android.mk#L346),
  [`adb root`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/adb/services.cpp#L86-L93),
  [Débogage root](https://github.com/LineageOS/android_packages_apps_Settings/blob/lineage-16.0/src/com/android/settings/development/RootAccessPreferenceController.java#L69-L76),
  [`logcatd.rc`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/logcat/logcatd.rc),
  [`PRODUCT_PACKAGES_DEBUG`](https://github.com/LineageOS/android_build/blob/lineage-16.0/target/product/base.mk#L168-L173),
  ordre de l'init ([`init.rc`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/rootdir/init.rc#L279-L318),
  [`queue_property_triggers`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/init/init.cpp#L432-L436),
  [`Action::CheckEvent`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/init/action.cpp#L179-L181))
- KernelSU Next : [release v3.4.2](https://github.com/KernelSU-Next/KernelSU-Next/releases/tag/v3.4.2) (empreinte de
  l'APK) ; le noyau ne cherche le gestionnaire que dans `/data/app` (`drivers/kernelsu/manager/throne_tracker.c` du
  noyau LibreHU)
- LineageOS 16.0 : [`ota_from_target_files.py`](https://github.com/LineageOS/android_build/blob/lineage-16.0/tools/releasetools/ota_from_target_files.py),
  [`core/Makefile`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/Makefile),
  [`init.rc`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/rootdir/init.rc),
  [`bacon.mk`](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-16.0/build/tasks/bacon.mk)
- Applis prébuilts : [`prebuilt_internal.mk`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/prebuilt_internal.mk)
  et `uncompress-shared-libs` ([`definitions.mk`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/definitions.mk)) ;
  Android 9 n'extrait pas les bibliothèques d'une appli système (`PackageManagerService.derivePackageAbi`)
- Audio : [`frameworks/av/services/audiopolicy/Android.mk`](https://github.com/LineageOS/android_frameworks_av/blob/lineage-16.0/services/audiopolicy/Android.mk)
  (`USE_XML_AUDIO_POLICY_CONF`) ; Bluetooth : [`bt_target.h`](https://github.com/LineageOS/android_system_bt/blob/lineage-16.0/internal_include/bt_target.h)
  (`BTA_DM_COD`, `BTA_AV_SINK_INCLUDED`), [`fluoride.go`](https://github.com/LineageOS/android_system_bt/blob/lineage-16.0/build/fluoride.go),
  profils voiture d'Android 9 : `packages/services/Car` (`car_product/overlay/packages/apps/Bluetooth`, pie-release)
- Verified Boot : [`avb_slot_verify.c`](https://android.googlesource.com/platform/external/avb/+/refs/heads/pie-release/libavb/avb_slot_verify.c)
  d'Android 9 (pied AVB absent d'une partition chaînée : `ERROR_INVALID_METADATA`, `result_should_continue` faux ;
  `VERIFICATION_DISABLED` : descripteurs non lus), [`fs_mgr_avb.cpp`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/fs_mgr/fs_mgr_avb.cpp)
  (seuls `OK` et `ERROR_VERIFICATION` acceptés, le second seulement si l'unité est vue déverrouillée),
  [`fs_mgr_is_device_unlocked`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/fs_mgr/fs_mgr.cpp#L503-L509)
  (déverrouillée seulement en `orange`), [`avb_vbmeta_image.c`](https://android.googlesource.com/platform/external/avb/+/refs/heads/pie-release/libavb/avb_vbmeta_image.c)
  (l'empreinte couvre l'en-tête, donc ses drapeaux), [`init.cpp`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/init/init.cpp#L616-L617)
  (`Failed to mount required partitions early`, fatal)
- Permissions privilégiées : [`common.mk`](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-16.0/config/common.mk)
  (`enforce`), [`PermissionManagerService`](https://github.com/LineageOS/android_frameworks_base/blob/lineage-16.0/services/core/java/com/android/server/pm/permission/PermissionManagerService.java)
  (`systemReady` lève `IllegalStateException` en `enforce`), [`RoSystemProperties`](https://github.com/LineageOS/android_frameworks_base/blob/lineage-16.0/core/java/com/android/internal/os/RoSystemProperties.java) ;
  ordre des propriétés : [`property_service.cpp`](https://github.com/LineageOS/android_system_core/blob/lineage-16.0/init/property_service.cpp),
  [`node_fns.mk`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/node_fns.mk),
  `uniq-pairs-by-first-component` ([`definitions.mk`](https://github.com/LineageOS/android_build/blob/lineage-16.0/core/definitions.mk))
- MCU : [`docs/mcu_firmware.md`](https://github.com/LibreHU/MCU-tools-app/blob/main/docs/mcu_firmware.md) de
  MCU-tools-app (PC_READY, acquittement `C0`, attente de 15 min à froid et 10 s après une veille)

## TL;DR

1. Hôte Proxmox : modèle Ubuntu 20.04, `pct create 160 ... --cores 72 --memory 131072 --rootfs nvme:600`.
2. Conteneur : paquets de l'étape 3, `repo init` + manifest local (arbre + dépôt vendor) + `repo sync`.
3. PC + TWRP : `adb pull` de `vendor` et `system`, `scp` dans le conteneur, puis les scripts `tools/` et
   `librehu/fetch_apks.sh`.
4. `lunch lineage_ac8257_demo-userdebug && mka systemimage bootimage vendorimage` (pas de zip possible).
5. Installer : vbmeta stock une fois avec `fastboot --disable-verity --disable-verification` (le vbmeta stock chaîne
   `system`), Format Data (première fois), `fastboot flash` de `system`, `boot` et `vendor` ; vérifier
   `adb shell getenforce` = `Permissive`.
