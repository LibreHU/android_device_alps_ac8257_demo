# LibreHU : fichier de passation (handoff)

> État au **24/10/2026**. Écrit pour qu'une nouvelle session Claude (autre compte, autre conteneur) reprenne le
> projet sans rien perdre. **Lis tout avant d'agir.** Les sections 1 et 2 sont des règles, pas des suggestions.
> Ce fichier vit sur la branche `ccr-eca2d7b0-vz26un` de `Dok-T/android_device_alps_ac8257_demo` (alias
> `LibreHU/android_device_alps_ac8257_demo`). Mets-le à jour à la fin de chaque session (section 10 et 11).

---

## 0. Démarrage d'une session

1. Sur claude.ai/code, démarrer la session en cochant les dépôts nécessaires (voir section 4) : une session ne voit
   que ceux choisis au départ. Les dépôts publics de tiers (ex. `cedricp/ddt4all`) se lisent en clonage anonyme.
2. Le conteneur est **vide** : pas de SDK Android, pas de clé de signature, pas des clones précédents. Les APK et
   images sont **construits et signés par les CI GitHub** : on peut travailler sans rien compiler localement, mais
   avant de pousser du Kotlin il vaut mieux compiler (section 6).
3. Répondre **en français**. Toujours finir une explication par un **TL;DR**.
4. Une seule session à la fois par branche. Pas deux comptes qui poussent sur la même branche en même temps.

---

## 1. Règles de l'utilisateur (verbatim ou presque)

- « Vérifie toujours les infos que je dis, et les infos que tu me donnes en allant chercher les sources sur internet
  et en citant les sources. Soit optimiste mais pas irréaliste. Ajoute toujours un tldr en fin d'explication. »
- Toujours mettre à jour la doc et les README des dépôts touchés.
- Suivre les demandes exactement, **pas d'extras non demandés**.
- « Discute en avec moi avant de faire quoi que ce soit » : pour les constats d'audit, proposer avant de modifier.
- « **JE NE VEUX PAS DE GSI OU TREBLE ! JE VEUX UNE VRAIE ROM** » (branche LineageOS = ROM complète pour l'appareil).
- « Fait le plus simple en premier, push et continue jusqu'au plus compliqué » (ordre de travail préféré).
- « Continue mais rapidement » : l'utilisateur veut des sessions efficaces, peu de bavardage.
- **MCU Toolkit** (`com.dokt.jacmcu`) : « Osef de MCU toolkit » : ne pas l'optimiser ni le modifier pour R8.
- **LEDs MCU** : « Ne fait pas maintenant les LEDs MCU, garde le en mémoire » : en attente (voir section 11).
  Une refonte a quand même été poussée juste avant ce message (service `6a1bb98`) : ne pas la retravailler ni
  l'annuler sans demande.

---

## 2. Contraintes de sécurité et de publication (ne jamais transgresser)

- **Jamais** désactiver dm-verity ni écrire `vbmeta` automatiquement. L'utilisateur le fait lui-même :
  `fastboot --disable-verity flash vbmeta vbmeta.img`.
- Ne jamais publier : `nvram`, `nvdata`, `proinfo`, `persist`, `metazone` (données propres à l'unité).
- `vendor.img` et blobs propriétaires : **non publiés**. LineageOS utilise `extract-files.sh` ; pas de branche de blobs.
- Ne pas committer de keystore dans un dépôt public (le classifieur le bloque : ne pas contourner). La clé de
  signature LibreHU est dans les secrets CI (`LIBREHU_KEYSTORE_B64` + mot de passe / alias via variables
  `LIBREHU_KEYSTORE`, `LIBREHU_KEYSTORE_PASSWORD`, `LIBREHU_KEY_ALIAS`).
- `PHONE_INFO` (infos du téléphone) ne va **qu'à** `org.librehu.service`.
- Ne pas exécuter de code issu du paquet GPL Jancar téléchargé ; ne pas contourner « Merge Without Review ».
- Pas de coordonnées GPS dans la doc.
- Refuser le contournement CSS des DVD (appli Disc : DVD → VLC, pas de déchiffrement fourni).
- France : les **avertisseurs de radars sont illégaux** (R413-15) : seulement l'alerte de **limite de vitesse** (OSM).
- Trailers obligatoires dans **chaque** commit :
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: <URL de la session en cours>
  ```
  (ancienne session : `https://claude.ai/code/session_011cBHDDd5gMBpcC8eHigZCi` ; une nouvelle session met la sienne).
- Aucun identifiant de modèle dans les commits, README, code (sauf ces trailers).
- Pas de pull request sans demande explicite. Pousser seulement sur la branche convenue.

---

## 3. Le matériel : Jancar UJC201 (AC8257)

| Élément | Valeur |
|---|---|
| Autoradio | Jancar **UJC201**, carte **JAC_8258C**, vendu sous plusieurs marques (SIXWIN, Podofo, Hikity…) ; unité de l'utilisateur : SIXWIN 6 Go + 128 Go |
| Voiture de l'utilisateur | **Renault Clio 3**, boîtier CAN **Hiworld** (protocole Renault **LNP002**) |
| SoC | Autochips **AC8257** (famille MediaTek MT6765/MT8768), `ro.product.device=ac8257_demo` |
| CPU | 8 × Cortex-A53, arm64-v8a ; `dalvik.vm.isa.arm64.variant=cortex-a53` |
| GPU | PowerVR « rgx » (clark m1.9ED4971894), OpenGL ES 3.2, `libPVROCL.so` présent ; **pas de pilote Vulkan** vendor |
| Android | **Android 9 (SDK 28)** ; `ro.build.version.release=12` est **falsifié** par Jancar |
| ROM stock | `UJC201-V1.151R6-260122_0427-RH-C0-CYA` (MAJ officielle janvier 2026) ; ancienne `V1.1.35R6-250718` |
| Noyau stock | Linux **4.9.117+ #72** (22/01/2026) ; #25 sur l'ancienne ROM |
| Mémoire | zram 1 Go ; PowerHAL MTK `vendor.mediatek.hardware.power@2.0` |
| MCU | STM32 (firmware Jancar 2024.08.09), sur `/dev/ttyS1` 115200, protocole **JAC_V1** (section 7.2) |
| Écran | dalle 720×1280 montée en paysage (TWRP : `persist.twrp.rotation=90`) |
| Tactile | GT928 et autres (doc `docs/TOUCH.md` du dépôt noyau), touches tactiles hors LCD (`/jancar/config/touch_key.xml`) |
| Partitions utiles | `recovery` = 32 Mio exactement ; BCB (message bootloader) sur `para` (pas de `/misc`) ; `boot` system-as-root (`skip_initramfs`) |
| AVB | `vbmeta` stock chaîne `recovery` (clé Jancar, rollback location 1) : TWRP reçoit le **footer vbmeta du recovery stock** (sinon bootloop) |
| `fastboot boot` | **ne marche pas** sur cette unité : il faut flasher `recovery` |
| Service stock | `ivi-services` (Jancar) ; `com.jancar.canservice` gère le boîtier CAN |
| `ro.zygote.preload.enable` | 0 dans la ROM Jancar (propriété non AOSP) ; interrupteur dans LibreHU-service → Tweaks (module root `system.prop`) |
| `flash_recovery` | **commenté** dans `/system/init.rc` : Android ne réécrit **pas** `recovery` au démarrage (vérifié dans le dump) |

---

## 4. Carte des dépôts

Organisation GitHub **LibreHU** (et compte personnel **Dok-T**, dont certains dépôts sont des alias / anciens noms).
Attention : selon le dépôt, l'outil GitHub MCP accepte `Dok-T/...` ou `LibreHU/...` (ex. le dépôt de l'appareil
répond sous `Dok-T/android_device_alps_ac8257_demo`, le fork Open Headunit sous `Dok-T/librehu-open-headunit-app`).

| Dépôt | Rôle | Branches | Package | Notes |
|---|---|---|---|---|
| `android_device_alps_ac8257_demo` | arbre **TWRP** (branche `twrp`, défaut), **LineageOS 16** (`lineage-16.0`), travail Claude (`ccr-eca2d7b0-vz26un`) | twrp, lineage-16.0, ccr-eca2d7b0-vz26un | — | CI `build-twrp.yml` → releases `twrp-build-<n>` |
| `android_kernel_autochips_ac8257_4.9` | noyau GPL Autochips + ajouts LibreHU, docs de l'unité (`docs/ujc201/`), outils (`tools/ac8257/`) | `LibreHU-main` (testée), `connectivity-builtin` (WMT/WLAN/BT/GPS/FM intégrés), `autochips-gpl` (source Jancar), `reverse-engineering` | — | releases `latest-LibreHU-main` ; KernelSU Next |
| `LibreHU-service` | **cœur** : MCU, audio (BD37534), CAN, OBD, veille, tactile, caméra de recul, pont téléphone, Tweaks, API AIDL | main | `org.librehu.service` | **API 8** (`LibreHu.API_VERSION`) |
| `LibreHU-Launcher-App` | launcher (pages, widgets, OBD plein écran, météo, alerte vitesse, horloge de veille, écran de verrouillage) | **main** + éditions `librehu-service` et `ivi` | `org.librehu.launcher` | toujours committer sur `main` puis **merger main → librehu-service et ivi** et pousser les 3 |
| `LibreHU-OTA-app` (« LibreHU Apps ») | magasin / MAJ des applis, zips TWRP, install /system | main | `org.librehu.ota` | catalogue `data/Catalog.kt` |
| `LibreHU-dialer-app` | téléphone BT, T9, widgets | main, librehu-service, ivi | `org.librehu.dialer` | **pas de gradlew** : utiliser celui de l'OTA (`-p`) |
| `LibreHU-FM-app` | radio FM (natif armeabi-v7a imposé par le pilote) | main, librehu-service, ivi | `org.librehu.fm` | 17 méthodes natives gardées par R8 |
| `LibreHU-widget-app` | widgets | main, … | `org.librehu.widgets` | |
| `LibreHU-BtnRemap-app` (« LibreHU Touches ») | remappage des touches, combinaisons, test | main, … | `org.librehu.btnremap` | « claims » des touches CAN au service |
| `LibreHU-EasySource-app` | sélecteur de source | main | `org.librehu.easysource` | |
| `LibreHU-disc-app` | lecteur CD/DVD USB, rip FLAC/WAV, MusicBrainz | main | `org.librehu.disc` | 11 natives arm64 |
| `LibreHU-bridge-app` | **appli téléphone** (QR / BT, canal chiffré, Android Auto Car App Library IoT) | main | (téléphone) | APK publié `LibreHU-Bridge-main.apk` |
| `LibreHU-xcertplay-app` | fork CarPlay (xcertplay) | **`librehu` (travail) → pousser aussi sur `master`** (lu par LibreHU Apps) | `org.librehu.carplay` | `git push origin librehu:master` |
| `librehu-open-headunit-app` (Dok-T) | fork Android Auto (Open Headunit) | **`librehu` (travail) → pousser aussi sur `main`** (lu par LibreHU Apps) | `org.librehu.headunit` | `git push origin librehu:main` |
| `LibreHU-ViPER4Android-app` / `viper4android-librehu` | ViPER4Android | main, librehu-service, vehicle-audio | `com.llsl.viper4android` | |
| `MCU-tools-app` | MCU Toolkit, doc firmware MCU (`docs/mcu_firmware.md`), `tools/mcu/` | main, main-LOS | `com.dokt.jacmcu` | ne pas toucher (règle 1) |
| `LibreHU-flashablesZips` | zips TWRP (noyaux, TWRP, tweaks, ViPER) + `dist/index.json` pour LibreHU Apps | main | — | CI horaire (cron `17 * * * *`), release `zips` |

Dépôts amont utiles : `cedricp/ddt4all` (base ECU Renault, **ne publie pas `ecu.zip`** : seulement AppImage /
installeurs), `mik3y/usb-serial-for-android` 3.10.0, `minimal-manifest-twrp/platform_manifest_twrp_aosp` (twrp-12.1).

---

## 5. Conventions git, CI et publication

- **Commits** : messages en anglais, une phrase dense ; trailers de la section 2. Corps des commits sans identifiant de modèle.
- **Applis** : chaque push sur une branche → CI `build.yml` :
  `assembleRelease` (R8), signature LibreHU, artefact « R8 reports » (`app/build/outputs/mapping/release/`),
  **rolling prerelease** `latest-<branche>` (APK `<App>-<branche>.apk` + `release.txt` : versionCode, versionName,
  branche, commit) et releases numérotées (les 15 dernières gardées). LibreHU Apps lit `release.txt` (ETag) de la
  branche configurée par appli (`branches = listOf("main")` par défaut, `master` pour CarPlay, `librehu-service`
  pour ViPER).
- **Une seule clé de signature** pour toutes les applis LibreHU (MAJ croisées via LibreHU Apps).
- **R8** sur toutes les applis Gradle (sauf MCU Toolkit) : `isMinifyEnabled`, `isShrinkResources`,
  `proguard-android-optimize.txt` + `proguard-rules.pro` ; **`-dontobfuscate` partout** ; garder les méthodes
  `native` (`-keepclasseswithmembers,includedescriptorclasses class * { native <methods>; }`) et les helpers lancés
  par `app_process` :
  - service : `-keep class org.librehu.service.atc.AtcHelper { public static void main(java.lang.String[]); }`
  - launcher : `-keep class org.librehu.launcher.system.SystemHelper { public static void main(java.lang.String[]); }`
  - CarPlay (AGP 9.3 DSL) : `optimization { enable = true }` + `mobile/src/main/keepRules/librehu.keep`
    (dont `LinuxI2cNativeException(int, String)` appelé depuis le JNI).
  - En cas de « class/method not found » : lire `usage.txt` de l'artefact R8 de la CI.
- **TWRP** : CI `build-twrp.yml` (push du fichier workflow, ou `workflow_dispatch` avec `MANIFEST_BRANCH=twrp-12.1`)
  → release **prérelease** `twrp-build-<run>` taguée sur le commit construit (`target_commitish: github.sha`,
  ajouté le 24/10 ; avant, le tag tombait sur la branche par défaut `twrp`), titre avec la branche.
  Une build devient « stable » pour LibreHU Apps quand on décoche « pre-release » à la main **après test sur l'unité**.
- **flashablesZips** : `zips/<catégorie>/<id>/` = `zip.json` + `install.sh` (corps d'`update-binary` après
  `common/twrp-common.sh`) + `prepare.sh <workdir>` optionnel ; `tools/build.py` → `dist/` + `index.json`.
  Zips TWRP : `twrp-ujc201` (dernière release **non** prérelease) et `twrp-ujc201-beta` (dernière build, préreleases
  comprises, `TWRP_CHANNEL=beta`, version `b<n>`). Vérifient l'appareil, la taille, le sha256, sauvegardent le
  recovery dans `/sdcard/LibreHU/backup/recovery-<date>.img`, écrivent puis relisent la partition.
- **Pousser** : `git push -u origin <branche>` ; en cas d'erreur réseau, 4 essais (2, 4, 8, 16 s).

---

## 6. Compiler localement

Le conteneur précédent avait : SDK dans `/root/android-sdk`, un script Gradle de miroir (`/tmp/claude-0/mirror.gradle`,
dépôts Maven via le proxy), la clé dans un clone local. Dans un nouveau conteneur, installer le SDK (platform 36,
build-tools) ou laisser la CI compiler. Commandes utilisées :

```sh
# Appli standard (service, launcher, ota, fm, widgets, btnremap, easysource, disc, bridge)
ANDROID_HOME=/root/android-sdk LIBREHU_KEYSTORE=<chemin>/librehu.jks ./gradlew --no-daemon -q :app:assembleRelease
# Tests unitaires du cœur du service (CAN, OBD, MCU, tactile…)
./gradlew --no-daemon -q :core:test
# Dialer : pas de gradlew propre, Gradle 9.7.1 de l'OTA
<ota>/gradlew -p <dialer> :app:assembleRelease
# CarPlay
./gradlew :mobile:assembleRelease
# Open Headunit (flavour github)
./gradlew :app:compileGithubReleaseKotlin   # ou assembleGithubRelease
# touchfix (TWRP, aarch64 statique sans libc)
sh tools/touchfix/build.sh                  # clang --target=aarch64-linux-gnu -ffreestanding -nostdlib … (lld)
```

AGP 9.4, Kotlin 2.4.20, Compose BOM 2026.09.00 (bridge), car-app 1.4.0. Sans clé locale, `assembleRelease` échoue
à la signature : compiler en `assembleDebug` pour vérifier, ou laisser la CI.

---

## 7. Architecture technique

### 7.1 LibreHU-service (`org.librehu.service`)

Modules principaux (`app/src/main/java/org/librehu/service/`) : `mcu`, `can`, `obd`, `power` (veille),
`touch` (touches tactiles, calibration), `display` (feux → jour / nuit), `car` (FrontLed, véhicule, son moteur),
`bt`, `phone`, `projection` (Android Auto / CarPlay), `bridge` (serveur appli téléphone), `perf` (AppCompiler,
ZygotePreload), `tweaks`, `atc` (fonctions Autochips via `AtcHelper` en `app_process`), `overlay` (OSD),
`backup` (export / import de toutes les configs), `root` (RootShell), `net` (Ethernet USB r8152), `ui` (Compose).
Logique pure et testée dans `core/src/main/kotlin/org/librehu/core/` (`can`, `obd`, `mcu`, `touch`).

- **API AIDL** `ILibreHuService` version **8** (`getObdBattery`, `getObdCarValues`, `runKeyAction`…), accès façon
  SuperSU (applis LibreHU autorisées, autres demandées).
- **Broadcasts** : `org.librehu.action.OBD` (≈1/s : valeurs PID par nom, `car:` nombres, `cartext:` textes,
  `BATTERY_PERCENT`, `BATTERY_STATUS`), `org.librehu.service.CLAIM_KEYS` (BtnRemap réclame `can:<code>`).
- **Fournisseur véhicule** (`car/VehicleProvider`) : infos voiture partagées avec launcher, Open Headunit, CarPlay
  (colonnes dont `carplay_video_low_latency`).
- **Veille** (`power/Standby.kt`) : modes OFF / SLEEP / SHUTDOWN ; en SLEEP mode avion + GPS coupés **avec marques
  persistantes** (`airplane_set_by_standby`, `gps_cut_by_standby`, écrites en `commit()`), remis au réveil, au
  contact, **ou au démarrage du service** (correctif du 22/10 : avant, un SoC coupé par le MCU laissait le mode avion).
  Minuterie MCU `F1 n` (n × 420 min sur firmware 2024.08.09).
- **Compilation AOT** (`perf/AppCompiler.kt`) : Android 9 laisse une appli hors Play Store en `speed-profile` sans
  profil = `verify` (pas de code natif) et ne compile qu'à l'arrêt en charge. Le service lance
  `cmd package compile -m speed -f <pkg>` (root) une fois par version, au démarrage (+60 s) et à chaque
  installation / MAJ ; liste dans Tweaks avec le filtre lu dans `dumpsys package dexopt`, ajout d'autres applis.
- **Zygote** (`perf/ZygotePreload.kt`) : module `/data/adb/modules/librehu_props` avec `system.prop`
  (Magisk / KernelSU) ; pas avec SuperSU ; effet au redémarrage, à mesurer (`am start -W`).

### 7.2 MCU Jancar (JAC_V1)

Trame `EE FA <len=données+1> <cmd> <données> <somme de tous les octets précédents>` sur `/dev/ttyS1` 115200.
Envoi : `1F 01` PC_READY. Reçu : `00` ACC, `04` frein à main, `0B` feux (ILL), `1F` état groupé, `0A` version,
`09` date / heure locale, `20` touche `[canal, v1..v4]` (1 IR, 2 molette, 3/4 touches AD, 5/6 volant câblé ;
relâché = FF), **`10` octets du boîtier CAN** (relayés tels quels, paquets ≤ 128 octets, ~20 ms).
Config `0F` : `02`/`03` luminosité PWM (5..100 %, gardée en flash), `04` LED façade `[type, R, G, B, mode]`
(1 auto, 2 manuel = avec feux seulement, 3 semi-auto), `00` vitesse UART du boîtier CAN (38400 par défaut).
Référence : `MCU-tools-app/docs/mcu_firmware.md`.

### 7.3 Boîtier CAN Hiworld

Trame `5A A5 LEN CMD D0..Dn-1 CS`, `CS = ((LEN + CMD + ΣD) & 0xFF) - 1` (`core/can/Hiworld.kt`).
Touche volant : message **`0x11`**, D1 bit 3 = événement, D2 = code (**octet entier** : SRC+/SRC- ne diffèrent que
dans les bits hauts), D3 = 1 sur la trame d'appui. Appui Clio 3 : `08 kk 01`, `08 kk 00`, `08 00 00`, `00 00 00`
(~100 ms) ; maintenu : la séquence se répète toutes les ~380 ms.
Codes LNP002 : 1 vol+, 2 vol-, 3/18 mute, 4 navigation, 5 précédent/décrocher, 6 suivant/raccrocher, 8 droite,
9 gauche, 10 mode, 13 précédent, 14 suivant, 15 OK, 16 téléphone, 19 décrocher, 20 raccrocher, 21 scan, 24 voix.
Codes 4 et 0x11 vus sur la Clio 3 : bouton inconnu.
**Appui court / long** (`core/can/WheelHold.kt`, testé) : appui mesuré sur les trames ; long si encore en cours
après `long_ms` (900 ms par défaut, réglable 600..2000), fin d'appui = pas de trame d'appui pendant 450 ms après un
relâchement. Une touche **sans** action longue = chaque trame d'appui est un clic (volume maintenu qui répète).
Écran CAN : « Dernier appui (trames reçues : ↓ ↑ en ms) » pour diagnostiquer.

### 7.4 OBD (`obd/ObdManager.kt`, `ObdLinks.kt`)

ELM327 en Bluetooth (SPP, puis insecure, puis canal 1 par réflexion) ou USB (usb-serial-for-android : FTDI,
CH340, PL2303, CP210x). **Une seule session à la fois** (`active = running && thread === currentThread`,
`halt()` ferme la liaison, lecture USB interruptible) : avant le 24/10, deux sessions se volaient l'adaptateur
(« Error writing 5 bytes … rc=-1 », BT qui tombe). Valeurs constructeur (`carSafely`) ne coupent plus la session.
**ddt4all** : import de `ecu.zip` (lit `db.json`, véhicules à calculateurs CAN, identification `2180` puis UDS
`22F1A0/F18A/F194/F195`, lecture seule services 21 / 22) ; **téléchargement depuis une adresse saisie** (mémorisée,
redirections suivies, ≤ 1,5 Go, vérifié avant remplacement) car ddt4all ne publie pas la base.
Batterie (`BatteryWatch`, `core/obd/CarBattery`) : charge moteur arrêté, charge / pas de charge / surtension, alarmes.
Doc : `LibreHU-service/docs/obd.md`.

### 7.5 Pont téléphone (bridge)

Serveur dans le service (`bridge/BridgeServer.kt`) : TCP **47800** (même Wi-Fi / partage de connexion) ou RFCOMM
UUID `6c1b2e6a-8f0e-4b8c-9a51-1ebd2d4c0b01`. Canal `BridgeChannel` : ECDH P-256, l'autoradio signe (ECDSA P-256),
HKDF-SHA256, AES-256-GCM numéroté. Association : QR `librehu://pair?v=1&fp=…&t=…&n=…&ip=…&p=…&bt=…` (jeton à
durée limitée) ou Bluetooth avec confirmation sur l'autoradio ; ensuite clé d'accès 32 octets (HMAC), gardée par le
keystore Android du téléphone. Requêtes `{"id","m","p"}` : `hello`, `pages`, `page`, `set`, `action`, `values`,
`subscribe`, `key`, `forget`. Pages décrites par le service (`bridge/BridgePages.kt`) et par les applis LibreHU
(permission signature). Doc : `LibreHU-service/docs/bridge.md`.
**Android Auto** (appli téléphone) : une appli Car App Library n'est listée que si elle vient d'une **source de
confiance** (Google Play) ; « Sources inconnues » ne couvre pas ces applis
(developer.android.com/training/cars/testing). L'appli propose « Réinstaller comme Google Play » (root,
`pm install -r -i com.android.vending`) ou `adb install -r -i com.android.vending LibreHU-Bridge-main.apk`
(méthode communautaire aa4mg, non garantie).

### 7.6 Launcher

Trois éditions (`main`, `librehu-service`, `ivi`). Horloge de veille (`standby/`) : numérique / analogique,
date, média, téléphone, batterie voiture, **jusqu'à 6 valeurs OBD** (`obdValues`, ordre, ligne / tuiles, noms),
aussi sur l'écran de verrouillage (`lock/LockActivity.kt`). Android Auto : switch « vidéo basse latence » qui
écrit le réglage `debug-video-low-latency` d'Open Headunit (broadcast ordonné `ACTION_SET_SETTINGS`).

### 7.7 Projection

- **Open Headunit** (fork) : préréglage LibreHU v3 (`librehu/LibreHuDefaults.kt`), basse latence décodeur
  (`vdec-lowlatency` MediaTek sous Android 11, comme Moonlight), réglages par
  `com.andrerinas.openheadunit.ACTION_GET_SETTINGS` / `ACTION_SET_SETTINGS`
  (JSON `{"format":"open-headunit-settings","version":1,"settings":{…}}`).
- **CarPlay** (xcertplay) : `AndroidMediaSink.vendorLowLatency`, `vdec-lowlatency` sur décodeur MediaTek, repli
  sans la clé si `configure` échoue ; journal « vdec-lowlatency accepted ». Infos iPhone (lockdown, batterie, iAP2).

### 7.8 TWRP (`android_device_alps_ac8257_demo`, branche twrp / ccr)

- Manifeste minimal TWRP **twrp-12.1**, TWRP 3.7.1_12, `TW_DEVICE_VERSION` remplacé par la CI par
  `UJC201-b<run>-<commit>` (affiché au démarrage) et `ro.librehu.twrp` dans `prop.default`.
- `tools/apply_twrp_patches.py` : patchs source (BCB sur `para`, fenêtres / horloge dans `gui/pages.cpp`,
  thème, **keynav**). `tools/keynav/keynav.inc` : navigation complète aux touches (cadre sur l'élément actif ;
  VOL-/VOL+ suivant / précédent, flèches = voisin, Enter = appui, glissières deux fois).
- `tools/ujc201_postprocess.py` : **obligatoire** (sinon écran noir / bootloop) : FBIOBLANK, thème, overlay
  `recovery/root`, footer AVB du recovery stock (`prebuilt/avb/recovery_stock_vbmeta_250718.bin`), `--version`.
  Ne flasher que `twrp_ujc201.img`, jamais `recovery.img` brut.
- `touchfix` (`tools/touchfix/touchfix.c` → `recovery/root/system/bin/touchfix`, 35,5 Ko, sans libc) : tactile,
  MCU (ACC, frein, feux, version, horloge, PC_READY), touches au volant → uinput `ujc201-wheel` selon
  `ujc201_keys.conf` (`/data/media/0/TWRP/` > `/tmp/` > `/system/etc/`), **boîtier CAN Hiworld depuis le 24/10**
  (trames `10` → message `0x11` → **canal 7**, table LNP002 par défaut si non appris). `wheelkeys learn|show|clear`.
  Journal `/tmp/mcu.log` (trames `10` limitées à 200).
- Menu de démarrage (`tools/bootmenu/`, dans le **boot**) : TWRP / Android / Fastboot, auto Android en 3 s.
- Vérifier un flash : `su -c "sha256sum /dev/block/platform/bootdevice/by-name/recovery"` = sha256 de la release
  (image = taille exacte de la partition).

### 7.9 Noyau

Branche `LibreHU-main` : sources GPL Autochips + gpios_ioctl, **KernelSU (Next)**, tactile GT928 calibré +
autres dalles, pilote TP9963 reconstitué, Ethernet USB intégré, lecteurs CD/DVD USB, OC CPU jusqu'à 2,6 GHz
(plafond 2,2 GHz, maximum au démarrage 2,3 GHz), GPU, tensions réglables, `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE`,
schedtune / WALT, touch boost MTK (`drivers/misc/mediatek/performance/tchbst`). `connectivity-builtin` : pilotes
WMT/WLAN/BT/GPS/FM dans le noyau (en cours). Zips : `kernel-librehu(-bootmenu)`, `kernel-connectivity(-bootmenu)`.
Le zip noyau sauvegarde `boot` d'abord, ne touche pas à `vbmeta`.

---

## 8. Où sont les docs internes

- Service : `README.md`, `docs/*.md` (android-auto, atc, bluetooth, bridge, can-vehicles, gps-time, mcu-profiles,
  obd, phone, power, reverse-view, touch, video, `ivi-services/` = rétro-ingénierie du service stock).
- Launcher : `README.md`, `docs/standby.md`.
- Noyau : `docs/ujc201/` (audio, deep buffer, Ethernet, GPL, projection stock, réglages cachés, ROM, tester un noyau, vidéo).
- MCU : `MCU-tools-app/docs/mcu_firmware.md`.
- TWRP : `README.md`, `CHANGELOG.md` de ce dépôt.
- Forks : `README_LIBREHU.md` (Open Headunit, xcertplay, ViPER) : chaque fichier modifié et pourquoi.

---

## 9. Pièges connus (déjà payés une fois)

- **Mauvaise branche** : CarPlay et Open Headunit se travaillent sur `librehu` mais LibreHU Apps lit `master` /
  `main` : pousser les deux (`librehu:master`, `librehu:main`). Une branche `librehu` en trop sur Open Headunit
  n'a pas pu être supprimée (403) ; préreleases `latest-librehu` inutiles dans les deux forks (à nettoyer si l'utilisateur veut).
- **Launcher** : oublier de merger `main` dans `librehu-service` et `ivi`.
- **R8** : une classe appelée par réflexion / JNI / `app_process` disparaît. Vérifier le dex (`dexdump`) ou
  `usage.txt`. usb-serial-for-android garde ses pilotes avec ses propres règles (vérifié).
- **dexopt** : `speed-profile` sans profil = rien ; utiliser `speed`.
- **Tags de release TWRP** : sans `target_commitish`, le tag tombe sur `twrp` même si l'image vient d'une autre
  branche (cas de la build 10 : image keynav `f8bb3d0`, tag `a8e89d3`).
- **Accès GitHub** : `gh` dans le conteneur n'a pas accès aux dépôts LibreHU sous leur nom d'organisation ;
  passer par l'outil GitHub MCP (noms acceptés : ceux de la portée de la session).
- **Disque** : l'allocation de la session est fixe ; supprimer les builds / clones inutiles si « no space left ».
- **Conteneur redémarré** : les compilations en arrière-plan meurent ; relancer.
- **Chaînes Android** : échapper `'` en `\'` dans `strings.xml` (sinon erreur aapt).
- **Python inline** dans des heredocs : attention aux guillemets (une erreur de syntaxe n'écrit rien).

---

## 10. Fait récemment (21–24/10/2026) : à tester sur l'unité

| Quoi | Dépôt / commit | À vérifier sur l'autoradio |
|---|---|---|
| R8 sur toutes les applis + rapports CI | toutes (22/10) | ouverture de chaque appli, fonctions natives (FM, Disc), helpers root |
| Basse latence vidéo AA / CarPlay | service, launcher, headunit `eb71158`, carplay `f39b974` | image fluide ; « vdec-lowlatency accepted » dans le journal CarPlay ; sinon couper le switch |
| Appui court / long volant (WheelHold) | service `6a1bb98` | Clio 3 : court = action courte, long (≥ 0,9 s) = action longue ; ligne « Dernier appui » |
| Mode avion après veille | service `6a1bb98` | après une nuit / coupure, mode avion et GPS remis |
| Liste de compilation AOT + autres applis | service `6a1bb98` | Tweaks : filtres « speed » ; ajout d'une appli tierce |
| Interrupteur Zygote preload | service `6a1bb98` | module créé, valeur au redémarrage, mesure `am start -W` |
| LEDs façade refaites (test couleur / blanc) | service `6a1bb98` | **en attente par choix de l'utilisateur** |
| Compilation `speed` après install | OTA `1861e60` | appli installée → filtre `speed` |
| OBD une session + téléchargement ecu.zip | service `b5e0d06` | FT232R @ 38400, protocole A6 : plus d'« Error writing… » ; BT stable |
| Appli téléphone nouvelle interface + carte AA | bridge `6657a6f` | réinstallation « Google Play » → visible dans AA |
| Horloge de veille : valeurs OBD | launcher `73290f2` (+ éditions) | 6 valeurs, ordre, ligne / tuiles, écran de verrouillage |
| TWRP : version + tag correct | device `cdc7b32` | version au démarrage |
| TWRP : touches du boîtier CAN | device `3c5b078` (build relancée le 24/10) | **Clio 3 : touches volant dans TWRP** (si rien : vérifier la vitesse du boîtier, `/tmp/mcu.log` lignes `rx ee fa .. 10`) |
| Zip TWRP bêta | flashablesZips `8ffe619` | apparaît dans LibreHU Apps → Zips → recovery |

Diagnostic TWRP de l'utilisateur (« le .img bêta n'a pas l'air de s'installer ») : le flash marchait, la build 10
contenait keynav (journal CI : `pages.cpp (keynav, 19 types d'elements)`), mais TWRP ne lisait que les touches
câblées (`20`), pas celles du boîtier CAN (`10`) : d'où aucune navigation au volant sur la Clio 3.

---

## 11. En attente / à faire

1. **LEDs MCU** : ne rien faire tant que l'utilisateur ne relance pas le sujet (section 1).
2. **Bugs MCU (#92)** : LEDs, lumières, timeout veille, reboot après coupure contact, défaut lumière : attend des
   infos de l'utilisateur.
3. **TWRP** : confirmer sur l'unité la build avec boîtier CAN ; si OK, la passer en release (décocher prérelease)
   pour le zip stable ; fusionner `ccr-eca2d7b0-vz26un` → `twrp` seulement si l'utilisateur le demande.
4. **Analyse audio de la ROM stock (#25)** et **branche noyau `connectivity-builtin` (#78)** : en cours.
5. Pistes perf proposées, non lancées (à faire seulement sur demande) : boost CPU au toucher (`tchbst`),
   caméra de recul en `SurfaceView` (aujourd'hui `TextureView`), options de compilation de ViPER.
6. Nettoyage possible (sur demande) : préreleases `latest-librehu` des forks, branche `librehu` en trop.

---

## TL;DR

Jancar UJC201 (AC8257, Android 9), Clio 3 avec boîtier CAN Hiworld. Tout le code est sur GitHub (organisation
LibreHU + Dok-T), compilé et signé par les CI ; ce fichier dit quoi pousser où (launcher = 3 branches, forks =
`librehu` + `main` / `master`, TWRP = branche `ccr-eca2d7b0-vz26un`). Règles : français, sources citées, TL;DR,
rien de non demandé, jamais vbmeta / dm-verity, ne rien publier de propre à l'unité, trailers dans chaque commit.
À tester en priorité : TWRP avec touches du boîtier CAN, OBD USB/BT, appui court / long, mode avion après veille.
LEDs MCU : en pause.
