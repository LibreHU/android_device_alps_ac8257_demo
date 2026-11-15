# LineageOS 17.1 (Android 10) pour l'UJC201 — branche expérimentale

*English: [LINEAGE-17.1.en.md](LINEAGE-17.1.en.md)*

Branche **`lineage-17.1`** : le même arbre que `lineage-16.0` (LineageOS 16.0, Android 9), porté sur LineageOS 17.1
(Android 10). Une vraie ROM construite depuis les sources LineageOS. Le vendor reste celui de l'unité (Android 9,
VNDK 28, Treble) et le noyau celui de LibreHU (`stable-4.9.337`).

**État (15/11/2026) : en construction par la CI, jamais essayée sur l'unité.** La branche `lineage-16.0` reste la ROM
de tous les jours.

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
3. **Effacer data** (Wipe > Format Data) est conseillé : le passage d'une 16.0 à une 17.1 avec les données n'a
   jamais été essayé (l'installateur le signale s'il trouve des données d'Android 9).
4. Après l'essai, envoyer `adb logcat -b all -d`, `adb shell dmesg`, `adb shell getprop` et, en cas de redémarrage,
   le contenu de `/sys/fs/pstore` (depuis TWRP).

## Points à vérifier sur l'unité

- Ordre des propriétés d'Android 10 : celles du vendor stock passent **après** celles du system
  (`init/property_service.cpp`, `property_load_boot_defaults`, « Overriding previous 'ro.' property ») : une valeur du
  vendor qui différerait de `device.mk` gagne (à comparer avec `getprop`).
- Compilation SELinux au démarrage : plateforme Android 10 + politique du vendor Android 9 par le mapping 28.0.
  Avec `androidboot.selinux=permissive` (image de boot LibreHU), un échec de compilation reste fatal (redémarrage en
  bootloader) : c'est le premier point à regarder si l'unité ne démarre pas.
- Matrice de compatibilité (FCM 3) : noyau 4.9.337 couvert. Le noyau 4.19 expérimental ne l'est pas (dialogue
  « problème interne » probable, non bloquant).
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
