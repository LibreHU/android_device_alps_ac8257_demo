# Video de la ROM stock : CVBS IN 1 / 2, VIDEO OUT, AUDIO OUT

Analyse de la ROM Jancar (UJC201, AC8257) pour les RCA du faisceau : **CVBS IN 1**, **CVBS IN 2** (video seule),
**VIDEO OUT** et **AUDIO OUT**. Mise en oeuvre sans les applis Jancar : LibreHU-service, Vehicule -> Video
(`docs/video.md` de LibreHU-service).

## Entrees CVBS
- Un seul decodeur CVBS, camera Android `3` (`/jancar/config/ivi-config.ini`, `[CameraIndex]` : `AV=3`, `REAR=3`,
  `FRONT=11`, `TV=6`).
- Commutateur video analogique devant le decodeur : ivi-services
  `Platform_AutoChips_8257_Base.platformSelectInput(avId)`, GPIO `167` (SW1) et `165` (SW2) :
  AV / TV -> 0/0, FRONT -> 1/0, REAR -> 1/1 ; 0/1 n'est jamais ecrit ; AV2 (`avId 2`) n'a pas de cas sur l'AC8257.
  `[VideoChannelConfig]` (vide ici) permettrait de renvoyer un `avId` sur un autre (`IVIConfig.getConfigVideoChannel`).
- Appli AV `com.jancar.avin` (`/vendor/app/ivi-input`) : `setAndroidCameraOpenPrepared(1)` (-> `selectInput`), camera
  3, taille selon le type CVBS (`[AVIn] DefaultCVBSType`). Si la camera de recul est CVBS
  (`ivi-customer.ini BackCarVideoSource=0`), elle lache la camera en marche arriere, met REAR (32), puis reprend ;
  propriete `persist.avin.frontavin` pendant ce temps (lue par `com.jancar.hd2cam`).
- Video bloquee frein desserre (`IVICore.isMediaVideoPermit`).
- Son : `IVIAVIn.Id.getAudioChannel` AV -> 25, AV2 -> 26 ; `platformSwitchAudioTo(25)` -> BD37534 entree
  `mAVPhyAudioChannel = 0`, la meme que l'AUX (`Platform_AutoChips_8257_37534`). Les RCA CVBS IN de cette unite
  n'ont pas de son.

## VIDEO OUT
- ATC Settings (`com.autochips.atcsettings`, Affichage) : interrupteur **Rear display** = metazone `65550`
  (`AtcDisplaySettingsUtils.setRearDisplay`), visible si `hwc.external_display_enable=1`, redemarrage necessaire.
- `hwcomposer.ac8257.so` : ecran externe en miroir (`createExternalDisplay`, `setMirror`), publie
  `hwc.external_display_enable` / `hwc.external_display_open` (contexte SELinux `atc_hwc_prop`). Vus a `0` / `0` dans
  les getprop collectes.
- ivi-settings, `RearOutputActivity` (« Rear output settings ») : `hwc.rear_disp_fmt` (`P` / `N`),
  `hwc.rear_disp_lb_y_top`, `_y_bottom`, `_x_left`, `_x_right` (0..50), sauves dans
  `/jancar/config/jac_rear_output.json` ; `Settings.Global key_rear_display` ; puis
  `SettingsService.setRearDisplay` -> `startService(com.jancar.usbdisplay/.service.CaptureService,
  action change_rear_display, extra change)`.
- `com.jancar.usbdisplay` (`/vendor/app/ivi-usbdisplay`, uid system, persistant) : lit `key_rear_display` au demarrage
  (journal `MainService onCreate: key_rear_display = 1`), gere aussi les ecrans USB et l'AVM 360. APK absent de la
  collecte : son `CaptureService` n'est pas decompile, et le lecteur de `hwc.rear_disp_*` n'est pas identifie (pas le
  compositeur).

## AUDIO OUT
Sortie ligne du BD37534 (meme son que les haut-parleurs). Aucun reglage dedie dans ivi-settings / ivi-audio-settings
(seulement « Digital audio output », SPDIF).
