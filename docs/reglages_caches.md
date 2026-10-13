# Reglages caches de la ROM stock UJC201

Trouves dans `priv-app/MtkSettings/MtkSettings.apk` (paquet `com.android.settings`, Reglages MediaTek modifies par
Autochips), `system/app` et la partition `jancar`. Ouvrir une activite depuis un PC :
`adb shell am start -n <paquet>/<activite>`.

## ATC Settings (Autochips), dans les Reglages Android
`adb shell am start -n com.android.settings/com.autochips.atcsettings.mainui.MainActivity`
(declaree `MAIN` / `LAUNCHER`, mais pas affichee par le lanceur Jancar). Quatre onglets :

| Onglet | Reglages | Stockage |
|---|---|---|
| Ecran (`DisplayFragment`) | source de la camera de recul (CVBS / MIPI-AHD), image arriere, AVM rapide, AVM sur CVBS, nettete, tramage (dither), retro-eclairage, **recadrage de l'image de recul** (x, y, largeur, hauteur, `BackcarFragment`), miroir, « generate MDP » (`BackCar.updateArm2MdpSetting`) | **metazone** (lue par le LK et l'ARM2 du recul rapide) |
| Audio (`AudioFragment`, `AtcAudioSettings`) | graves / medium / aigus (niveau, frequence centrale, Q), loudness (frequence, accentuation des aigus, attenuation), balance / fader (attenuateurs par voie), volume pendant le recul | `com.autochips.audiosettings.AudioSettings` (puce audio des cartes Autochips de reference ; sur l'UJC201 la puce est un BD37534 pilote par ivi-services : effet reel a verifier) |
| Logo (`LogoFragment`) | logo de demarrage depuis une cle USB / la memoire (redimensionne a l'ecran) | partition logo / metazone |
| Autre (`OtherFragment`, `SensorBusFragment`) | mode USB (hote / peripherique, active adb), **Engineer Mode**, mode avion du demarrage rapide (QB), mode capteur AHD / AVM | `Settings.Global`, metazone |

Adresses metazone (`AtcMetazone.readval/writeval`, puis `flush`) :

| Adresse | Valeur |
|---|---|
| 65588 / 65600 | miroir (selon la source : CVBS / AHD) |
| 65594..65597 / 65601..65604 | recadrage x, y, largeur, hauteur (selon la source) |
| 65598 | nettete |
| 65599 | tramage |
| 65605 | mode camera AHD |
| 65606 | mode camera AVM |
| 65607 | source du recul |
| 65608 | AVM rapide |
| 65611 | AVM sur CVBS |
| 65634 | mode capteur AHD |
| 65635 | mode capteur AVM |

## Engineer Mode MediaTek
`adb shell am start -n com.mediatek.engineermode/.EngineerMode` (`system/priv-app/EngineerMode`), aussi via l'onglet
Autre d'ATC Settings. Menus materiel dont **Audio** (volumes par mode et par sortie, amelioration de la parole,
journaux du HAL) : utile pour l'etude de l'audio, a manier avec precaution (les valeurs vont dans les parametres
NVRAM / `audio_param`).

## ATCLogger
`com.autochips.atclogger/.MainActivity` (`system/app/ATCLogger`) : journaux Android / noyau / modem sur la
carte memoire.

## Configuration Jancar (partition `jancar`, `/jancar/config`)
`ivi-customer.ini` (options client : `CameraType`, `BackCarVideoSource`, volumes par defaut et de recul…),
`ivi-config.ini` (index des cameras Android, canaux AV / audio, courbe de volume `BD37534VolumeCurve`, touche MODE,
volume CCD), `ivi-settings.ini` (reglages Jancar et leur visibilite : `CCDCamera`, `CCDCameraLine` lignes de recul,
miroirs, tension CCD…), `can_config.json`, `ivi-radio-cfg.ini`, `pointercal-*.xml` (calibration tactile).
Voir aussi [LibreHU-service/docs/ivi-services/10-config.md](https://github.com/LibreHU/LibreHU-service/blob/main/docs/ivi-services/10-config.md).
