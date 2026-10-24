# TWRP – Jancar UJC201 (Autochips AC8257, carte JAC_8258C)

Arbre TWRP (branche **twrp-12.1**) pour les autoradios Android « UJC201 » (SIXWIN, Podofo, Hikity…).
**Teste et fonctionnel** sur une unite SIXWIN, firmware `UJC201-V1.151R6-260122_0427-RH-C0-CYA` (noyau `4.9.117+ #72, 22/01/2026`),
auparavant `UJC201-V1.1.35R6-250718_0429` (noyau `4.9.117+ #25` : meme configuration, memes symboles exportes et memes
CRC que #72, donc memes modules).

## Branches
| Branche | Contenu |
|---|---|
| **`twrp`** (par defaut) | cet arbre TWRP, sa CI et ses releases |
| [`lineage-16.0`](https://github.com/LibreHU/android_device_alps_ac8257_demo/tree/lineage-16.0) | ROM LineageOS 16.0 (Android 9) de l'UJC201 : systeme LineageOS + vendor stock + applis LibreHU (en cours) |

## Changelog récent

### 2026-10-12
- Mise à jour du noyau précompilé vers le noyau stock UJC201-V1.151R6-260122_0427-RH-C0-CYA, Linux 4.9.117+ #72, avec le patch `skip_initramfs` → `want_initramfs` ; la zone DTB ajoutée au flux gzip est conservée.
- Mise à jour de `prebuilt/dtbo.img` depuis le `recovery_dtbo` du nouveau `recovery.img`.
- Mise à jour du contenu de `prebuilt/avb/recovery_stock_vbmeta_250718.bin` avec le VBMeta extrait du nouveau recovery stock ; le nom de fichier historique est conservé. L'empreinte de la clé publique reste `0aa0987116fc792f36bc909b0a4d530413f02a54`.
- Ajout de l'entrée `System Image` dans `recovery.fstab` pour les sauvegardes/restaurations brutes de la partition `system`, en conservant l'entrée de sauvegarde au niveau des fichiers.
- Ajout d'un correctif dans `tools/apply_twrp_patches.py` : si la fstab par défaut ne contient pas `/misc`, le code AOSP `bootloader_message` utilise `/dev/block/platform/bootdevice/by-name/para`, où cet appareil stocke le BCB (`boot-recovery --wipe_data`). Ce correctif vise à éviter de rester bloqué dans TWRP après une réinitialisation d'usine ; il doit être confirmé par le build et un test sur l'appareil.


| Fonction | Etat |
|---|---|
| Demarrage sans bootloop d'Android | OK (signature AVB du recovery stock) |
| Affichage | OK, paysage (rotation 90) |
| Tactile + touches du bandeau (power, home, back, vol+, vol-) | OK (`touchfix`) |
| Luminosite | OK (pilote inverse, corrige par `touchfix`) |
| ADB / MTP | OK (configfs, `musb-hdrc`) |
| Cle USB | OK sur le port hote (xhci) ; port OTG basculable (Advanced > USB: Host mode) |
| /data | OK (non chiffre sur ce firmware) |
| Barre d'etat | temperature CPU (mtktscpu) + tension d'entree (2 sondes ADC, a valider en voiture) |
| MCU Jancar (ttyS1) | ACC, frein a main, feux (barre d'etat a droite), version MCU (Advanced > MCU info), fenetre « feux allumes », touches au volant, horloge synchronisee sur le MCU |
| Navigation aux touches | TWRP entier au volant / clavier USB : cadre sur l'element actif, listes, clavier a l'ecran, glissieres (**a tester**) |

## Installer
```
adb reboot bootloader
fastboot flash recovery twrp_ujc201.img
fastboot oem reboot-recovery
```
Retour au recovery stock : `fastboot flash recovery <recovery stock>.img`.

**Verifier ce qui est flashe** : TWRP affiche sa version au demarrage (`3.7.1_12-UJC201-b<build>-<commit>`,
builds a partir de la 11) ; depuis Android en root, `getprop` ne voit pas le recovery, mais l'empreinte de la
partition doit etre celle de l'image (meme taille, 32 Mio) :
`su -c "sha256sum /dev/block/platform/bootdevice/by-name/recovery"` = sha256 affiche par la release. Dans TWRP :
`getprop ro.librehu.twrp`. Les builds de la CI sont des pre-releases ; le titre donne la branche construite.
Faire d'abord une sauvegarde complete de l'eMMC (SP Flash Tool, onglet Readback, une ligne par zone) :

| Nom | Region | Adresse | Longueur | Contenu |
|---|---|---|---|---|
| `ROM_0` | `EMMC_BOOT_1` | 0x0 | 0x400000 | preloader |
| `ROM_1` | `EMMC_USER` | 0x0 | 0x1A0000000 | pgpt -> cache (tout sauf userdata) |
| `ROM_2` | `EMMC_USER` | 0x1A0000000 | 0x1B7A000000 | userdata (optionnel, tres gros) |
| `ROM_3` | `EMMC_BOOT_2` | 0x0 | 0x400000 | 2e zone de boot (souvent vide) |
| `ROM_4` | `EMMC_USER` | 0x1D1A000000 | 0x4000000 | fin de disque (otp, flashinfo, sgpt) |

Adresses du scatter `MT6761_Android_scatter.txt` de l'appareil.

**Flasher `twrp_ujc201.img` (post-traite), jamais le `recovery.img` brut du build.**
Depuis Android (root), l'onglet Zips de LibreHU Apps peut aussi l'ecrire dans `recovery` (zip `twrp-ujc201` de
[LibreHU-flashablesZips](https://github.com/LibreHU/LibreHU-flashablesZips) : derniere release, taille et SHA-256
verifies, recovery actuel sauvegarde dans `/sdcard/LibreHU/backup`).

## Build
GitHub Actions (`.github/workflows/build-twrp.yml`, lancement manuel) :
1. `repo sync` du manifeste minimal twrp-12.1 ;
2. `tools/apply_twrp_patches.py` patche le **source** TWRP (barre d'etat texte, theme, fenetres, navigation aux touches) ;
3. build `recoveryimage` avec les flags de `BoardConfig.mk` (pas de FBIOBLANK, luminosite, rotation…) ;
4. `tools/ujc201_postprocess.py` pose la signature AVB du recovery stock (et applique en binaire ce qui
   manquerait) → **`twrp_ujc201.img`**, publie en pre-release.

Dans le log de l'etape « Post-process », verifier :
`barre d'etat texte : deja geree par le source` et `FBIOBLANK neutralises : 0` (normal : l'ioctl n'est plus compile).

Localement, a partir d'un `recovery.img` deja construit :
```
python3 tools/ujc201_postprocess.py recovery.img twrp_ujc201.img \
    --avb prebuilt/avb/recovery_stock_vbmeta_250718.bin --overlay recovery/root
```

### Compiler from scratch
Memes etapes que la CI, sur un PC Linux x86-64 avec environ 60 Go libres et 16 Go de RAM (ou de la swap : la CI en
ajoute 12 Go).

| Ubuntu | Etat |
|---|---|
| **24.04 LTS** | **conseille** : c'est le runner de la CI (`ubuntu-24.04`), build complet verifie a chaque run |
| 22.04 LTS | memes paquets |
| **26.04 LTS** | paquets verifies (installation simulee dans un conteneur 26.04 propre, 21/10/2026) : `liblz4-tool` et `libxml2` n'existent plus sous ces noms (remplaces par `lz4`, et `libxml2` vient avec `libxml2-utils`), d'ou la liste ci-dessous valable pour les trois versions. Build complet **pas encore teste** sur 26.04 (Python 3.14, GCC 15) : en cas d'erreur des scripts AOSP 12, compiler dans un conteneur 24.04 (`distrobox create -i ubuntu:24.04`, ou `docker run -it -v ~/twrp:/twrp ubuntu:24.04`) |

```bash
# 1. Outils (meme liste pour Ubuntu 22.04, 24.04 et 26.04)
sudo apt install gperf gcc-multilib g++-multilib libc6-dev lib32ncurses-dev x11proto-core-dev libx11-dev \
  lib32z-dev libgl1-mesa-dev libxml2-utils xsltproc bc ccache lib32readline-dev lib32z1-dev lz4 \
  libncurses-dev libsdl1.2-dev build-essential git lzop pngcrush schedtool squashfs-tools imagemagick \
  libbz2-dev lzma ncftp python3 tar openjdk-11-jdk curl
mkdir -p ~/bin && curl -o ~/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod a+x ~/bin/repo
export PATH=~/bin:$PATH

# 2. Sources TWRP (manifeste minimal twrp-12.1) et cet arbre
mkdir -p ~/twrp && cd ~/twrp
repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp -b twrp-12.1
repo sync -j"$(nproc)" --force-sync --no-clone-bundle --no-tags
git clone -b twrp https://github.com/LibreHU/android_device_alps_ac8257_demo device/alps/ac8257_demo

# 3. Patchs du source TWRP (barre d'etat texte, theme)
python3 device/alps/ac8257_demo/tools/apply_twrp_patches.py bootable/recovery

# 4. Build
source build/envsetup.sh
export ALLOW_MISSING_DEPENDENCIES=true
lunch twrp_ac8257_demo-eng
make recoveryimage -j"$(nproc)"

# 5. Post-traitement : signature AVB du recovery stock (sans elle : bootloop), ecran, theme
D=device/alps/ac8257_demo; OUT=out/target/product/ac8257_demo
python3 $D/tools/ujc201_postprocess.py $OUT/recovery.img $OUT/twrp_ujc201.img \
    --avb $D/prebuilt/avb/recovery_stock_vbmeta_250718.bin --overlay $D/recovery/root
```
Flasher **`twrp_ujc201.img`** (jamais `recovery.img` brut : ecran noir) comme indique dans *Installer*.

## Ce qu'on a appris (pieges de cette plateforme)

### 1. AVB : ne pas signer le recovery avec une cle de test
Le `vbmeta` stock chaine `recovery` (cle Jancar, rollback location 1). Avec une autre cle :
- le LK tolere (bootloader deverrouille) ;
- mais le **fs_mgr d'Android 9** refait `avb_slot_verify` au premier etage de `init` et ne tolere que
  `ERROR_VERIFICATION`, pas `PUBLIC_KEY_REJECTED` (result 5) → `Failed to mount required partitions early`
  → kernel panic → **bootloop d'Android** (visible dans la partition `expdb`).

Solution : `BOARD_AVB_ENABLE := false` et le post-traitement pose le **vbmeta du recovery stock** en footer
(`prebuilt/avb/`) : cle correcte, seul le hash differe → erreur de verification toleree.

### 2. Noyau : `skip_initramfs`
Le LK ajoute `skip_initramfs ro rootwait init=/init` hors mode recovery (system-as-root).
Le noyau prebuilt est patche `skip_initramfs` → `want_initramfs` (meme methode que Magisk).
`fastboot boot` ne permet pas de demarrer TWRP sur cette unite : il faut flasher `recovery`.

### 3. Ecran noir : jamais de FBIOBLANK
Au demarrage, minui fait `FBIOBLANK` (eteindre) puis `FBIOBLANK` (rallumer). Le pilote LCM Jancar lance a
l'extinction un kthread `jac_set_lcd_power_kthread` qui coupe l'alimentation de la dalle (GPIO 170/164)
~100 ms plus tard, donc **apres** le rallumage → dalle eteinte, retro-eclairage allume, `VSYNC timeout`.
`TW_SCREEN_BLANK_ON_BOOT` est proscrit et le post-traitement neutralise les `ioctl(FBIOBLANK)` de
`libminuitwrp.so`. La dalle est une MIPI 720x1280 (portrait) derriere un pont LVDS ; Android utilise
`persist.sf.hwrotation=90`.

### 4. Tactile (`tools/touchfix`)
`mtk-tpd` (Goodix, id 0911) annonce 720x1280 mais envoie des coordonnees paysage ~1024x600, X inverse
(X ≈ 1008 a gauche, 13 a droite ; Y 14 en haut, 590 en bas). Il ne remonte rien tant qu'il n'a pas recu
la notification « ecran allume » (ecriture de `0` dans `/sys/class/graphics/fb0/blank`, sans eteindre).
`touchfix` capture `mtk-tpd` (EVIOCGRAB) et reemet sur un peripherique uinput. TWRP (`ev_get`) met l'axe X a
l'echelle de la largeur affichee apres rotation : pas d'echange X/Y, seulement l'inversion de X.
Le bandeau gauche (X brut > 1030) porte les touches : power Y≈108, home 189, back 271, vol+ 355, vol- 430.

### 5. Luminosite
`/sys/class/leds/lcd-backlight` : `max_brightness = 0`, `min_brightness = 179` → echelle inversee.
TWRP ecrit dans `/tmp/twbl` (`TW_BRIGHTNESS_PATH`), `touchfix` convertit (`179 - v*179/255`).

### 6. USB
- Port OTG : `musb-hdrc` (seul UDC). Le gadget est en **configfs** : l'`init.recovery.usb.rc` legacy
  (`android_usb`) de TWRP ne marche pas → `recovery/root/init.recovery.usb.rc` (mtp.gs0 + ffs.adb).
- Bascule hote/peripherique : `dual_role_usb/dual-role-usb20/data_role` = `host` / `device`
  (`mode` ufp/dfp est ignore par le pilote MTK, `cmode` aussi). Script `usbmode`.
- Second port : `xhci-mtk` (11280000.usb), **hote uniquement** → adb impossible dessus, cle USB OK.

### 7. Sondes
- Temperature CPU : `thermal_zone1` (`mtktscpu`). `thermal_zone0` = `mtktsbattery` = -127000 (pas de batterie).
- Pas de `power_supply` (`ATC_DISABLE_BATTERY_CHARGER`). Tension d'entree : ADC SoC canal 4
  (`/sys/devices/virtual/mtk-adc-cali/mtk-adc-cali/AUXADC_read_channel`, 902 mV a 12,02 V, x13,33) et
  PMIC `VCDT` (`iio:device0/in_voltage2_VCDT_input`, 649 mV, x18,52). Les deux suivent une chute sous charge ;
  rapports a confirmer entre 12,5 V et 14 V.

## Menu de demarrage (optionnel) : TWRP / Android / Fastboot
`tools/bootmenu/` : `/init` autonome place dans le ramdisk du **boot** (pas du recovery). A chaque demarrage,
3 cartes (style Material, couleurs TWRP), Android demarre seul apres 3 s ; toucher l'ecran met en pause
(Android au bout d'une minute sans action). Touches du bandeau : HOME = Android, BACK = TWRP.

![bootmenu](tools/bootmenu/preview/bootmenu.png)

- TWRP / Fastboot : `reboot(RESTART2, "recovery" | "bootloader")`, comme `adb reboot recovery`.
- Android : monte `system` (PARTNAME=system) en lecture seule, bascule la racine dessus et lance son `/init`
  (methode magiskinit pour le system-as-root « legacy »). Le noyau du boot est patche `want_initramfs`.
- Partition boot = 10 Mo, noyau ~10,3 Mo : le ramdisk doit rester sous ~190 Ko (actuellement ~65 Ko).

```
python3 tools/bootmenu/gen_ui.py 3        # interface (3 s de delai) -> ui_data.h + preview/
tools/bootmenu/build.sh                   # -> tools/bootmenu/bootmenu
python3 tools/bootmenu/mkboot.py <dump boot stock>.img boot_bootmenu.img
```
Tester d'abord dans TWRP sans rien flasher (`bootmenu --test`, voir ci-dessous), puis
`fastboot flash boot boot_bootmenu.img`. Retour : `fastboot flash boot <dump boot stock>.img`.
Test sous qemu sans materiel : `qemu-aarch64 tools/bootmenu/bootmenu --dump out.raw <carte|-1> <message> <progression%>`.

### 8. MCU Jancar
Port `/dev/ttyS1` 115200 8N1, protocole « JAC_V1 » (appli `com.jancar.services`) :
trame `EE FA <len = donnees+1> <cmd> <donnees> <somme des octets precedents>`.
`touchfix` envoie `1F 01` (PC_READY, comme Android au demarrage ; pas de battement de coeur sur AC8257) et `F0 00 00`
(etat ACC), puis lit `00` ACC, `04` frein a main, `0B` feux, `1F` etat groupe (b6 frein, b4 feux), `0A` version.
Etat ecrit dans `/tmp/twcar` (affiche par `%tw_ujc201_car%`), `/tmp/twcar_s`, `/tmp/mcu_version` et `/tmp/ujc201/<nom>`
(page graphique Advanced > *Vehicle / MCU dashboard* et zone droite de la barre : proprietes systeme `ujc201.<nom>`, lues par le theme avec `%property.ujc201.<nom>%`, sans patch du binaire TWRP). Requete frein a main au demarrage : `F0 04 00`.
Les entrees Advanced passent par `terminalcommand` : la sortie des scripts s'affiche dans la console (l'action `cmd` n'affiche rien).
LED des touches : commande `0F 04 <panneau> R G B <mode>` (R,G,B 0..99 ; mode 1 auto, 2 manuel, 3 semi-auto ;
en manuel/semi-auto, allumees seulement feux allumes).

**Fenetres** (`gui/pages.cpp` patche, dessinees par-dessus toutes les pages, au-dessus de la barre de navigation) :
`touchfix` ecrit `/tmp/twpopup`, une ligne par fenetre `<W|K|I>\t<titre>\t<texte>`.
- feux allumes : 8 s a l'allumage ; permanente si feux allumes **et** contact (ACC) coupe ;
- touche au volant : nom + action, 1,5 s apres le relachement ;
- invite de `wheelkeys learn`.
Binaire TWRP sans ce patch : bandeau du theme sur la barre de navigation (proprietes `ujc201.pop_k/pop_t/pop_x`, une fenetre a la fois : invite > touche > avertissement).

**Horloge** : trames `09` (date `[0, aa/100, aa%100, mois, jour]`, heure `[1, h, m, s]`, heure locale) ->
`/tmp/mcu_time`. TWRP patche convertit avec `mktime()` dans son fuseau (Settings > Time zone) et regle l'horloge
si l'ecart depasse 2 s (refait si le fuseau change). Sans le patch, `touchfix` corrige seulement la derive en gardant
le decalage horaire existant (arrondi au 1/4 d'heure).

**Touches au volant** : trame `20` = `canal v1 v2 v3 v4` (1 telecommande IR, 2 molette, 3/4 touches AD, 5/6 volant ;
`FF` = relachement). **Boitier CAN** (Hiworld, Renault LNP002 : Clio 3…) : ses octets arrivent dans les trames `10`,
`touchfix` y retrouve les messages `5A A5 LEN CMD .. CS` et la touche du message `11` (D1 bit 3, D2 = code, D3 = 1 a
l'appui) ; elle passe par le **canal 7** (`v1` = code). Sans ligne apprise, table LNP002 par defaut (VOL+ / VOL-,
MUTE / OK = appui, PREV / NEXT = haut / bas, gauche / droite, MODE = retour, NAVI = accueil). La vitesse du boitier
est celle du MCU (`0F 00`, 38400 par defaut) : a verifier sur une voiture dont le boitier en utilise une autre. `touchfix` les envoie sur le peripherique uinput `ujc201-wheel` selon la table
`ujc201_keys.conf` (`/data/media/0/TWRP/`, sinon `/tmp/`, sinon `/system/etc/` vide) :
`<canal> <octet 1..4> <min> <max> <action> [nom]`, actions `volup voldown enter back home power up down left right bl+ bl- none`.
Apprentissage : Advanced > *Steering wheel keys: learn* (`wheelkeys learn`, VOL+ VOL- MUTE MODE BACK PREV NEXT,
10 s par touche, sautee sinon).

**Navigation aux touches** (`tools/keynav/keynav.inc`, insere dans `gui/pages.cpp` par `apply_twrp_patches.py`) :
TWRP se pilote entierement au volant (ou avec un clavier USB). Un cadre jaune montre l'element actif ; il apparait a
la premiere touche et disparait au premier toucher de l'ecran.

| Touche (table apprise) | Action |
|---|---|
| VOL- / VOL+ (`voldown` / `volup`) | element suivant / precedent, dans l'ordre de lecture |
| PREV / NEXT, molette (`up` / `down`), fleches | element au-dessus / au-dessous (`left` / `right` : a gauche / a droite) |
| MUTE (`enter`) | appui sur l'element ; glissiere « Swipe to... » : **deux fois** en 4 s (cadre orange entre les deux) |
| BACK (`back`) / MODE (`home`) | page precedente / menu principal (comme avant) |

Dans une liste (fichiers, partitions, options) les touches changent de ligne et en sortent aux extremites ;
`left` / `right` avancent d'une page. Texte et console defilent. Curseurs (luminosite...) : `left` / `right`. Clavier
a l'ecran : chaque touche est un element, `enter` la tape (nom de sauvegarde, dossier). L'element actif de chaque page
est retenu. `power` = verrouillage, `bl+`/`bl-` = luminosite.

## Correctif build.prop (zip TWRP, optionnel)
Le firmware annonce `ro.build.version.release=12` (SDK 28 = Android 9) et le fingerprint d'une autre plateforme
(`evb3561sv`, Android 6.0) dans `/system/build.prop`. `tools/buildprop_fix/build.sh` construit deux zips TWRP :
- `ujc201_buildprop_fix.zip` : reprend release / fingerprint / description du fingerprint vendor
  (`alps/full_UJC201_64/ac8257_demo:9/PPR1.180610.011/1356:user/release-keys`) ; sauvegarde `build.prop.bak` a cote
  et copie dans `/sdcard/UJC201_buildprop_backup/<date>/` ;
  neutralise aussi la fausse version du framework Jancar (`ActivityThread.bindApplication` : « 12 » dans les
  Reglages Android tant que `persist.jancar.ver_rel` est vide, SDK 31 pour AnTuTu / Geekbench / AIDA64 via
  `persist.jancar.sdk`) : `persist.jancar.ver_rel=9` et `persist.jancar.sdk=28` dans `build.prop` (apres un reset)
  et `/system/etc/init/ujc201_version.rc` (reimpose a chaque demarrage) ;
- `ujc201_buildprop_restore.zip` : remet l'original (`.bak`, sinon la derniere copie de `/sdcard`).

## Fichiers
- `prebuilt/kernel` : noyau stock de la mise a jour Jancar de janvier 2026 (#72, 22/01/2026) + patch `want_initramfs`
  (avant : 250718, #25)
- `prebuilt/dtbo.img` : recovery_dtbo du recovery stock de la mise a jour 2026
- `prebuilt/avb/recovery_stock_vbmeta_250718.bin` : vbmeta (footer) du recovery stock 2026 (nom historique conserve)
- `recovery/root/` : rc, `touchfix`, `usbmode`, `powerinfo`, `mcuinfo`, `wheelkeys`, `ujc201_keys.conf`
- `tools/touchfix/` : source de `touchfix` (C autonome, sans libc) + `build.sh`
- `tools/apply_twrp_patches.py` : patchs du source TWRP (applique par le workflow)
- `tools/keynav/keynav.inc` : navigation aux touches (touches au volant, clavier), inseree dans `gui/pages.cpp`
- `tools/buildprop_fix/` : zips TWRP correctif / restauration du build.prop
- `tools/ujc201_theme.py` : entrees Advanced + page graphique (partage source / post-traitement)
- `tools/ujc201_postprocess.py` : post-traitement de l'image (signature AVB, patchs binaires de secours)
- `tools/bootmenu/` : menu de demarrage (source C, generateur d'interface, polices Roboto Apache 2.0, `mkboot.py`)

## Ailleurs
Ce depot ne contient que l'arbre TWRP. Le reste a ete deplace le 19/10/2026 :
- noyau, sources GPL Autochips, tester un noyau (footer AVB du boot, `para`, RAM), notes de la ROM stock (audio,
  video, CarPlay / Android Auto, Ethernet, reglages caches, /system en ecriture, zips audio, applis LibreHU) et
  outils (`usbnet`, `audio`, `dump`) : [android_kernel_autochips_ac8257_4.9, branche `reverse-engineering`](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9/tree/reverse-engineering)
  (`docs/ujc201/`, `tools/ac8257/`) ; noyau de travail sur les sources GPL Autochips : branche
  [`LibreHU-main`](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9/tree/LibreHU-main) ;
- firmware et protocole du MCU, outils `tools/mcu/`, appli JacMCU : [MCU-tools-app](https://github.com/LibreHU/MCU-tools-app) ;
- zips prets a flasher : [LibreHU-flashablesZips](https://github.com/LibreHU/LibreHU-flashablesZips).

## Securite
Ne jamais restaurer la partition « Preloader » depuis TWRP. Garder le recovery stock pour les mises a jour.
Ne pas publier ses propres partitions `nvram`, `nvdata`, `proinfo`, `persist`, `metazone` (identifiants,
certificat CarPlay).
