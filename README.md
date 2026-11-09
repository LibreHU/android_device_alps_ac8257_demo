# LineageOS 16.0 pour l'UJC201 (Jancar, Autochips AC8257)

*English: [README.en.md](README.en.md)*

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
| `vendor` | **vendor stock**, lu sur l'unite (`tools/get_vendor_img.sh`) et repris (`BOARD_PREBUILT_VENDORIMAGE`), avec le pilote ViPERFX_RE ajoute (`tools/vendor_add_viper.sh`) ; reste chez vous (2 Gio, propre a l'unite) |
| `boot` | **image de boot de la CI du noyau LibreHU** `stable-4.9.337` (`tools/fetch_kernel.sh` -> `prebuilt/boot-librehu-bootmenu.img`, prise telle quelle : `BOARD_PREBUILT_BOOTIMAGE`) : en-tete, ligne de commande et **pied AVB du boot stock**, sans lequel le LK refuse l'image (redemarrage au logo) ; KernelSU Next pour le root, menu de demarrage TWRP / Android / Fastboot. LineageOS ne construit pas de `boot.img` (voir [prebuilt/README.md](prebuilt/README.md)) |
| `dtbo`, `vbmeta`, `lk`, `tee`... | stock, non modifies |
| `recovery` | TWRP (branche `twrp`) ; LineageOS n'en construit pas (`TARGET_NO_RECOVERY`), rien ne l'ecrit |

LineageOS 16.0 est la seule version de LineageOS de meme niveau qu'Android 9 : VNDK 28 et politique SELinux 28.0
correspondent au vendor stock, sans couche de compatibilite.

### Ce que l'arbre contient

| Fichier | Role |
|---|---|
| `BoardConfig.mk` | architecture (Cortex-A53, arm64 + arm), boot (en-tete v1, adresses du stock), partitions (table eMMC du noyau #72), vendor prebuilt, VNDK, politique audio XML du vendor (`USE_XML_AUDIO_POLICY_CONF`, comme le stock ; sinon la configuration de l'emulateur goldfish), pile Bluetooth d'autoradio (`bluetooth/`), `SKIP_BOOT_JARS_CHECK` (le paquet `com.autochips.*` d'`autochips.jar` n'est pas dans la liste blanche d'AOSP) |
| `lineage_ac8257_demo.mk`, `AndroidProducts.mk`, `vendorsetup.sh` | produit `lineage_ac8257_demo`, **userdebug seulement** (en user : SELinux toujours enforcing, adb avec autorisation, domaines permissifs refuses) (profil telephone : modem 4G), empreinte du vendor stock ; **adb sans autorisation des le demarrage et `adb root` autorise, a chaque build** (`WITH_ADB_INSECURE` de LineageOS : `ro.adb.secure=0`, `persist.sys.usb.config=adb` ; `persist.sys.root_access=2` ; userdebug et eng seulement, voir « Installer ») |
| `device.mk` | 1280 x 720 a 160 dpi (`wm size` du stock), proprietes du stock, overlays, paquets ; **journaux persistants a chaque build** (`persist.logd.logpersistd=logcatd` + `logpersist.start` : tous les tampons de logcat dans `/data/misc/logd/`, 256 fichiers de 1 Mio au plus) ; ECNR des appels active comme sur le stock ; `PRODUCT_BOOT_JARS += autochips` |
| `overlay/` | barre de navigation a l'ecran, pas de luminosite auto, paysage fixe, ecran toujours allume ; **profils Bluetooth d'une voiture** (`packages/apps/Bluetooth` : HFP client relie a Telecom, A2DP sink, AVRCP controleur, PBAP et MAP client ; roles de telephone coupes), ceux de la voiture de reference d'Android 9 (`packages/services/Car`) |
| `bluetooth/bdroid_buildcfg.h` | pile Bluetooth (`BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR`) : l'autoradio se declare comme une **voiture** (classe d'appareil `0x240420` : Audio + Rendering, Audio/Video, « Car audio » ; par defaut smartphone) et l'A2DP sink est compile (`BTA_AV_SINK_INCLUDED`, faux par defaut : sans lui pas d'enregistrement SDP « Audio Sink ») |
| `mcu_ready/` | service natif : envoie `PC_READY` au MCU Jancar (`/dev/ttyS1`) des le demarrage (`on init`), jusqu'a sa reponse. **Indispensable** : sans lui le MCU coupe le SoC une dizaine de secondes apres le demarrage (sur le stock c'est `com.jancar.services` qui l'envoie) |
| `librehu/` | applis LibreHU **toutes dans `/system/priv-app`** (comme le demande LibreHU-service : `SET_TIME`, Bluetooth, demarrage fiable), avec la liste blanche de leurs permissions privilegiees `privapp-permissions-librehu.xml` (LineageOS impose `ro.control_privapp_permissions=enforce` : une permission manquante fait planter `system_server` au demarrage ; `check_privapp.py`, lance par `fetch_apks.sh`, verifie chaque APK) : **LibreHU-service** (`latest-main`), **LibreHU Launcher** edition `librehu-service` (seul ecran d'accueil, remplace Trebuchet), **LibreHU Apps / OTA** (`latest-main`) ; APK telecharges par `fetch_apks.sh`, signature d'origine gardee : l'appli OTA les met ensuite a jour comme sur la ROM stock. **ViPER4Android LibreHU** 2.1.1 (`latest-librehu-service`). Aussi : **telephone**, **radio FM**, **widgets** et **BtnRemap** (edition `librehu-service`), **EasySource**, **Disc**, **MCU Toolkit** (`latest-main`), **Android Auto** (Open Headunit LibreHU, `latest-main`) et **CarPlay** (xcertplay LibreHU, `latest-master`) ; un APK absent est ignore. Toutes signees avec la cle LibreHU : l'appli OTA les met a jour. **Bibliotheques natives** (`native_libs.py`, lance par `fetch_apks.sh`) : Android 9 ne les extrait jamais pour une appli systeme, et le build recompresserait un APK aux bibliotheques compressees, ce qui retire sa signature v2 (PackageManager le refuserait) ; un tel APK (Android Auto) est donc installe tel quel et ses bibliotheques extraites dans `/system/priv-app/<appli>/lib/arm64/` ; une appli 32 bits seulement (FM) est precompilee pour arm (`LOCAL_MULTILIB := 32`). `ksunext/` : **gestionnaire KernelSU Next v3.4.2** (version figee sur l'API du noyau, empreinte verifiee par `fetch_apks.sh`), garde dans `/system/etc/librehu/` et installe dans `/data/app` au premier demarrage par `librehu_ksunext` : le noyau ne reconnait son gestionnaire que la (`throne_tracker.c`), jamais en appli systeme |
| `proprietary-files.txt`, `extract-files.sh`, `setup-makefiles.sh` | fichiers proprietaires cote `/system` repris du stock V1.151R6 : interfaces HIDL Autochips (camera de recul, AVM, affichage rapide, iAP2, audio ATC...), `autochips.jar` (BOOTCLASSPATH, epingle par SHA-1) et ses bibliotheques JNI, `libusbdvr.so`. Ils sont dans le depot [android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo) (branche `lineage-16.0`, clone par le manifest local) ; `extract-files.sh` ne sert que pour un autre firmware |
| `tools/get_vendor_img.sh` | lit la partition vendor de l'unite (lecture seule) |
| `tools/vendor_add_viper.sh` | ajoute a l'image vendor locale (debugfs, copie `vendor.img.orig` gardee) le pilote [ViPERFX_RE](https://github.com/likelikeslike/ViPERFX_RE) v2.1.1 (module officiel, SHA-256 verifie) : `libv4a_re.so` dans `/lib[64]/soundfx` et l'effet `v4a_standard_re` dans `/etc/audio_effects.xml`, comme le zip `viper4android-re` de LibreHU-flashablesZips. Dans vendor car sous Android 9 Treble les effets sont charges par le HAL audio du vendor, qui ne peut pas charger de bibliotheque de `/system` |
| `tools/fetch_kernel.sh` | noyau LibreHU `stable-4.9.337` (`Image.gz-dtb`) et ses modules Wi-Fi / BT / GPS / FM depuis la release `latest-stable-4.9.337` (empreintes de GitHub verifiees, noyau de l'image = celui des modules) ; non versionnes. Ajoute **`androidboot.selinux=permissive`** a la ligne de commande de l'en-tete des images de boot (seul champ modifie, pied AVB garde) : sans lui l'init de LineageOS passe en enforcing (`BOARD_KERNEL_CMDLINE` ne sert pas avec une image prebuilt, le LK n'ajoute rien) ; `LIBREHU_SELINUX=enforcing tools/fetch_kernel.sh` pour ne pas l'ajouter |
| `tools/vendor_add_conn_modules.sh` | met ces modules dans `/lib/modules` de l'image vendor locale (debugfs, droits et contexte SELinux de l'original, marqueur `.librehu_conn`, copie `vendor.img.orig` gardee) : le noyau LibreHU refuse ceux du vendor stock (CRC des symboles differents), comme le font les zips `kernel-stable` sur l'unite |
| `sepolicy/private/` | domaine SELinux de `mcu_ready` (cote system, `BOARD_PLAT_PRIVATE_SEPOLICY_DIR`) : sans lui, l'init d'Android 9 **refuse de lancer le service, meme en permissif** (« has incorrect label or no domain transition », `init/service.cpp`), PC_READY ne part pas et le MCU coupe le SoC une dizaine de secondes apres le demarrage ; meme chose pour `librehu_ksunext`. Les deux domaines sont **permissifs** a eux seuls (`permissive`, refuse en build user) : PC_READY part meme si SELinux passait en enforcing (`/dev/ttyS1` est un type de la politique vendor, que la politique system ne peut pas nommer) |
| `config.fs`, `BOARD_ROOT_EXTRA_FOLDERS` | points de montage du stock a la racine de `system` : `/jancar` (0755 root:root, partition `jancar` du fstab du vendor) et `/avm` (0775 root:system). Sans `/jancar`, `fs_mgr` ne peut pas monter la partition (racine en lecture seule), `mount_all` echoue et init ne lance pas la classe `main` (zygote) : Android ne demarre pas. Reperes par Reo Au In. `/vendor` est cree par le build |
| `rootdir/etc/init/librehu.rc` | valeurs `persist` du stock qu'un `/data` vide n'a pas (getprop du stock, rapport LibreHU Helper) : `persist.vendor.connsys.chipid` mis a `0x8257` a `early-boot` s'il vaut `-1` (build.prop du vendor) ou `0x0000`, avant le lancement de `wmt_loader` (Wi-Fi) ; propriete vendor de l'ECNR alignee sur la persist |
| `rootdir/etc/fstab.ac8257` | fstab du vendor stock |

## Compiler from scratch

**Guide detaille pas a pas** (conteneur LXC Proxmox, Ubuntu 20.04, sources, fichiers de l'unite, build
des images, installation, mises a jour, depannage) : [docs/BUILD.md](docs/BUILD.md). Resume ci-dessous.

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
  <project name="LibreHU/android_vendor_jancar_ac8257_demo" path="vendor/jancar/ac8257_demo"
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
# fichiers proprietaires de /system : deja dans le depot vendor (manifest local) ; autre firmware que V1.151R6 :
# ./extract-files.sh (depuis l'unite, adb) ou ./extract-files.sh ~/stock (docs/BUILD.md, etape 5)
librehu/fetch_apks.sh                                # derniers APK LibreHU (toutes les applis de la ROM) + gestionnaire KernelSU Next
cd ~/android/lineage
```

### 4. Build
```bash
export LC_ALL=C USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache && ccache -M 50G
source build/envsetup.sh
lunch lineage_ac8257_demo-userdebug
mka systemimage bootimage vendorimage
```
Resultat dans `out/target/product/ac8257_demo/` : `system.img`, `boot.img` (image de la CI du noyau LibreHU, pied AVB
stock, `androidboot.selinux=permissive`), `vendor.img` (votre vendor avec ViPERFX_RE et les modules de ce noyau).
**Pas de zip** : LineageOS 16.0 refuse d'en faire un pour un appareil non A/B sans recovery
(`ota_from_target_files.py`), et l'arbre garde TWRP comme recovery (detail : [docs/BUILD.md](docs/BUILD.md), etape 6).

### 5. Installer
Rien n'est automatise. Avant tout :
1. **Sauvegarde complete** : SP Flash Tool (readback) avec le scatter stock, et sauvegarde TWRP de `system`,
   `vendor`, `boot`, `data`. Garder aussi `para` (`dd if=/dev/block/by-name/para of=...`).
2. **vbmeta**, une seule fois, a la main (jamais fait par ces outils), **avec les deux options** :
   `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img` (vbmeta stock : sauvegarde, ou
   `images/vbmeta.img` d'un rapport LibreHU Helper). Le vbmeta stock **chaine la partition `system`** (cle Jancar) et
   le `system.img` de LineageOS n'a pas le pied AVB attendu : avec `--disable-verity` seul, le LK et l'init (montage de
   vendor) s'arretent sur `ERROR_INVALID_METADATA` de libavb, fatal meme deverrouille, et l'unite redemarre au logo
   sans aucun journal. `--disable-verification` fait ignorer la chaine. Deja passe avec `--disable-verity` seul (noyau
   LibreHU sous stock) : le refaire avec les deux (detail : [docs/BUILD.md](docs/BUILD.md), etape 8).
3. Sous TWRP : *Wipe > Format Data* (LineageOS ne demarre pas sur les donnees de la ROM stock), puis
   `adb reboot bootloader` et `fastboot flash` de `system.img`, `boot.img` et `vendor.img`, **les trois** : le vendor a
   les modules du noyau LibreHU (le noyau stock les refuse) et seul ce `boot.img` met SELinux en permissif.
4. Retour arriere : restaurer la sauvegarde TWRP (ou SP Flash Tool).

Root : LineageOS 16.0 ne donne le root qu'a adb ; plusieurs fonctions de LibreHU-service en ont besoin (comme sur le
stock). Le noyau LibreHU contient KernelSU Next ; son gestionnaire (v3.4.2) est **installe tout seul** dans `/data/app`
une fois Android demarre (journal : `logcat -s LibreHU-KSU`). L'ouvrir, puis onglet Superuser : autoriser
LibreHU-service (KernelSU ne pose pas de question). Avec le noyau stock, ajouter Magisk.

adb : **actif et sans autorisation des le premier demarrage**, a chaque build userdebug ou eng (celui de
[docs/BUILD.md](docs/BUILD.md)) ; en `user`, Android 9 exige toujours l'autorisation (`ALLOW_ADBD_NO_AUTH`).
`adb root` est autorise par defaut (*Options pour les developpeurs > Debogage root* sur « ADB uniquement »,
`persist.sys.root_access=2`) ; adbd demarre en shell, `adb root` est a taper une fois par demarrage. Attention : toute
personne qui branche un ordinateur sur l'USB de l'unite obtient un shell, puis le root, sans confirmation a l'ecran.
Le remettre sur « Desactive » dans les reglages ferme le root (valeur gardee dans `/data`).

Journaux : `logcat` de tous les tampons enregistre en continu dans `/data/misc/logd/` (garde apres un redemarrage,
256 Mio au plus). Lecture en root : `adb root` puis `adb pull /data/misc/logd`, ou `su -c 'cat /data/misc/logd/logcat*'`.
Journal du noyau du demarrage precedent : `/proc/last_kmsg` (docs/BUILD.md, Depannage).

USB : le transfert de fichiers avec un ordinateur (MTP) est **desactive par defaut** par LibreHU-service (reglage
Avance -> Autochips) ; LineageOS a le `MtpReceiver` de MediaProvider, le serveur MTP demarre donc seul une fois le
reglage active (sur la ROM stock, c'est le service qui le demarre).

## Roadmap

1. **Arbre de depart** — ✅ cette branche (20/10/2026), non compile.
2. **Premier build** (images `system`, `boot`, `vendor`) et **premier demarrage** sur vendor stock + noyau LibreHU : ecran, tactile, adb, Wi-Fi,
   Bluetooth, GPS (modules du noyau LibreHU dans vendor), audio (HAL ATC du vendor), MCU (`mcu_ready` puis LibreHU-service).
3. **Fonctions autoradio** avec les applis LibreHU : MCU / CAN, touches au volant, radio FM, camera de recul et AVM,
   AV-in, telephone (RIL MediaTek `c6m_1rild` avec la telephonie AOSP), Android Auto / CarPlay.
4. **Politique SELinux** du device : domaine de `mcu_ready` fait (09/11/2026, indispensable pour qu'init le lance) ;
   ensuite ses regles et celles des applis, puis le mode enforcing (aujourd'hui permissif, comme le stock).
5. **Noyau LibreHU** a la place du noyau stock, root (KernelSU Next) — dans l'arbre depuis le 01/11/2026 ; depuis le
   09/11/2026, `boot.img` est l'image de la CI du noyau (pied AVB stock), modules de connectivite dans vendor, a tester.
6. **Fichiers proprietaires de `/system`** dans un depot vendor — ✅ 09/11/2026 : interfaces HIDL Autochips,
   `autochips.jar` desodexe (`PRODUCT_BOOT_JARS`) et ses JNI ([android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo)), non compile.
7. **Builds publies** (images) et mis a jour par l'appli OTA. Zip flashable : impossible tel quel (LineageOS 16.0 ne fait
   pas de zip pour un appareil non A/B sans recovery) ; il faudrait un installateur propre a LibreHU.

## Risques connus

Premier essai d'un testeur (Reo Au In, 08/11/2026, build de la branche du 07/11) : Android demarre puis l'unite
redemarre au bout d'une dizaine de secondes ; pas de journal. Cause la plus probable : l'identifiant de puce Wi-Fi
`0x0000` d'un `/data` vide (plus bas). Corrige ici depuis (09/11), a reessayer :
- **`mcu_ready` jamais lance** (pas de domaine SELinux, voir `sepolicy/`) : sans PC_READY, le MCU coupe le SoC (10 s
  apres une sortie de veille, 15 min au demarrage a froid : `docs/mcu_firmware.md` de MCU-tools-app, section 5).
  Depuis le 09/11 (nuit), `mcu_ready` attend la reponse du MCU a PC_READY (acquittement `C0 1F` ou version `0A`) et
  non la premiere trame venue (le MCU relaie les trames du boitier CAN sans PC_READY), renvoie toutes les secondes,
  et ecrit aussi dans le journal du noyau (`dmesg | grep mcu_ready`) ;
- **`boot.img` de LineageOS sans pied AVB** : refuse par le LK (redemarrage au logo) ; c'est maintenant l'image de la
  CI du noyau ;
- **applis LibreHU dans `/system/app`** : sans leurs permissions privilegiees (heure, Bluetooth, widgets...) ; toutes
  en `/system/priv-app` avec leur liste blanche ;
- **`/jancar` et `/avm` absents de la racine** (vus par Reo Au In, qui les avait ajoutes a la main) : sans `/jancar`,
  `mount_all` echoue et init ne lance ni zygote ni le reste de la classe `main` ; crees par le build depuis le 09/11.
- **SELinux en enforcing** (trouve a l'audit du 09/11 au soir) : avec l'image de boot prebuilt, la ligne
  `androidboot.selinux=permissive` de `BoardConfig.mk` ne servait plus et le LK ne l'ajoute pas ; l'init de LineageOS
  userdebug passait donc en enforcing, `mcu_ready` (sans regles) ne pouvait pas ouvrir `/dev/ttyS1` et le MCU coupait
  le SoC. Corrige : `tools/fetch_kernel.sh` l'ajoute a l'en-tete des images de boot, et `mcu_ready` / `librehu_ksunext`
  sont des domaines permissifs. A verifier au demarrage : `adb shell getenforce` = `Permissive`.
- **vbmeta : `system` chaine** (audit du 09/11, nuit) : le vbmeta stock contient `chain recovery`, `chain system`,
  `hashtree vendor`, `hash dtbo` et `hash boot`. Le LK et l'init de LineageOS suivent la chaine de `system` et lisent
  le vbmeta du pied AVB de la partition ; celui de LineageOS n'en a pas (`BOARD_AVB_ENABLE := false`) :
  `ERROR_INVALID_METADATA`, fatal meme deverrouille (`external/avb/libavb/avb_slot_verify.c` d'Android 9,
  `result_should_continue` ; `system/core/fs_mgr/fs_mgr_avb.cpp`). Avec `--disable-verity` seul, le demarrage
  dependait donc de restes du system stock en fin de partition. Corrige : `fastboot --disable-verity
  --disable-verification` (etape 5 ci-dessus), ce que faisait aussi le vbmeta « flags 3 » de Reo Au In.
- **Liste blanche des permissions privilegiees en `enforce`** (audit du 09/11, nuit) : LineageOS impose
  `ro.control_privapp_permissions=enforce`, ou une seule permission privilegiee manquante fait planter system_server a
  chaque demarrage ; le stock est en `log`. Remis a `log` (`lineage_ac8257_demo.mk`, avant les `inherit-product` pour
  passer devant LineageOS).
- **Proprietes du `default.prop` du vendor** (audit du 09/11, nuit) : `ro.zygote` et `ro.vndk.version` viennent du
  `default.prop` du vendor stock ; reprises cote system par securite, et `persist.sys.usb.config=adb` dans le `build.prop` du
  system pour garder adb quoi que pose le vendor (`device.mk`).

Reo Au In a aussi repare son zip du 07/11 a sa facon (vbmeta non signe ecrit par le zip, pied AVB et drapeau de
premier montage retires, arbre de hachage de vendor reconstruit, `fpsgo.ko` coupe) : ce depot garde ses regles
(vbmeta jamais ecrit par les outils, `fastboot --disable-verity --disable-verification` a la main ; image de boot de la
CI avec le pied AVB du stock) ; `fpsgo.ko` du stock est refuse par le noyau LibreHU sans autre effet (docs/STABLE.md du
noyau).

Toujours ouverts :
- **Wi-Fi : identifiant de puce `0x0000`** : sur un `/data` vide (Format Data), le noyau `stable-4.9.337` repondait 0
  a la demande d'identifiant de `wmt_loader`, qui l'enregistre dans `persist.vendor.connsys.chipid` ; le pilote Wi-Fi
  demarre alors avec une puce 0 et l'unite redemarre en boucle des que le Wi-Fi s'allume (constate par Reo Au In,
  repare chez lui par `setprop persist.vendor.connsys.chipid 0x8257`). Depuis le 09/11, `rootdir/etc/init/librehu.rc`
  pose `0x8257` a `early-boot` (avant `wmt_loader`, quel que soit le noyau) et remplace un `0x0000` deja enregistre ;
  correctif du noyau aussi dans la branche de test `test-wifi-chipid` (`tools/fetch_kernel.sh test-wifi-chipid`).
  Les deux sont a essayer.
- **`autochips.jar`** (09/11) : sur le stock, les classes Autochips sont dans `/system/framework/autochips.jar` (dans
  le `BOOTCLASSPATH`) ; sans lui, LibreHU-service ne peut pas rendre l'affichage a Android apres l'ARM2 (video
  materielle verte : cameras, AV-in) ni lire les reglages Autochips. Desodexe de `boot-autochips.vdex` (stock
  V1.151R6) dans le depot [android_vendor_jancar_ac8257_demo](https://github.com/LibreHU/android_vendor_jancar_ac8257_demo)
  (branche `lineage-16.0`, manifest local ci-dessus), epingle dans `proprietary-files.txt`, `PRODUCT_BOOT_JARS +=
  autochips` (`device.mk`), avec ses bibliotheques JNI (`lib{,64}/lib{atcavm,atcvobsub,dvr,logo,metazone}_jni.so`)
  et `libusbdvr.so` (dependance de `libdvr_jni.so`), dans `proprietary-files.txt` et le depot vendor comme les
  interfaces HIDL. **Pas encore compile ni essaye** (attendu : `echo $BOOTCLASSPATH` contient `autochips.jar`,
  LibreHU-service trouve `AtcMetazone`, `AtcLogo`, `BackCar`, sans `ClassNotFoundException` ni
  `UnsatisfiedLinkError`).
- **Autres valeurs `persist` d'un `/data` vide** : tirees du `getprop` d'un stock (rapport LibreHU Helper du
  04/11/2026, 415 proprietes `persist`, dont 331 viennent du `build.prop` du vendor stock, garde ici). Reprises :
  `connsys.chipid` et l'ECNR des appels (`persist.audiohal.third_ecnr_lib.enable=1`). Laissees : gain du micro (remis
  par LibreHU-service), `persist.sf.hwrotation=90` (le SurfaceFlinger d'AOSP ne lit que `ro.sf.hwrotation`, l'ecran est
  en 1280 x 720 rotation 0 sur le stock), AEE (`persist.vendor.mtk.aee.mode=4`... : sens non verifie), qualite d'image
  `persist.vendor.sys.pq.*` et couleurs `persist.sys.rgb.*` (lecteurs inconnus sans les fichiers du vendor), proprietes
  des applis Jancar et de leur pile Bluetooth, choix de l'utilisateur (voiture, langue, fuseau) et
  `persist.netd.stable_secret` (propre a chaque unite).
- **Son des appels Bluetooth** : en HFP client, le Bluetooth d'Android 9 confie le son de l'appel au HAL audio du
  vendor (parametres `hfp_enable`, `hfp_set_sampling_rate`, appareils BT SCO de `audio_policy_configuration.xml`) ;
  le HAL audio MediaTek du stock les gere-t-il ? A essayer (sur le stock, c'est la pile Bluetooth de Jancar qui
  passait les appels).

- **RIL** : modem MediaTek (`ro.vendor.mtk_ril_mode=c6m_1rild`, `mtk-ril.so`) avec la telephonie AOSP de LineageOS :
  appels et donnees a verifier.
- **Applis Jancar absentes** (`com.jancar.*`, `com.autochips.*`) : leurs fonctions passent par les applis LibreHU ;
  ce qu'aucune appli LibreHU ne couvre encore manquera.
- **Rotation et affichage** : l'ecran est en 1280 x 720 paysage sur le stock ; a verifier au premier demarrage.
- Rien n'est encore compile : erreurs de build probables au premier essai, a corriger ici.

## Regles

- Rien n'est ecrit sous dm-verity et vbmeta n'est jamais desactive automatiquement :
  `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img` a la main.
- Ne jamais publier les donnees propres a l'unite : adresses MAC Bluetooth et Wi-Fi, numero de serie, certificat Apple
  MFi (donc ni `nvram`, `nvdata`, `proinfo` tels quels, ni `persist` / `metazone` sans verification). Les fichiers
  proprietaires Jancar / Autochips / MediaTek sont publies (depot vendor), verifies avant chaque ajout.

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
