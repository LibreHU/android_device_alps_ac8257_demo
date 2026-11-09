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
(`stable-4.9.337` : sources GPL Autochips + modifications LibreHU + correctifs linux-stable jusqu'a 4.9.337, la seule
branche suivie depuis le 01/11/2026). Applis : depots `LibreHU-*` de
[LibreHU](https://github.com/LibreHU).

## Approche

L'unite est **Treble** : partition vendor Android 9 separee (`ro.treble.enabled=true`, `ro.vndk.version=28`,
`ro.product.first_api_level=28`), system-as-root. Le manifest framework du `/system` stock est celui d'AOSP : aucun
HAL cote system propre a Jancar ou MediaTek. D'ou, pour la phase 1 :

| Partition | Contenu |
|---|---|
| `system` | **LineageOS 16.0 construit ici** + applis LibreHU (service, launcher, OTA, ViPER4Android, telephone, FM, widgets, BtnRemap, EasySource, Disc, MCU Toolkit, Android Auto, CarPlay) + `mcu_ready` |
| `vendor` | **vendor stock**, lu sur l'unite (`tools/get_vendor_img.sh`) et repris (`BOARD_PREBUILT_VENDORIMAGE`), avec le pilote ViPERFX_RE ajoute (`tools/vendor_add_viper.sh`) ; jamais publie |
| `boot` | **image de boot de la CI du noyau LibreHU** `stable-4.9.337` (`tools/fetch_kernel.sh` -> `prebuilt/boot-librehu-bootmenu.img`, prise telle quelle : `BOARD_PREBUILT_BOOTIMAGE`) : en-tete, ligne de commande et **pied AVB du boot stock**, sans lequel le LK refuse l'image (redemarrage au logo) ; KernelSU Next pour le root, menu de demarrage TWRP / Android / Fastboot. LineageOS ne construit pas de `boot.img` (voir [prebuilt/README.md](prebuilt/README.md)) |
| `dtbo`, `vbmeta`, `lk`, `tee`... | stock, non modifies |
| `recovery` | TWRP (branche `twrp`) ; LineageOS n'en construit pas (`TARGET_NO_RECOVERY`), son zip n'y touche pas |

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
| `librehu/` | applis LibreHU **toutes dans `/system/priv-app`** (comme le demande LibreHU-service : `SET_TIME`, Bluetooth, demarrage fiable), avec la liste blanche de leurs permissions privilegiees `privapp-permissions-librehu.xml` (LineageOS impose `ro.control_privapp_permissions=enforce` : une permission manquante fait planter `system_server` au demarrage ; `check_privapp.py`, lance par `fetch_apks.sh`, verifie chaque APK) : **LibreHU-service** (`latest-main`), **LibreHU Launcher** edition `librehu-service` (seul ecran d'accueil, remplace Trebuchet), **LibreHU Apps / OTA** (`latest-main`) ; APK telecharges par `fetch_apks.sh`, signature d'origine gardee : l'appli OTA les met ensuite a jour comme sur la ROM stock. **ViPER4Android LibreHU** 2.1.1 (`latest-librehu-service`). Aussi : **telephone**, **radio FM**, **widgets** et **BtnRemap** (edition `librehu-service`), **EasySource**, **Disc**, **MCU Toolkit** (`latest-main`), **Android Auto** (Open Headunit LibreHU, `latest-main`) et **CarPlay** (xcertplay LibreHU, `latest-master`) ; un APK absent est ignore. Toutes signees avec la cle LibreHU : l'appli OTA les met a jour |
| `proprietary-files.txt`, `extract-files.sh`, `setup-makefiles.sh` | interfaces HIDL Autochips cote system (camera de recul, AVM, affichage rapide, iAP2, audio ATC...) reprises du stock |
| `tools/get_vendor_img.sh` | lit la partition vendor de l'unite (lecture seule) |
| `tools/vendor_add_viper.sh` | ajoute a l'image vendor locale (debugfs, copie `vendor.img.orig` gardee) le pilote [ViPERFX_RE](https://github.com/likelikeslike/ViPERFX_RE) v2.1.1 (module officiel, SHA-256 verifie) : `libv4a_re.so` dans `/lib[64]/soundfx` et l'effet `v4a_standard_re` dans `/etc/audio_effects.xml`, comme le zip `viper4android-re` de LibreHU-flashablesZips. Dans vendor car sous Android 9 Treble les effets sont charges par le HAL audio du vendor, qui ne peut pas charger de bibliotheque de `/system` |
| `tools/fetch_kernel.sh` | noyau LibreHU `stable-4.9.337` (`Image.gz-dtb`) et ses modules Wi-Fi / BT / GPS / FM depuis la release `latest-stable-4.9.337` (empreintes de GitHub verifiees, noyau de l'image = celui des modules) ; non versionnes |
| `tools/vendor_add_conn_modules.sh` | met ces modules dans `/lib/modules` de l'image vendor locale (debugfs, droits et contexte SELinux de l'original, marqueur `.librehu_conn`, copie `vendor.img.orig` gardee) : le noyau LibreHU refuse ceux du vendor stock (CRC des symboles differents), comme le font les zips `kernel-stable` sur l'unite |
| `sepolicy/private/` | domaine SELinux de `mcu_ready` (cote system, `BOARD_PLAT_PRIVATE_SEPOLICY_DIR`) : sans lui, l'init d'Android 9 **refuse de lancer le service, meme en permissif** (« has incorrect label or no domain transition », `init/service.cpp`), PC_READY ne part pas et le MCU coupe le SoC une dizaine de secondes apres le demarrage |
| `config.fs`, `BOARD_ROOT_EXTRA_FOLDERS` | points de montage du stock a la racine de `system` : `/jancar` (0755 root:root, partition `jancar` du fstab du vendor) et `/avm` (0775 root:system). Sans `/jancar`, `fs_mgr` ne peut pas monter la partition (racine en lecture seule), `mount_all` echoue et init ne lance pas la classe `main` (zygote) : Android ne demarre pas. Reperes par Reo Au In. `/vendor` est cree par le build |
| `rootdir/etc/fstab.ac8257` | fstab du vendor stock |

## Compiler from scratch

**Guide detaille pas a pas** (conteneur LXC Proxmox, Ubuntu 20.04, sources, fichiers de l'unite, build du zip
flashable et des images, installation, mises a jour, depannage) : [docs/BUILD.md](docs/BUILD.md). Resume ci-dessous.

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
device/alps/ac8257_demo/tools/fetch_kernel.sh        # noyau LibreHU stable-4.9.337 : images de boot + modules (prebuilt/)
# (tools/fetch_kernel.sh test-wifi-chipid : branche de test, correctif de l'identifiant de puce Wi-Fi)
device/alps/ac8257_demo/tools/vendor_add_conn_modules.sh  # ces modules dans l'image vendor (Wi-Fi, BT, GPS, FM)
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
mka systemimage           # phase 1 : seulement system.img (boot et vendor restent ceux de l'unite)
mka bootimage             # boot.img = copie de prebuilt/boot-librehu-bootmenu.img (CI du noyau, pied AVB stock)
# ou tout en une fois : mka bacon (images + zip flashable TWRP, qui ecrit system et boot ; vendor : docs/BUILD.md)
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

Root : LineageOS 16.0 ne donne le root qu'a adb ; plusieurs fonctions de LibreHU-service en ont besoin (comme sur le
stock). Le noyau LibreHU contient KernelSU Next : installer son gestionnaire (v3.4.2) apres le premier demarrage.
Avec le noyau stock, ajouter Magisk.

USB : le transfert de fichiers avec un ordinateur (MTP) est **desactive par defaut** par LibreHU-service (reglage
Avance -> Autochips) ; LineageOS a le `MtpReceiver` de MediaProvider, le serveur MTP demarre donc seul une fois le
reglage active (sur la ROM stock, c'est le service qui le demarre).

## Roadmap

1. **Arbre de depart** — ✅ cette branche (20/10/2026), non compile.
2. **Premier build** de `system.img` et **premier demarrage** sur vendor + boot stock : ecran, tactile, adb, Wi-Fi,
   Bluetooth, GPS (modules vendor stock), audio (HAL ATC du vendor), MCU (`mcu_ready` puis LibreHU-service).
3. **Fonctions autoradio** avec les applis LibreHU : MCU / CAN, touches au volant, radio FM, camera de recul et AVM,
   AV-in, telephone (RIL MediaTek `c6m_1rild` avec la telephonie AOSP), Android Auto / CarPlay.
4. **Politique SELinux** du device : domaine de `mcu_ready` fait (09/11/2026, indispensable pour qu'init le lance) ;
   ensuite ses regles et celles des applis, puis le mode enforcing (aujourd'hui permissif, comme le stock).
5. **Noyau LibreHU** a la place du noyau stock, root (KernelSU Next) — dans l'arbre depuis le 01/11/2026 ; depuis le
   09/11/2026, `boot.img` est l'image de la CI du noyau (pied AVB stock), modules de connectivite dans vendor, a tester.
6. **Zip LineageOS complet** (`mka bacon`) installable depuis TWRP, builds publies et mis a jour par l'appli OTA.

## Risques connus

Premier essai d'un testeur (Reo Au In, 08/11/2026, build de la branche du 07/11) : Android demarre puis l'unite
redemarre au bout d'une dizaine de secondes ; pas de journal. Corrige ici depuis (09/11), a reessayer :
- **`mcu_ready` jamais lance** (pas de domaine SELinux, voir `sepolicy/`) : sans PC_READY, le MCU coupe le SoC une
  dizaine de secondes apres le demarrage ;
- **`boot.img` de LineageOS sans pied AVB** : refuse par le LK (redemarrage au logo) ; c'est maintenant l'image de la
  CI du noyau ;
- **applis LibreHU dans `/system/app`** : sans leurs permissions privilegiees (heure, Bluetooth, widgets...) ; toutes
  en `/system/priv-app` avec leur liste blanche ;
- **`/jancar` et `/avm` absents de la racine** (vus par Reo Au In, qui les avait ajoutes a la main) : sans `/jancar`,
  `mount_all` echoue et init ne lance ni zygote ni le reste de la classe `main` ; crees par le build depuis le 09/11.

Reo Au In a aussi repare son zip du 07/11 a sa facon (vbmeta non signe ecrit par le zip, pied AVB et drapeau de
premier montage retires, arbre de hachage de vendor reconstruit, `fpsgo.ko` coupe) : ce depot garde ses regles
(vbmeta jamais ecrit, `fastboot --disable-verity` a la main ; image de boot de la CI avec le pied AVB du stock) ;
`fpsgo.ko` du stock est refuse par le noyau LibreHU sans autre effet (docs/STABLE.md du noyau).

Toujours ouverts :
- **Wi-Fi : identifiant de puce `0x0000`** : sur un `/data` vide (Format Data), le noyau `stable-4.9.337` repondait 0
  a la demande d'identifiant de `wmt_loader`, qui l'enregistre dans `persist.vendor.connsys.chipid` ; le pilote Wi-Fi
  demarre alors avec une puce 0 et l'unite redemarre en boucle des que le Wi-Fi s'allume (constate par Reo Au In,
  repare chez lui par `setprop persist.vendor.connsys.chipid 0x8257`). Correctif dans la branche de test
  `test-wifi-chipid` du noyau (`tools/fetch_kernel.sh test-wifi-chipid`), a essayer ; en attendant, apres le premier
  demarrage : `su -c 'setprop persist.vendor.connsys.chipid 0x8257'` puis redemarrer, Wi-Fi coupe.
- **`autochips.jar` absent** : sur le stock, les classes Autochips sont dans `/system/framework/autochips.jar` (dans
  le `BOOTCLASSPATH`) ; ce `/system` ne l'a pas. Sans lui, LibreHU-service ne peut pas rendre l'affichage a Android
  apres l'ARM2 (video materielle verte : cameras, AV-in) ni lire les reglages Autochips. A recuperer sur une unite
  sous le stock (`adb pull /system/framework/autochips.jar`, et `/system/framework/arm64/boot-autochips.*` si le jar
  n'a plus son `classes.dex`), puis a ajouter a `proprietary-files.txt` et au `BOOTCLASSPATH`.
- **Autres valeurs `persist` d'un `/data` vide** : comme `connsys.chipid`, des proprietes ecrites sur le stock par les
  applis Jancar ou le premier demarrage d'usine manquent apres Format Data ; liste a tirer d'un `getprop` du stock
  (rapport LibreHU Helper).

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

## Fluidité des applis LibreHU

Les applis LibreHU (Jetpack Compose) sont **précompilées en code natif** (`speed`) à la construction de la ROM
(`PRODUCT_DEXPREOPT_SPEED_APPS` dans `device.mk`, `LOCAL_DEX_PREOPT := nostripping` dans `librehu/Android.mk` : le dex
reste dans l'APK, la signature d'origine et les mises à jour dans `/data` restent valables), et `pm.dexopt.install=speed`
compile aussi les installations et mises à jour. Sans cela, Android 9 installe une appli hors Play Store en
`speed-profile`, qui sans profil vaut `verify` (pas de code natif), et ne compile en arrière-plan qu'appareil inactif et
en charge, ce qui n'arrive presque jamais sur un autoradio (source.android.com, *Package Manager configuration*). Sur la
ROM stock, LibreHU-service fait la même chose en root (Avancé → Tweaks → *Fluidité des applis LibreHU*).

## Licence

Copyright (C) 2026 les contributeurs de LibreHU.

Les fichiers de LibreHU sont sous **GNU AGPL v3 ou ulterieure** (`AGPL-3.0-or-later`, fichier [`LICENSE`](LICENSE)),
avec les [termes additionnels](LICENSE-ADDITIONAL-TERMS.md) de son article 7 : garder la mention « Basé sur LibreHU –
https://github.com/LibreHU » et marquer une version modifiee comme telle. Qui distribue une version modifiee doit en
donner le code source complet sous la meme licence. Les autres gardent leur licence :

| Quoi | Ou | Auteur | Licence |
|---|---|---|---|
| Fichiers de base de l'arbre (en-tete Apache-2.0 garde) | `Android.mk`, `AndroidProducts.mk`, `BoardConfig.mk`, `device.mk`, `lineage_ac8257_demo.mk`, `extract-files.sh`, `setup-makefiles.sh`, `vendorsetup.sh` | [twrpdtgen](https://github.com/twrpdtgen/twrpdtgen) (SebaUbuntu), The Android Open Source Project, The LineageOS Project | Apache-2.0 |
| Noyau stock (binaire de la mise a jour Jancar ; source : branche `autochips-gpl` du [depot du noyau](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9/tree/autochips-gpl)) | `prebuilt/` | Jancar, AutoChips, les auteurs de Linux | GPL-2.0 |
