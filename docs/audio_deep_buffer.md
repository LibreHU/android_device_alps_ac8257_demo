# Musique muette, sonneries OK : retirer la sortie `deep_buffer`

## Symptome
Sur l'UJC201 (AC8257, Android 9), toute la musique est muette (lecteur, Android Auto, radio FM), alors que les
sonneries et les clics du clavier s'entendent. ViPER4Android coupe ou non : aucun changement.

## Diagnostic (`dumpsys media.audio_flinger`)
Android ouvre deux sorties vers la meme carte son :

| Sortie | PCM ALSA | Blocs | Utilisee pour | Resultat |
|---|---|---|---|---|
| `primary` (`AUDIO_OUTPUT_FLAG_PRIMARY\|FAST`) | `pcm0` MultiMedia1 | 1024 trames | sonneries, clavier | son OK |
| `deep_buffer` (`AUDIO_OUTPUT_FLAG_DEEP_BUFFER`) | `pcm3` MultiMedia2 | 2048 trames | musique (par defaut) | muet |

Les trames sont bien ecrites et `pcm3p` est `RUNNING` : le son se perd apres Android, sur le chemin MultiMedia2.

`deep_buffer` ne sert qu'a economiser la batterie (gros blocs, moins de reveils CPU) au prix de la latence
(commits AOSP : [deep audio buffers](https://gerrit.omnirom.org/plugins/gitiles/android_frameworks_av/+/1948eb3ea6eee336e8cdab9b0c693f93f5f19993%5E%21),
[deep buffer par defaut pour la musique](https://android.googlesource.com/platform/frameworks/av/+/439e4ed)).
Inutile sur un autoradio.

## Contournement
Sans `deep_buffer` dans `audio_policy_configuration.xml`, la musique passe par `primary`. Les effets globaux
(ViPER4Android, session 0) suivent la sortie de la musique et fonctionnent sur `primary`.

```
tools/audio/no_deep_buffer.sh apply     # sauvegarde (/sdcard/librehu-audio + copie locale), modifie, verifie
adb reboot
tools/audio/no_deep_buffer.sh status    # deep_buffer : 0, une seule sortie (AudioOut_D) dans audio_flinger
tools/audio/no_deep_buffer.sh restore   # retour au fichier d'origine
```
Il faut `adb root` et `/vendor` inscriptible (`adb disable-verity`, redemarrage, `adb remount`).

Sans `adb root` (ROM `user` d'origine) : zips TWRP `ujc201_nodeepbuffer_install.zip` / `_restore.zip`
(`tools/audio/twrp/build.sh`, voir le README) ; ils s'arretent sans rien modifier si `/vendor` est sous dm-verity.
Le fichier est reecrit sur place (`cat > fichier`) pour garder son label SELinux.

Effet de bord : traitement par blocs de 1024 trames, donc un peu plus de charge CPU pour les effets lourds
(Convolver avec un long IRS, reverberation).
