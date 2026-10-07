# TWRP – Jancar UJC201 (Autochips AC8257, carte JAC_8258C)

Arbre TWRP (branche **twrp-12.1**) pour les autoradios Android « UJC201 » (SIXWIN, Podofo, Hikity…).
**Teste et fonctionnel** sur une unite SIXWIN, firmware `UJC201-V1.1.35R6-250718_0429` (noyau `4.9.117+ #25`).

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

## Installer
```
adb reboot bootloader
fastboot flash recovery twrp_ujc201.img
fastboot oem reboot-recovery
```
Retour au recovery stock : `fastboot flash recovery <recovery stock>.img`.
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

## Build
GitHub Actions (`.github/workflows/build-twrp.yml`, lancement manuel) :
1. `repo sync` du manifeste minimal twrp-12.1 ;
2. `tools/apply_twrp_patches.py` patche le **source** TWRP (barre d'etat texte, theme) ;
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
`FF` = relachement). `touchfix` les envoie sur le peripherique uinput `ujc201-wheel` selon la table
`ujc201_keys.conf` (`/data/media/0/TWRP/`, sinon `/tmp/`, sinon `/system/etc/` vide) :
`<canal> <octet 1..4> <min> <max> <action> [nom]`, actions `volup voldown enter back home power up down left right bl+ bl- none`.
Apprentissage : Advanced > *Steering wheel keys: learn* (`wheelkeys learn`, VOL+ VOL- MUTE MODE BACK, 10 s par touche).
TWRP n'a pas de navigation au clavier : `back` = page precedente, `home` = menu principal, `power` = verrouillage,
`enter` = valider un champ texte, `bl+`/`bl-` = luminosite ; `volup`/`voldown` ne font rien dans TWRP seul.

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
- `prebuilt/kernel` : noyau stock 250718 (#25) + patch `want_initramfs`
- `prebuilt/dtbo.img` : recovery_dtbo du recovery stock 250718
- `prebuilt/avb/recovery_stock_vbmeta_250718.bin` : vbmeta (footer) du recovery stock
- `recovery/root/` : rc, `touchfix`, `usbmode`, `powerinfo`, `mcuinfo`, `wheelkeys`, `ujc201_keys.conf`
- `tools/touchfix/` : source de `touchfix` (C autonome, sans libc) + `build.sh`
- `tools/apply_twrp_patches.py` : patchs du source TWRP (applique par le workflow)
- `tools/buildprop_fix/` : zips TWRP correctif / restauration du build.prop
- `tools/ujc201_theme.py` : entrees Advanced + page graphique (partage source / post-traitement)
- `tools/ujc201_postprocess.py` : post-traitement de l'image (signature AVB, patchs binaires de secours)
- `tools/mcu/` : analyse du firmware MCU (`mdis.py`, `ana*.py`) et `jacmcu.py` (trames, decodage de `/tmp/mcu.log`, moniteur serie)
- `apps/jacmcu/` : app Android JacMCU (etat, commandes, console MCU ; mode service Jancar ou root)
- `docs/mcu_firmware.md` : reference complete du MCU (brochage, alimentation, protocole, interfacage Android)
- `tools/bootmenu/` : menu de demarrage (source C, generateur d'interface, polices Roboto Apache 2.0, `mkboot.py`)

## Securite
Ne jamais restaurer la partition « Preloader » depuis TWRP. Garder le recovery stock pour les mises a jour.
Ne pas publier ses propres partitions `nvram`, `nvdata`, `proinfo`, `persist`, `metazone` (identifiants,
certificat CarPlay).
