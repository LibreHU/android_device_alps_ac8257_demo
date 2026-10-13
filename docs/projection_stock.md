# CarPlay, Android Auto et duplication d'ecran : applis de la ROM stock

Analyse (jadx, chaines des bibliotheques) des APK de l'UJC201 (Android 9, AC8257). Rien n'est publie ici que du
comportement : ces applis sont proprietaires (Google, Autochips, Jancar, editeurs chinois).

## Vue d'ensemble

| Dossier (`/system/app` ou `priv-app`) | Paquet, version | Nom affiche | Role |
|---|---|---|---|
| `ivi-CarPlay` | `com.autochips.carplayapp` 9.250606 (uid system) | **CPLink** | Interface CarPlay (filaire et sans fil) |
| `CarplayService` | `com.autochips.carplay` 9 (uid system) | - | Pile CarPlay Autochips (iAP2, flux, session) |
| `ivi-AndroidAuto` | `com.google.android.projection.sink` 9.250618 (uid system) | Android Auto | Recepteur Android Auto officiel de Google, integre par Jancar |
| `CarEventService` | `com.autochips.careventservice` 9 | - | « Car Event Monitor » Autochips, demarre seulement si `persist.sys.cemservice` = 1 ; sans lien avec la projection |
| `SpeedPlay` | `com.suding.speedplay` sd_2.0.32 | SpeedPlay | Tout-en-un tiers (Suding / Texustek) : CarPlay, Android Auto, CarLife, AirPlay, Android en miroir |
| `EasyConnection` | `net.easyconn` 7.0.1 | CarbitLink | Duplication d'ecran Carbit (appli compagnon sur le telephone) |
| `WeLink` | `com.autoai.car.jlink` 1.24.20251104 (uid system) | Jlink | Duplication d'ecran AutoAI WeLink (appli compagnon, QR code) |

Seuls CPLink + CarplayService et Android Auto sont des implementations « officielles » (certifiees). SpeedPlay,
CarbitLink et Jlink sont des alternatives payantes ou sous licence, liees a l'appareil.

## CPLink (CarPlay Autochips)

- **Pile** : `CarplayService` parle a des services natifs du vendor par HIDL : `vendor.autochips.hardware.iap@1.0`
  (`IIAPService`, `IIAPTransport`, `IIAPCarplay` : iAP2 et authentification Apple MFi) et
  `vendor.autochips.hardware.carplayplugin` (`ICarPlayPlugin`, flux audio `IAStream` et video `IVStream`). CPLink est
  l'interface (`CarPlayActivity`, `CarPlayAppService`) ; API cliente `com.autochips.carplay.CarplayManager`
  (activer / desactiver, mode nuit, rappel d'etat : appel, navigation, Siri, flux audio).
- **Certificat** : `ro.atc.carplay.certificate` et `persist.sys.carplay.certificate` (vrais par defaut) ; le certificat
  CarPlay de l'appareil est dans ses partitions (voir « Securite » du README) : ne jamais les publier.
- **Reglages par proprietes** : `ro.atc.carplay.support`, `.support.type`, `.init_resolution`, `.audio_duck_pct` (25),
  `persist.carplay.support.wireless` (vide = filaire et sans fil ; « only support wireless » coupe l'USB),
  `persist.carplay.wirelessCarPlay_2G`, `persist.carplay.autoconnect.enable` (vrai), `persist.carplay.drop.latency`,
  `persist.carplay.v.keyframe`, `persist.carplay.mic.algorithm` (`atc` sur l'unite).
- **Sans fil** : point d'acces Wi-Fi de l'autoradio (`HotSpotUtil`) et Bluetooth.
- **Dependance a ivi-services** : CPLink lui envoie (diffusion reservee au paquet `com.jancar.services`)
  `com.jancar.carplay_connected` / `_disconnect` / `_show` / `_hidden`, `com.jancar.action.CARPLAY_PHONE_START` /
  `_RINGING` / `_END`, `action.android.carplay.send` (`MAIN_AUDIO_START` / `MAIN_AUDIO_STOP`). ivi-services
  (`CarPlayUtil`) alors : coupe le Bluetooth de l'autoradio pendant CarPlay (et le rallume apres), met
  `Settings.Global phoneMode` (`carplay_wried` / `carplay_wireless`) et previent Android Auto
  (`action.phone.mode.change`), met en pause les autres medias, coupe le son 1 s au debut d'un flux, passe le mode
  nuit (phares) a CarPlay par `CarplayManager.setNightMode`, ventilation pendant les appels.

## Android Auto (`com.google.android.projection.sink`)

- C'est le **recepteur Android Auto de Google** (bibliotheque « GAL » : protobuf, transports USB, Wi-Fi et
  Bluetooth, sans fil complet : identifiants Wi-Fi par Bluetooth, Wi-Fi Direct), avec la partie native
  `lib/arm64/libautoreceiver_jni.so` (vide dans la copie analysee : a recopier pour l'etudier). Le code est dans le
  `.vdex` (CompactDex d'Android 9), lu par ses chaines.
- **Integration Jancar** : SDK `com.jancar.sdk.*` (car, bluetooth, audio, radio…), demarrage sur
  `com.jancar.services.ready`, `ACL_CONNECTED` et `action.phone.mode.change`.
- **Diffusions** : `com.google.android.projection.android_auto_start` / `_end` (ivi-services en fait la source media
  active) ; commandes `com.google.android.projection.sink.NIGHT_MODE`, `.GPS`, `.LOCKOUT` ; proprietes
  `persist.auto.wired.connect`, `persist.auto.wireless.connect`, `persist.androidauto.dump.enable`.

## SpeedPlay, CarbitLink, Jlink

- **SpeedPlay** (Suding / Texustek, aussi `com.zjinnova.zlink`, c'est-a-dire ZLink) : CarPlay par sa propre pile iAP2
  (`libSdCarplay.so`, `libcustomiap.so`) avec la puce MFi lue en I2C (`/dev/i2c-%d`,
  `/sys/bus/platform/drivers/mtc-car/mfi`), Android Auto (`libSdAuto.so`, USB AOA), CarLife (Baidu), AirPlay et
  duplication Android (scrcpy). **Licence liee a l'appareil** (uuid MFi, `ro.serialno`, numero de serie eMMC,
  `/sdcard/EasyConnected/License.ini`, `persist.suding.factorytest.activate`) : inutilisable sans activation.
- **CarbitLink** (`net.easyconn`) : duplication de l'ecran du telephone (appli EasyConnection sur le telephone),
  AirPlay, Miracast, DLNA ; licence Carbit.
- **Jlink** (`com.autoai.car.jlink`, AutoAI WeLink) : duplication par appli compagnon et QR code.

## Micro : gain et annulation d'echo (reglages usine)

Dans ivi-settings (`com.jancar.settings` 2.7.4), Reglages usine :
- **Gain micro (AC8257, Android 9)** : `MicGainAdjust8257Activity`, 3 niveaux = `AudioManager.setParameters`
  `MIC1_HW_GAIN=3|4|5` et `MIC2_HW_GAIN=3|4|5` (traites par `AudioALSAHardware` de `audio.primary.ac8257.so`), gardes
  dans `persist.jancar.mic.hw.gain` et reappliques au demarrage par son `FactoryService` (le HAL ne les garde pas).
  Valeur relevee sur l'unite : `MIC1_HW_GAIN=3` (niveau 1). L'autre ecran (`MicGainAdjustActivity`, curseur 0-50 dans
  `/sys/.../rk817-codec/micgain`) est pour le RK3326, pas pour cette unite.
- **ECNR** (`EchoNoiseSetActivity`) : `persist.audiohal.third_ecnr_lib.enable` et `vendor.audiohal.third_ecnr_lib.enable`
  = 0 ou 1 (bibliotheque tierce d'annulation d'echo / reduction de bruit du HAL).
- LibreHU-service les reprend (Audio → Microphone, `Microphone.kt`) : meme parametre et meme propriete, reapplique a
  chaque demarrage, sans ivi-settings.

## Avec LibreHU-service (sans ivi-services)

- CPLink et Android Auto parlent a leurs propres services (CarplayService et HIDL, bibliotheque native de Google) :
  la projection elle-meme ne depend pas d'ivi-services, mais **a tester** : Android Auto attend aussi
  `com.jancar.services.ready` pour certains demarrages.
- Ce qu'ivi-services faisait et qui manquerait : couper le Bluetooth de l'autoradio pendant CarPlay, `phoneMode`,
  pause des autres medias, mode nuit de CarPlay. Les diffusions de CPLink sont reservees a `com.jancar.services` ;
  la piste est l'API `CarplayManager` de `CarplayService` (rappel d'etat, mode nuit) et, pour Android Auto, ses
  diffusions `android_auto_start` / `_end` et `NIGHT_MODE`.
- Alternative libre : Open Headunit (ex-Headunit Revived, AGPL-3.0) pour Android Auto ; pour CarPlay, rien de libre
  d'utilisable (authentification Apple obligatoire).
