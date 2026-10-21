# LineageOS 16.0 pour l'UJC201 (Jancar, Autochips AC8257)

Arbre de device **LineageOS 16.0 (Android 9)** de l'autoradio Jancar UJC201 (`ac8257_demo`, SoC Autochips AC8257,
famille MediaTek MT6761). Une vraie ROM construite depuis les sources LineageOS, pas une GSI.

**Etat : arbre de depart, pas encore compile ni teste sur l'unite.**

## Branches du depot

| Branche | Contenu |
|---|---|
| `twrp` (par defaut) | recovery TWRP de l'UJC201, avec sa CI et ses releases |
| **`lineage-16.0`** | cette branche : ROM LineageOS 16.0 |

Noyau : [android_kernel_autochips_ac8257_4.9](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9)
(`LibreHU-main` : sources GPL Autochips + modifications LibreHU). Applis : depots `LibreHU-*` de
[LibreHU](https://github.com/LibreHU).

## Approche

L'unite est **Treble** : partition vendor Android 9 separee (`ro.treble.enabled=true`, `ro.vndk.version=28`,
`ro.product.first_api_level=28`), system-as-root. Le manifest framework du `/system` stock est celui d'AOSP : aucun
HAL cote system propre a Jancar ou MediaTek. D'ou, pour la phase 1 :

| Partition | Contenu |
|---|---|
| `system` | **LineageOS 16.0 construit ici** + applis LibreHU (service, launcher, OTA, ViPER4Android, telephone, FM, widgets, BtnRemap, EasySource, Disc, MCU Toolkit, Android Auto, CarPlay) + `mcu_ready` |
| `vendor` | **vendor stock**, lu sur l'unite (`tools/get_vendor_img.sh`) et repris (`BOARD_PREBUILT_VENDORIMAGE`), avec le pilote ViPERFX_RE ajoute (`tools/vendor_add_viper.sh`) ; jamais publie |
| `boot` | noyau stock #72 (`prebuilt/kernel`, voir [prebuilt/README.md](prebuilt/README.md)) ; plus tard le noyau LibreHU |
| `dtbo`, `vbmeta`, `lk`, `tee`... | stock, non modifies |
| `recovery` | TWRP (branche `twrp`) ; le recovery LineageOS n'est pas a flasher |

LineageOS 16.0 est la seule version de LineageOS de meme niveau qu'Android 9 : VNDK 28 et politique SELinux 28.0
correspondent au vendor stock, sans couche de compatibilite.

### Ce que l'arbre contient

| Fichier | Role |
|---|---|
| `BoardConfig.mk` | architecture (Cortex-A53, arm64 + arm), boot (en-tete v1, adresses du stock), partitions (table eMMC du noyau #72), vendor prebuilt, VNDK |
| `lineage_ac8257_demo.mk`, `AndroidProducts.mk`, `vendorsetup.sh` | produit `lineage_ac8257_demo` (profil telephone : modem 4G), empreinte du vendor stock |
| `device.mk` | 1280 x 720 a 160 dpi (`wm size` du stock), proprietes du stock, overlays, paquets |
| `overlay/` | barre de navigation a l'ecran, pas de luminosite auto, paysage fixe, ecran toujours allume |
| `mcu_ready/` | service natif : envoie `PC_READY` au MCU Jancar (`/dev/ttyS1`) des le demarrage, jusqu'a sa reponse. **Indispensable** : sans lui le MCU coupe le SoC une dizaine de secondes apres le demarrage (sur le stock c'est `com.jancar.services` qui l'envoie) |
| `librehu/` | applis LibreHU dans `/system/app` : **LibreHU-service** (`latest-main`), **LibreHU Launcher** edition `librehu-service` (seul ecran d'accueil, remplace Trebuchet), **LibreHU Apps / OTA** (`latest-main`) ; APK telecharges par `fetch_apks.sh`, signature d'origine gardee : l'appli OTA les met ensuite a jour comme sur la ROM stock. **ViPER4Android LibreHU** 2.1.1 (`latest-librehu-service`) dans `/system/priv-app` avec sa liste blanche (`MODIFY_AUDIO_ROUTING`, `DUMP` ; LineageOS impose `ro.control_privapp_permissions=enforce`). Aussi dans `/system/app` : **telephone**, **radio FM**, **widgets** et **BtnRemap** (edition `librehu-service`), **EasySource**, **Disc**, **MCU Toolkit** (`latest-main`), **Android Auto** (Open Headunit LibreHU, `latest-main`) et **CarPlay** (xcertplay LibreHU, `latest-master`) ; un APK absent est ignore. Toutes signees avec la cle LibreHU : l'appli OTA les met a jour |
| `proprietary-files.txt`, `extract-files.sh`, `setup-makefiles.sh` | interfaces HIDL Autochips cote system (camera de recul, AVM, affichage rapide, iAP2, audio ATC...) reprises du stock |
| `tools/get_vendor_img.sh` | lit la partition vendor de l'unite (lecture seule) |
| `tools/vendor_add_viper.sh` | ajoute a l'image vendor locale (debugfs, copie `vendor.img.orig` gardee) le pilote [ViPERFX_RE](https://github.com/likelikeslike/ViPERFX_RE) v2.1.1 (module officiel, SHA-256 verifie) : `libv4a_re.so` dans `/lib[64]/soundfx` et l'effet `v4a_standard_re` dans `/etc/audio_effects.xml`, comme le zip `viper4android-re` de LibreHU-flashablesZips. Dans vendor car sous Android 9 Treble les effets sont charges par le HAL audio du vendor, qui ne peut pas charger de bibliotheque de `/system` |
| `rootdir/etc/fstab.ac8257` | fstab du vendor stock (pour le build du recovery) |

## Compiler from scratch

### 1. Machine
- Linux x86-64 ; **Ubuntu 18.04 ou 20.04** conseille (LineageOS 16.0 date de ces versions ; sur plus recent, Python 2
  et quelques reglages sont necessaires).
- **Environ 200 Go libres** (sources + sortie), **16 Go de RAM** conseilles (moins = plus lent ; activer zram), SSD.
  Le wiki LineageOS donne 200 Go des la 17.1 ([guide de build](https://wiki.lineageos.org/devices/s2/build/)).
- La CI GitHub gratuite ne suffit pas (14 Go de disque, 6 h par job) : build sur un PC ou un runner auto-heberge.

```bash
sudo apt install bc bison build-essential ccache curl flex g++-multilib gcc-multilib git gnupg gperf \
  imagemagick lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool libncurses5 libncurses5-dev \
  libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip \
  zlib1g-dev python2 unzip adb
# Le build d'Android 9 appelle "python" = Python 2
sudo ln -sf /usr/bin/python2 /usr/local/bin/python
mkdir -p ~/bin && curl -o ~/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod a+x ~/bin/repo
export PATH=~/bin:$PATH
git config --global user.name "Votre nom" && git config --global user.email "vous@exemple.com"
```

### 2. Sources LineageOS 16.0 + cet arbre
```bash
mkdir -p ~/android/lineage && cd ~/android/lineage
repo init -u https://github.com/LineageOS/android.git -b lineage-16.0 --depth=1
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/ujc201.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="LibreHU/android_device_alps_ac8257_demo" path="device/alps/ac8257_demo"
           remote="github" revision="lineage-16.0" />
</manifest>
EOF
repo sync -c -j"$(nproc)" --no-tags --no-clone-bundle
```

### 3. Fichiers de l'unite et applis LibreHU
L'unite sous TWRP (adb root) ou sous la ROM stock avec root, branchee en USB :
```bash
device/alps/ac8257_demo/tools/get_vendor_img.sh      # -> vendor/jancar/ac8257_demo/vendor.img (2 Go, reste local)
device/alps/ac8257_demo/tools/vendor_add_viper.sh    # pilote ViPERFX_RE dans cette image (sudo apt install e2fsprogs)
cd device/alps/ac8257_demo
./extract-files.sh                                   # interfaces HIDL Autochips de /system (adb)
librehu/fetch_apks.sh                                # derniers APK LibreHU (toutes les applis de la ROM)
cd ~/android/lineage
```

### 4. Build
```bash
export LC_ALL=C USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache && ccache -M 50G
source build/envsetup.sh
lunch lineage_ac8257_demo-userdebug
mka systemimage           # phase 1 : seulement system.img (boot et vendor restent stock)
# plus tard : mka bacon   # zip LineageOS complet
```
Resultat : `out/target/product/ac8257_demo/system.img`.

### 5. Installer (phase 1)
Rien n'est automatise. Avant tout :
1. **Sauvegarde complete** : SP Flash Tool (readback) avec le scatter stock, et sauvegarde TWRP de `system`,
   `vendor`, `boot`, `data`. Garder aussi `para` (`dd if=/dev/block/by-name/para of=...`).
2. **vbmeta**, une seule fois, a la main (jamais fait par ces outils) :
   `fastboot --disable-verity flash vbmeta vbmeta.img` (vbmeta stock).
3. Sous TWRP : *Install > Install Image* > `system.img` > **System Image**, puis *Wipe > Format Data* (LineageOS ne
   demarre pas sur les donnees de la ROM stock).
4. Retour arriere : restaurer la sauvegarde TWRP (ou SP Flash Tool).

Root : LineageOS 16.0 ne donne le root qu'a adb. Plusieurs fonctions de LibreHU-service en ont besoin (comme sur le
stock) : a ajouter (Magisk, ou KernelSU Next avec le noyau LibreHU).

## Roadmap

1. **Arbre de depart** — ✅ cette branche (20/10/2026), non compile.
2. **Premier build** de `system.img` et **premier demarrage** sur vendor + boot stock : ecran, tactile, adb, Wi-Fi,
   Bluetooth, GPS (modules vendor stock), audio (HAL ATC du vendor), MCU (`mcu_ready` puis LibreHU-service).
3. **Fonctions autoradio** avec les applis LibreHU : MCU / CAN, touches au volant, radio FM, camera de recul et AVM,
   AV-in, telephone (RIL MediaTek `c6m_1rild` avec la telephonie AOSP), Android Auto / CarPlay.
4. **Politique SELinux** du device (`mcu_ready`, applis) puis mode enforcing (aujourd'hui permissif, comme le stock).
5. **Noyau LibreHU** (`LibreHU-main`) a la place du noyau stock, `boot.img` construit, root (KernelSU Next).
6. **Zip LineageOS complet** (`mka bacon`) installable depuis TWRP, builds publies et mis a jour par l'appli OTA.

## Risques connus

- **RIL** : modem MediaTek (`ro.vendor.mtk_ril_mode=c6m_1rild`, `mtk-ril.so`) avec la telephonie AOSP de LineageOS :
  appels et donnees a verifier.
- **Applis Jancar absentes** (`com.jancar.*`, `com.autochips.*`) : leurs fonctions passent par les applis LibreHU ;
  ce qu'aucune appli LibreHU ne couvre encore manquera.
- **Rotation et affichage** : l'ecran est en 1280 x 720 paysage sur le stock ; a verifier au premier demarrage.
- Rien n'est encore compile : erreurs de build probables au premier essai, a corriger ici.

## Regles

- Rien n'est ecrit sous dm-verity et vbmeta n'est jamais desactive automatiquement :
  `fastboot --disable-verity flash vbmeta vbmeta.img` a la main.
- Ne pas publier ses partitions `nvram`, `nvdata`, `proinfo`, `persist`, `metazone`, ni `vendor.img` (fichiers
  proprietaires).
