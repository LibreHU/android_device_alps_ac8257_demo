# Installer LineageOS 16.0 sur l'UJC201

[English](INSTALL.en.md) · Page du site : <https://librehu.github.io/lineageos.html>

Une vraie ROM construite depuis les sources de LineageOS (Android 9), pas une GSI : applis LibreHU integrees, noyau
LibreHU, partition vendor de **votre** autoradio (jamais publiee). **Builds de test** : elle demarre depuis le
12/11/2026, plusieurs choses sont encore en cours de correction (voir [Problemes connus](#problemes-connus)).

Uniquement pour le **Jancar UJC201** (Autochips AC8257, produit `ac8257_demo`, ecran 1280 x 720). Les autres
autoradios AC8257 ont un autre noyau, un autre device tree ou un autre ecran : ne l'installez pas dessus.

> **Builds userdebug** : adb repond sans autorisation et `adb root` est permis (toute personne branchee sur le port
> USB obtient un shell root) ; SELinux est permissif pendant la mise au point. Les zips sont signes avec la cle de
> test d'AOSP, comme la ROM.

## 1. Telecharger

Chaque build de la CI (branche `lineage-16.0`) est publie dans les
[releases du depot](https://github.com/LibreHU/android_device_alps_ac8257_demo/releases) (`lineage-16.0-<date>-<arbre>`) :

| Fichier | Ce que c'est |
|---|---|
| `LibreHU-LineageOS-16.0-ac8257_demo-<date>-<arbre>.zip` | zip TWRP (system, boot, modules du noyau) : **celui a installer** |
| `system.img.zst` | image system pour fastboot (zstd : a decompresser avant de flasher) |
| `boot-librehu-bootmenu.img` / `boot-librehu.img` | image de boot avec / sans le menu de demarrage |
| `SHA256SUMS` | empreintes des fichiers |

Verifier le zip : `certutil -hashfile fichier.zip SHA256` (Windows), `sha256sum fichier.zip` (Linux / macOS).

## 2. Avant de commencer

1. **TWRP LibreHU** installe et fonctionnel (branche `twrp` de ce depot, tuto sur le site).
2. **Sauvegardes**, gardees hors de l'autoradio : sauvegarde TWRP de Boot, System Image et Vendor Image ; votre
   `vbmeta.img` d'origine (necessaire plus bas) ; idealement une lecture complete avec SP Flash Tool, avec `nvram`,
   `nvdata`, `protect1` / `protect2` (calibration et identifiants).
3. Un PC avec `adb` et `fastboot` (platform-tools d'Android), un cable USB, une cle USB ou une carte microSD, une
   alimentation stable (moteur tournant ou alimentation d'etabli).

## 3. vbmeta : pourquoi et comment

La partition `vbmeta` (demarrage verifie d'Android) contient les empreintes et les cles de `boot`, `dtbo` et
`vendor`, et un lien vers `system` signe avec la cle de Jancar ; le bootloader la verifie a chaque demarrage. Le
`system` de LineageOS n'est pas signe par Jancar : avec le vbmeta d'origine tel quel, **l'autoradio reste sur le logo
du constructeur**.

La solution : votre propre vbmeta d'origine avec la verification coupee, deux drapeaux de son en-tete (octet 123) :
`1` = dm-verity coupe (`--disable-verity`), `2` = verification coupee (`--disable-verification`). LineageOS a besoin
des **deux** (valeur 3) ; le stock demarre aussi avec ce vbmeta. Le zip n'ecrit jamais vbmeta : il verifie les
drapeaux et s'arrete sans rien ecrire tant que la verification est active.

Avec fastboot :

```
adb reboot bootloader
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot reboot
```

Sans fastboot (autoradio bloque sur le logo) : copie de vbmeta avec les deux drapeaux (PowerShell, dans le dossier de
la sauvegarde), puis SP Flash Tool, onglet *Download*, votre scatter, **Download Only**, uniquement `vbmeta` avec
`vbmeta-disabled.img`, et l'autoradio branche eteint :

```
$b = [IO.File]::ReadAllBytes("$PWD\vbmeta.img")
if ([Text.Encoding]::ASCII.GetString($b, 0, 4) -ne "AVB0") { throw "pas un vbmeta" }
$b[123] = $b[123] -bor 3
[IO.File]::WriteAllBytes("$PWD\vbmeta-disabled.img", $b)
```

> **Jamais** *Format All + Download* ni *Firmware Upgrade* (ils effacent `nvram` / `nvdata` : calibration, adresses
> MAC, identifiants). **Ne formatez jamais `/vendor`** (LineageOS tourne dessus). **Ne flashez jamais vbmeta sans les
> deux drapeaux** tant que LineageOS est installe.

## 4. Installer

1. Copier le zip (verifie) sur une **cle USB ou une carte microSD**, pas dans la memoire interne (Format Data
   l'efface).
2. Flasher vbmeta avec les deux drapeaux (section 3), puis `fastboot reboot`.
3. Menu de demarrage -> **TWRP** (ou `fastboot oem reboot-recovery`).
4. **Premiere installation seulement** (en venant du stock ou d'une autre ROM) : *Wipe -> Format Data*, taper `yes`.
5. *Install* -> le zip -> glisser. Il ecrit `system` (relu et verifie), `boot` et les modules Wi-Fi / Bluetooth / GPS
   / FM du noyau dans `/vendor/lib/modules` (originaux sauvegardes dans `/sdcard/LibreHU/backup`). Il garde le type
   d'image de boot installe (avec ou sans menu) ; `bootmenu` ou `plain` dans le nom du zip en impose un.
6. *Reboot -> System*. Le premier demarrage prend quelques minutes ; le menu de demarrage lance Android tout seul au
   bout de 3 secondes.

## 5. Premier demarrage

- Choisir **LibreHU Launcher** comme ecran d'accueil, *Toujours*.
- Installes tout seuls : gestionnaire KernelSU Next, Aurora Store, LibreHU Helper (applis ordinaires).
- **Toutes les applis LibreHU recoivent le root** de KernelSU sans le demander (tous les paquets `org.librehu.*` et
  ViPER4Android, a chaque demarrage) ; un choix fait ensuite dans le gestionnaire, refus
  compris, est garde.
- Calibration du tactile appliquee a chaque demarrage (`/jancar/config/pointercal*.xml`).
- Pays du Wi-Fi d'apres la langue choisie a l'installation (au demarrage suivant ; `CN` jusque-la).
- Dalle portrait 720 x 1280 tournee en paysage (90°). A l'envers : `adb root`,
  `adb shell setprop persist.librehu.display_rotation 270`, `adb reboot`.

## 6. Mises a jour

*Parametres -> Systeme -> Mises a jour* (appli de LineageOS) : elle lit le flux des builds publies (`updater.json` de
la release `lineage-16.0-ota`), telecharge le suivant, redemarre dans TWRP et l'installe (depuis le build du
13/11/2026). Jusqu'au build `96472d7` compris, l'installation dans TWRP echouait (« extraction du zip impossible » :
le zip lisait mal le block map d'uncrypt) ; corrige ensuite. A la main : le nouveau zip depuis TWRP, **sans** Format
Data.

## 7. Depannage

| Symptome | Que faire |
|---|---|
| Reste sur le logo du constructeur | vbmeta verifie encore : le flasher avec les deux drapeaux (section 3) |
| Le zip s'arrete sur « vbmeta : verification active » | pareil, puis le zip a nouveau (rien n'a ete ecrit) |
| Menu de demarrage, puis fastboot | l'init s'est arrete ; sans couper le courant : `fastboot oem reboot-recovery`, puis dans TWRP `adb pull /sys/fs/pstore` et envoyer le journal |
| Tactile hors de l'ecran | `adb logcat -s LibreHU-Touch` et `adb shell head -c 19 /proc/gt9xx_config` (identifiant de la dalle), a envoyer |
| Video verte (Android Auto, lecteurs) | corrige dans les builds d'apres le 13/11 (`1ec65bc` et avant : une veille, contact coupe puis remis, ramene l'image ; ou `adb root`, `adb shell chown system:system /dev/backcardrv`, `adb shell chmod 0660 /dev/backcardrv`, `adb shell stop backcar_daemon`, `adb shell start backcar_daemon`, puis redemarrer LibreHU-service) |
| Ecran noir retroeclaire, ou tactile mort apres une extinction de l'ecran | une souris USB ou `adb shell input keyevent 26` rallume l'ecran ; build `171f952` : `adb root`, `adb shell "echo 1 > /sys/module/mtk_tpd/parameters/sleep_on_blank"`, puis eteindre et rallumer l'ecran (a refaire a chaque demarrage, corrige dans le build suivant) ; installee avant le 13/11 : `adb shell locksettings set-disabled true` |
| Pas de son du tout (ampli muet) | corrige dans le build qui suit le 14/11 ; avant : `adb root`, `adb shell chmod 0666 /dev/gpios_ioctl`, puis dans LibreHU-service, onglet Audio, activer puis couper la sourdine (jusqu'au redemarrage) |
| Reseau Wi-Fi introuvable | choisir sa langue et sa region dans les Parametres, redemarrer |

Rapports : LibreHU Helper (installe avec la ROM). Il contient le numero de serie de l'autoradio : le partager en prive.

## 8. Retour au stock

TWRP -> *Restore* de la sauvegarde (Boot, System Image, Vendor Image), puis *Wipe -> Format Data* et redemarrage. Le
vbmeta aux deux drapeaux peut rester. Sans TWRP : la lecture SP Flash Tool, *Download Only*, partition par partition.

## Problemes connus

- Video decodee par le materiel verte jusqu'a la premiere veille (`1ec65bc` et avant) : l'ARM2 garde deux couches de
  l'affichage, le HAL `backcar` du vendor n'avait pas acces a `/dev/backcardrv` ; corrige dans le build suivant
  (confirme sur l'unite le 13/11).
- Corriges dans le build qui suit `96472d7` (noyau compris) : batterie vue a 0-1 % (le noyau donne une batterie pleine
  sur secteur), clavier virtuel masque (decodeur IR « clavier MCE » du noyau pris pour un clavier physique ; sur un
  build plus ancien : *Parametres -> Systeme -> Langues et saisie -> Clavier physique -> Afficher le clavier virtuel*),
  egaliseur AudioFX de LineageOS retire (en conflit avec ViPER4Android) ; appui long de la touche power de facade possible
  sur le menu power d'Android (LibreHU-service, onglet Dalle, action « Bouton power maintenu »). Rallumer l'unite
  verrouillee par cette touche : la dalle reste active ecran eteint ; le build `171f952` ne la resettait pas au
  rallumage (tactile mort) : corrige dans le build suivant.
- Aucun son, alors qu'Android joue et que LibreHU-service affiche la sourdine coupee (builds jusqu'au 14/11) : le
  noeud `/dev/gpios_ioctl` etait cree en 0600 root, le service ne pouvait pas couper la sourdine de l'ampli (GPIO 166) ;
  regle ueventd ajoutee (droits du stock), trouve et confirme sur l'unite par Reo Au In le 13/11.
- En cours d'analyse (14/11) : Parametres Bluetooth qui plantent, AV IN 1 et 2, routage audio. Streaming Bluetooth :
  la reconnexion automatique de LibreHU-service relancait sans fin un telephone injoignable (toutes les 40 s) ;
  corrige dans le service (`d0debeb`), test a refaire telephone a portee.
- Wi-Fi 5 GHz : l'unite voit le 5 GHz (canaux 36 a 44 et 157 dans un releve du 14/11). Une borne qui n'annonce son
  reseau en 5 GHz qu'en WPA2-Enterprise (EAP) n'est joignable avec un mot de passe qu'en 2,4 GHz : activer WPA2-PSK
  sur la radio 5 GHz de la borne.
- YouTube en VP9 1080p60 saccade : pareil sous le stock et dans Chrome, limite du decodeur materiel : mesure sur
  l'unite (codecbench, 13/11/2026), le VP9 materiel decode le 1080p a ~60 fps au plus (MediaTek annonce 23-79 fps),
  le VP9 logiciel a 61 fps, le H.264 materiel a 126 fps. Lire en 720p (definition de l'ecran), en 1080p30, ou en
  H.264 : extension enhanced-h264ify de Firefox, avec le 60 i/s autorise dans ses reglages ; veille de la voiture peu fiable ; le tactile peut ne pas se reveiller apres l'extinction de
  l'ecran ; service watermark d'Autochips absent (bruit dans les journaux).

La compiler soi-meme : [BUILD.md](BUILD.md).

## TL;DR

Telecharger le dernier zip des releases, flasher votre vbmeta d'origine avec `--disable-verity
--disable-verification`, puis dans TWRP : Format Data (premiere fois), le zip depuis une cle USB, redemarrer. Jamais
Format All dans SP Flash Tool, jamais de formatage de `/vendor`. Mises a jour ensuite par l'appli de LineageOS.
