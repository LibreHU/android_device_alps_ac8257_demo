# LineageOS 17.1 (Android 10) pour l'UJC201 — branche expérimentale

*English: [LINEAGE-17.1.en.md](LINEAGE-17.1.en.md)*

Branche **`lineage-17.1`** : le même arbre que `lineage-16.0` (LineageOS 16.0, Android 9), porté sur LineageOS 17.1
(Android 10). Une vraie ROM construite depuis les sources LineageOS. Le vendor reste celui de l'unité (Android 9,
VNDK 28, Treble) et le noyau celui de LibreHU : `rc-4.19.325`, variante `a10-lto32` depuis le 19/11/2026
(`a10` le 18/11 ; un noyau par ROM : la 16.0 garde `stable-4.9.337`). Ce noyau demande une **partition boot de
32 Mio** : le zip la migre tout seul (voir Installer).

**État au 23/11/2026** : builds publiés le 21/11 (`4716bf9`, `8027ca6`, `f9859e6`, `d54fe5c`, release
`lineage-17.1-…` + flux `lineage-17.1-ota`), en service sur l'unité de l'auteur avec le noyau 4.19 `a10-lto32`.
Essayé : Wi-Fi WPA3 (HAL supplicant 1.2, 300 Mbit/s en 5 GHz), applis caméra (caméras masquées / avant / arrière par
LibreHU-service), noyau de test `experimental-4.19.325-lcm-mz` (dalle d'après la MetaZone, identifiant de carte
`A0_AN`). Prochain build (pas encore lancé) : nettoyage du vendor par le zip (applis du fabricant, RRO MediaTek,
uVoice, avec sauvegarde) et ECNR WebRTC de LibreHU à la place d'uVoice (`tools/fetch_ecnr.sh`), valeurs télécom du RRO dans l'overlay, scan Wi-Fi en arrière-plan.
Connu : SELinux permissif, le flot d'audit avc `proc_ged` remplit `dmesg` en ~30 s. L'historique ci-dessous reste valable.

**État (18/11/2026) : les essais du 18/11 (noyau 4.9, puis 4.19) ne finissaient pas de démarrer : system_server et
SystemUI mouraient toutes les 8 s. Codec2 d'Android 10 demande n'importe quel heap ION (`~0`) et recevait
`ion_mm_heap_for_pa2mva`, un buffer sans mémoire. Corrigé dans les deux noyaux le 18/11 ; build suivant avec le 4.19
`a10`, à réessayer.** La branche `lineage-16.0`
reste la ROM de tous les jours.

## Ce qui change par rapport à `lineage-16.0`

| Sujet | `lineage-16.0` (Android 9) | `lineage-17.1` (Android 10) |
|---|---|---|
| Bibliothèques du vendor stock | VNDK 28 = VNDK du system | `PRODUCT_EXTRA_VNDK_VERSIONS := 28` (device.mk) : le system garde `/system/lib*/vndk-28` et `vndk-sp-28` (`prebuilts/vndk/v28`) à côté des siennes ; la CI vérifie leur présence |
| `genfscon fuseblk` de LineageOS (conflit avec la politique du vendor Jancar) | retiré par `tools/patch_lineage_sources.sh` | `TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR := true` (réglage prévu par LineageOS 17.1, `device/lineage/sepolicy/common/sepolicy.mk`) |
| fs_mgr qui croit l'unité verrouillée (LK Jancar : `verifiedbootstate=green`) | `fs_mgr_is_device_unlocked()` corrigé | les **deux** copies du test d'Android 10 corrigées : `fs_mgr_is_device_unlocked()` (`fs_mgr/fs_mgr.cpp`) et `IsDeviceUnlocked()` (`fs_mgr/libfs_avb/util.cpp`, montage de vendor par la première étape de l'init) |
| Rotation de la dalle et du tactile | patch SurfaceFlinger + InputReader | même logique, patch refait pour Android 10 (`TouchInputMapper::findViewport`) |
| Rétroéclairage inversé | patch LightsService | même logique, appliquée avant les deux chemins d'Android 10 (SurfaceControl et HAL lights) |
| Focus audio de la musique Bluetooth (A2DP sink) | patch de l'appli Bluetooth | réglage natif d'Android 10 : `a2dp_sink_automatically_request_audio_focus` = true (overlay) ; plus de patch |
| `autochips.jar` dans le BOOTCLASSPATH | module Make du dépôt vendor (branche `lineage-16.0`) | Android 10 construit l'image de démarrage dans Soong, qui ne trouve que des modules Soong (« failed to find dex jar path ») : branche `lineage-17.1` du dépôt vendor, `Android.bp` (`dex_import`, comme l'outil d'extraction de LineageOS 17.1) ; avec une copie `lineage-16.0`, le script fait la même chose dans la copie locale |
| APEX | — | aplatis (`TARGET_FLATTEN_APEX := true`, défaut d'Android 10 sans `updatable_apex.mk`) |
| `USE_XML_AUDIO_POLICY_CONF` | nécessaire | toujours nécessaire (Android 10 ne lit que l'XML mais `AudioPolicyManager.cpp` s'arrête sans le drapeau) |
| Permissions privilégiées vérifiées | liste d'Android 9 | `librehu/privileged-permissions-android10.txt` (217 permissions) ; les applis LibreHU du 15/11/2026 y passent sans ajout |
| Flux de l'appli Mises à jour | release `lineage-16.0-ota` | release `lineage-17.1-ota` (une 17.1 n'est jamais proposée à une 16.0) |
| Politique audio (moteur) | courbes de `audio_policy_configuration.xml` du vendor | Android 10 ne lit `audio_policy_engine_configuration.xml` que dans `/vendor/etc` (absent du vendor Android 9) et reprend alors les courbes du vendor, incomplètes (pas `AUDIO_STREAM_ACCESSIBILITY`) : patch `frameworks/av` (comme Android 11, un groupe de volume absent prend les courbes de la musique) ; sans lui audioserver plantait en boucle |
| SystemUI | `/system/priv-app` (passe avant `/vendor/app/ivi-systemui`) | Android 10 le met dans `/system/product`, parcouru **après** `/vendor/app` : l'`ivi-systemui` Jancar (même paquet `com.android.systemui`) prenait sa place ; patch `frameworks/base` : retour dans `/system/priv-app` |

## Canal de mises à jour (OTA) propre à la 17.1

Une 17.1 ne se met à jour que depuis le canal 17.1, jamais depuis celui de la 16.0 ni d'une autre version, et une
16.0 ne voit jamais de 17.1. Quatre barrières :

1. **Flux séparé** : l'appli Mises à jour de la 17.1 lit `releases/download/lineage-17.1-ota/updater.json`
   (`overlay/packages/apps/Updater`) ; celle de la 16.0 lit `lineage-16.0-ota`. La CI de chaque branche n'écrit que
   dans son flux, celle de `lineage-17.1` ne touche jamais `lineage-16.0-ota`.
2. **CI** : ne publie que si `ro.lineage.build.version` du build vaut `17.1`, si l'appli Updater construite contient
   bien l'adresse du flux 17.1 (et pas celle de la 16.0), et si le tag commence par `lineage-17.1-`. Sinon rien
   n'est publié.
3. **Appli Updater de LineageOS 17.1** (`Utils.isCompatible` / `Utils.canInstall`) : une mise à jour d'une version
   plus ancienne (16.0) n'est même pas listée ; une autre version n'est jamais installable (il faut
   `ro.lineage.build.version` identique).
4. **Installateur du zip** : une installation lancée par l'appli Mises à jour (block map) lit la version de LineageOS
   installée (`build.prop` du system) et la compare à celle du zip (`info/lineage_version`) : différentes, il
   s'arrête avant d'écrire quoi que ce soit (« chaque version a son propre canal de mise à jour »). Un flash à la main
   dans TWRP reste possible pour changer de version volontairement.

Il n'y a pas de LineageOS 17.0 : la version d'Android 10 de LineageOS est la 17.1 (`ro.lineage.build.version=17.1`).

## Construire

Comme [BUILD.md](BUILD.md), avec ces différences :

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-17.1 --depth=1
```

Manifeste local : l'arbre et le dépôt vendor en `revision="lineage-17.1"` (mêmes fichiers propriétaires que sa
branche `lineage-16.0`, `autochips.jar` en module Soong).

```xml
<project name="LibreHU/android_device_alps_ac8257_demo" path="device/alps/ac8257_demo" remote="github" revision="lineage-17.1" />
<project name="LibreHU/android_vendor_jancar_ac8257_demo" path="vendor/jancar/ac8257_demo" remote="github" revision="lineage-17.1" />
```

Après chaque `repo sync`, depuis la racine des sources (le build s'arrête sinon, `BoardConfig.mk`) :

```bash
device/alps/ac8257_demo/tools/patch_lineage_sources.sh
```

Puis `librehu/fetch_apks.sh`, `tools/fetch_kernel.sh`, `tools/fetch_viper.sh`, `lunch lineage_ac8257_demo-userdebug`,
`m systemimage signapk`, comme en 16.0.

## CI

`.github/workflows/lineage-17.1-build.yml` : à chaque push de `lineage-17.1` dont le message contient `[build]`, ou à
la main. Séparée de celle de `lineage-16.0` : groupe de concurrence `lineage-17.1-build`, cache ccache
`lineage-17.1-ccache-*` (6 Gio, un seul gardé : les 10 Go de cache du dépôt sont partagés), releases
`lineage-17.1-<date>-<arbre>` (préversions), zip `LibreHU-LineageOS-17.1-ac8257_demo-<date>-<arbre>.zip`, flux
`lineage-17.1-ota`. Elle ne touche jamais `lineage-16.0-ota`.

## Installer (quand un build existe)

1. Sauvegarde TWRP complète (system, boot, data) : c'est le retour arrière.
2. Zip dans TWRP comme en 16.0 ([INSTALL.md](INSTALL.md)) ; `vbmeta` reste comme il est (vérification désactivée).
   **Partition boot de 32 Mio** (19/11/2026) : le noyau `a10-lto32` ne tient pas dans les 10 Mio d'origine. Si la
   partition fait encore 10 Mio, le zip lance d'abord `librehu_boot32_twrp.zip` (inclus, de la release du noyau :
   4,4 Go libres dans la mémoire interne, sauvegardes dans `/sdcard/LibreHU/boot32`, vendor réduit à 2033 Mio), puis
   TWRP redémarre et le zip se réinstalle tout seul (OpenRecoveryScript ; mise à jour par l'appli : commande du
   recovery). Rien de LineageOS n'est écrit avant la migration. Zip dans `/tmp`, une clé USB ou en sideload : le
   réinstaller à la main après le redémarrage. La migration se fait aussi seule depuis TWRP LibreHU (Avancé >
   Boot partition: grow to 32 MiB) ; retour : `librehu_boot32_restore_twrp.zip` (entrée « back to 10 MiB »). Après
   la migration, une image de boot de 10 Mio (16.0, noyau 4.9) ne se flashe qu'avec les zips TWRP 4.19 de LibreHU
   (ils déplacent le pied AVB en fin de partition) ou en revenant à 10 Mio.
3. **Effacer data** (Wipe > Format Data) est conseillé : le passage d'une 16.0 à une 17.1 avec les données n'a
   jamais été essayé (l'installateur le signale s'il trouve des données d'Android 9).
4. Après l'essai, envoyer `adb logcat -b all -d`, `adb shell dmesg`, `adb shell getprop` et, en cas de redémarrage,
   le contenu de `/sys/fs/pstore` (depuis TWRP).

## Premier essai sur l'unité (15/11/2026, build du 15/11, noyau 4.9.337)

- Android ne finissait pas de démarrer (pas de `sys.boot_completed`) : `system_server` attendait
  `media.audio_policy` sans fin (« Waiting for service 'media.audio_policy' »), car `audioserver` plantait à chaque
  démarrage (47 tombstones : SIGSEGV, pointeur nul, `EngineBase::loadAudioPolicyEngineConfig()` de
  `libaudiopolicyenginedefault.so`). Cause : stratégie `STRATEGY_ACCESSIBILITY` sans groupe de volume (voir le
  tableau). Corrigé (patch `frameworks/av`).
- SystemUI : celle du vendor (`/vendor/app/ivi-systemui`, Android 9) installée à la place de celle de LineageOS.
  Corrigé (patch `frameworks/base`). Les données de la 16.0 étaient gardées : formater data reste conseillé.
- Bluetooth : le HAL MediaTek s'arrête (« TurnOn: failed to init Bluetooth! »), `wmt_loader` arrêté : à revoir
  au prochain essai.

## Caméra, caméra de recul, AV IN (21/11/2026)

- Appli Caméra qui plante, pas de caméra de recul ni d'AV IN 1 / 2 : `cameraserver` ne publiait jamais le service
  caméra (« Camera service is unavailable »). Android 10 prend la liste des fournisseurs de caméra dans le manifeste
  VINTF et attend chacun dans `getService()` (`CameraProviderManager::listServices`, `listManifestByInterface`) ; le
  manifeste du vendor Jancar déclare `ICameraProvider/internal/0`, que personne ne sert (son `camhal3lite`
  enregistre `internal/1`) : attente sans fin (« Waited one second for ...ICameraProvider/internal/0 »). Android 9
  n'essayait que `legacy/0` et `external/0`, sans les attendre. Corrigé (patch `frameworks/av` 0002) : seuls les
  fournisseurs du manifeste déjà enregistrés sont attendus, les autres arrivent par la notification d'enregistrement.
- `atcavm_server` (serveur 360 Autochips, binaire Android 9 du system stock) refusé par le lieur à chaque démarrage :
  « cannot locate symbol `_ZN7android13GraphicBuffer4lockEjPPv` » (`GraphicBuffer::lock(uint32_t, void**)` a pris
  deux paramètres en Android 10). Seul symbole manquant de ce binaire et de ses bibliothèques stock face à l'image
  17.1 (vérifié sur `lineage-17.1-20261121-1132-8027ca6`). Shim `librehu/shim_atcavm` (`libshim_atcavm`), chargé par
  le lieur de LineageOS pour ce binaire seulement (`TARGET_LD_SHIM_LIBS`) : pas de `LD_PRELOAD`, ignoré pour un
  processus `AT_SECURE`.

- Appli Caméra : le HAL Jancar déclare des caméras sans capteur (2, 10, 11, 12 sur l'unité du 21/11 : échec -38) et
  les dit « arrière » ; l'appli (première arrière, première avant) ouvrait la 2. Patch `frameworks/av` 0003 :
  `persist.librehu.camera.hidden` (caméras masquées, `2,10,11,12`) et `persist.librehu.camera.facing` (orientation
  forcée, `3:back,0:front,8:external`), posés par LibreHU-service (Véhicule → Vidéo) qui redémarre `cameraserver`.
  Sans ces propriétés, rien ne change. Carte de l'unité du 21/11 : 0 = caméra USB (avant), 3 = décodeur CVBS (AV IN 1 /
  2 et recul CVBS, commutateur analogique), 8 et 9 = caméras qui s'ouvrent (AHD, puce 9963 pour la 8 selon Jancar).

## SELinux : commandes GED (`/proc/ged`) du pilote GPU (25/11/2026)

- Constat (rapports LibreHU Helper du 25/11, 17.1) : des milliers de refus SELinux `ioctl` sur `/proc/ged`
  (`proc_ged`) par minute, de `hal_graphics_composer_default` (de loin le premier), des applis, `bootanim`,
  `mediacodec`, `surfaceflinger`, `hal_graphics_allocator_default`, `system_server` ; commandes `0x6701`, `0x6704`,
  `0x6765`, `0x6766`, `0x6769` (GED : journal GPU, fences 3D, infos de buffers ; `ged_bridge_id.h`). En permissif, les
  appels passent, mais `dmesg` et logcat sont écrasés en quelques minutes (`audit_lost` à 5,38 millions).
- Cause : Android 10 ajoute pour tous les domaines et tous les fichiers
  `allowxperm domain { file_type fs_type domain dev_type }:{ dir notdevfile_class_set blk_file } ioctl { FIOCLEX FIONCLEX };`
  (`system/sepolicy/public/domain.te`, LineageOS 17.1 à 21.0 ; absente de la 16.0). Dès qu'une règle `allowxperm`
  existe pour un couple source / cible, seuls les ioctl listés passent. La politique vendor stock (Android 9)
  n'autorise GED que par des règles `ioctl` sans liste (`(allow X proc_ged (file (ioctl ...)))`, 30 sources) :
  sous Android 10, plus aucune commande GED n'est permise.
- Correctif : le zip de la ROM génère `/vendor/odm/etc/selinux/odm_sepolicy.cil` depuis la politique vendor
  installée (`tools/flashable/odm-sepolicy.sh`) : pour chaque source à laquelle le vendor donne `ioctl` sur
  `proc_ged`, `(allowx SRC proc_ged (ioctl file ((range 0x6700 0x670c) (range 0x6764 0x6769))))`, les 19 commandes du
  pilote GED (identiques en 4.9 et 4.19). Sans partition odm, `/odm` pointe sur `/vendor/odm` et l'init l'ajoute à la
  politique qu'il compile au démarrage (`init/selinux.cpp`, Android 10 à 14). Seules les sources du vendor installé
  sont reprises : chaque nom existe dans la politique compilée. La classe `chr_file` n'est pas reprise (pas sous
  liste blanche : une règle l'y mettrait). Un `odm_sepolicy.cil` qui n'est pas de LibreHU n'est jamais touché.
- Vérifié hors ligne : compilation par `secilc` avec les options de l'init (`-m -M true -G -N`) de la plateforme
  LineageOS (mapping 28.0) + vendor stock de l'unité + ce fichier : OK, mêmes 26 échecs `neverallow` préexistants
  avec et sans (aucun ne le concerne) ; `sesearch` : les 11 domaines refusés dans les journaux ont la règle.
  `tools/ci/test_odm_sepolicy.sh` (CI) compile la sortie du générateur dans une politique minimale (le vendor de
  l'unité n'est jamais publié) et refuse une règle mal formée.
- Les zips Android 9 (16.0, crDroid 9.0) retirent ce fichier s'il a été laissé par une ROM Android 10+ : la
  politique vendor stock y suffit.

## Points à vérifier sur l'unité

- Ordre des propriétés d'Android 10 : celles du vendor stock passent **après** celles du system
  (`init/property_service.cpp`, `property_load_boot_defaults`, « Overriding previous 'ro.' property ») : une valeur du
  vendor qui différerait de `device.mk` gagne (à comparer avec `getprop`).
- Compilation SELinux au démarrage : plateforme Android 10 + politique du vendor Android 9 par le mapping 28.0.
  Avec `androidboot.selinux=permissive` (image de boot LibreHU), un échec de compilation reste fatal (redémarrage en
  bootloader) : c'est le premier point à regarder si l'unité ne démarre pas.
- Matrice de compatibilité (FCM 3) : celle d'Android 10 ne liste que les noyaux 4.4, 4.9 et 4.14
  (`hardware/interfaces/compatibility_matrices/Android.bp`). Avec le 4.19, `Build.isBuildConsistent()` échoue :
  dialogue « problème interne » attendu au démarrage, non bloquant.
- Démarrage d'activités depuis l'arrière-plan restreint par Android 10 : à surveiller pour LibreHU-service (caméra de
  recul, sources).

## Sources

- Fuseblk : [`sepolicy.mk`](https://github.com/LineageOS/android_device_lineage_sepolicy/blob/lineage-17.1/common/sepolicy.mk),
  [`genfs_contexts`](https://github.com/LineageOS/android_device_lineage_sepolicy/blob/lineage-17.1/common/private/genfs_contexts).
- fs_mgr : [`fs_mgr.cpp`](https://github.com/LineageOS/android_system_core/blob/lineage-17.1/fs_mgr/fs_mgr.cpp)
  (`fs_mgr_is_device_unlocked`), [`libfs_avb/util.cpp`](https://github.com/LineageOS/android_system_core/blob/lineage-17.1/fs_mgr/libfs_avb/util.cpp)
  (`IsDeviceUnlocked`), [`libfs_avb/fs_avb.cpp`](https://github.com/LineageOS/android_system_core/blob/lineage-17.1/fs_mgr/libfs_avb/fs_avb.cpp)
  (`AvbHandle::Open`).
- Boot jar Soong : [`dexpreopt_bootjars.go`](https://github.com/LineageOS/android_build_soong/blob/lineage-17.1/java/dexpreopt_bootjars.go)
  (« failed to find dex jar path »), [`bootjar.go`](https://github.com/LineageOS/android_build_soong/blob/lineage-17.1/android/bootjar.go),
  [`prebuilt.go`](https://github.com/LineageOS/android_build_soong/blob/lineage-17.1/android/prebuilt.go) (`PrebuiltMutator`),
  [`extract_utils.sh`](https://github.com/LineageOS/android_vendor_lineage/blob/lineage-17.1/build/tools/extract_utils.sh)
  (`dex_import`), [`base_rules.mk`](https://github.com/LineageOS/android_build/blob/lineage-17.1/core/base_rules.mk)
  (« already defined by »).
- APEX, vendor prébuilt : [`core/board_config.mk`](https://github.com/LineageOS/android_build/blob/lineage-17.1/core/board_config.mk)
  (`TARGET_FLATTEN_APEX`, `BUILDING_VENDOR_IMAGE`, `PRODUCT_EXTRA_VNDK_VERSIONS`) ; manifeste
  [`default.xml`](https://github.com/LineageOS/android/blob/lineage-17.1/default.xml) (`prebuilts/vndk/v28`).
- Propriétés : [`property_service.cpp`](https://github.com/LineageOS/android_system_core/blob/lineage-17.1/init/property_service.cpp).
- Bluetooth : [`config.xml`](https://github.com/LineageOS/android_packages_apps_Bluetooth/blob/lineage-17.1/res/values/config.xml),
  [`A2dpSinkStreamHandler.java`](https://github.com/LineageOS/android_packages_apps_Bluetooth/blob/lineage-17.1/src/com/android/bluetooth/a2dpsink/A2dpSinkStreamHandler.java),
  voiture de référence : [`car_product`](https://github.com/LineageOS/android_packages_services_Car/tree/lineage-17.1/car_product).
- Rotation : [`SurfaceFlinger.cpp`](https://github.com/LineageOS/android_frameworks_native/blob/lineage-17.1/services/surfaceflinger/SurfaceFlinger.cpp),
  [`InputReader.cpp`](https://github.com/LineageOS/android_frameworks_native/blob/lineage-17.1/services/inputflinger/InputReader.cpp) ;
  rétroéclairage : [`LightsService.java`](https://github.com/LineageOS/android_frameworks_base/blob/lineage-17.1/services/core/java/com/android/server/lights/LightsService.java).
- Permissions privilégiées : [`AndroidManifest.xml`](https://github.com/LineageOS/android_frameworks_base/blob/lineage-17.1/core/res/AndroidManifest.xml).
- Mises à jour : [`Utils.java`](https://github.com/LineageOS/android_packages_apps_Updater/blob/lineage-17.1/src/org/lineageos/updater/misc/Utils.java)
  (`isCompatible`, `canInstall`, `getServerURL`), [`Constants.java`](https://github.com/LineageOS/android_packages_apps_Updater/blob/lineage-17.1/src/org/lineageos/updater/misc/Constants.java)
  (`ro.lineage.build.version`).
