# Changelog

## Non publie

### Corrige
- **Touches au volant d'un boitier CAN ignorees** (Clio 3 et autres voitures avec boitier Hiworld) : touchfix ne
  lisait que la trame MCU `0x20` (volant cable en direct). Les touches du boitier arrivent dans les trames `0x10`
  (octets du boitier relayes par le MCU) : elles sont maintenant decodees (trame Hiworld `5A A5 LEN CMD .. CS`,
  message `0x11`, comme `HiworldWheelKeys` de LibreHU-service) et passent par le canal 7 (table, apprentissage,
  fenetres). Table par defaut LNP002 si la touche n'est pas apprise. La build 10 avait bien keynav (journal de la
  CI : `pages.cpp (keynav, 19 types d'elements)`) mais aucune touche ne lui parvenait sur ces voitures. Son tag
  etait pose sur la branche par defaut `twrp` (`a8e89d3`) alors que l'image venait de `f8bb3d0` : corrige ci-dessous.
- **Version visible** : `TW_DEVICE_VERSION` = `UJC201-b<build>-<commit>` (affiche par TWRP au demarrage) et
  `ro.librehu.twrp` dans `prop.default` (`--version` de `ujc201_postprocess.py`) ; release taguee sur le commit
  construit (`target_commitish`), branche et commit dans son titre et ses notes.

### Nouveau
- **TWRP entier aux touches au volant** (`tools/keynav/keynav.inc`, insere dans `gui/pages.cpp`) : cadre sur
  l'element actif, VOL-/VOL+ = suivant / precedent, fleches (PREV / NEXT, molette) = voisin, MUTE = appui ; listes
  (lignes, pages), texte et console (defilement), curseurs, clavier a l'ecran, glissieres de confirmation (OK deux
  fois). Apprentissage : PREV et NEXT en plus. A tester sur l'unite.
- **Noyau #72** : `prebuilt/kernel` = noyau stock de la mise a jour officielle Jancar de janvier 2026 (#72 du
  22/01/2026, patch `want_initramfs`) ; `prebuilt/dtbo.img` et vbmeta du recovery 2026 ; configuration, exports et
  CRC identiques a #25.
- **fstab** : entree `System Image` (sauvegarde / restauration brute de `system`) en plus de « System (fichiers) ».
- **BCB** : `tools/apply_twrp_patches.py` replie le message bootloader sur la partition `para` quand la fstab n'a pas
  `/misc` (eviter de rester dans TWRP apres une reinitialisation d'usine) ; a confirmer sur l'unite.

### Deplace
- Le depot ne garde que l'arbre TWRP (19/10/2026). Notes de l'appareil et de la ROM stock (sources GPL du noyau,
  Ethernet, audio, video, projection, reglages caches, tester un noyau, /system, applis LibreHU) et outils `usbnet`,
  `audio`, `dump` : depot noyau
  [android_kernel_autochips_ac8257_4.9](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9)
  (`docs/ujc201/`, `tools/ac8257/`). MCU (`docs/mcu_firmware.md`, `tools/mcu/`, appli JacMCU) :
  [MCU-tools-app](https://github.com/LibreHU/MCU-tools-app).

## v1.1 — depuis 3.7.1_12 (`858a3c4`)

Teste sur l'appareil : menu de demarrage, tableau de bord, barre d'etat, frein a main, sortie console des menus.
A valider : bandeau / fenetres, synchro horloge, touches au volant (aucune trame `0x20` capturee pour l'instant).

### Nouveau
- **Menu de demarrage** (`boot.img`, `tools/bootmenu/`) : TWRP / Android / Fastboot, Material aux couleurs TWRP,
  demarrage automatique sur Android apres 3 s, tactile + touches HOME (Android) / BACK (TWRP) du bandeau.
  Noyau stock (`skip_initramfs` -> `want_initramfs`), footer AVB stock. Retour : `fastboot flash boot <boot stock>`.
- **MCU Jancar** (`/dev/ttyS1`, protocole JAC_V1) lu par `touchfix` : ACC, frein a main (requete `F0 04 00` au
  demarrage), feux (ILL), version du firmware, heure ; `PC_READY` (`1F 01`) envoye au demarrage ;
  journal des trames dans `/tmp/mcu.log`.
- **Barre d'etat** : `ACC ON   HB ON   LIGHTS OFF` a droite.
- **Advanced > Vehicle / MCU dashboard** : tension d'entree et CPU (valeurs + jauges), pastilles ACC / frein /
  feux, version et horloge MCU, trames recues, derniere touche au volant, boutons d'apprentissage.
- **Advanced > MCU info** : version du firmware MCU, etat vehicule, heure MCU.
- **Alertes** : feux allumes (8 s), feux allumes + contact coupe (permanente), touche au volant, invite
  d'apprentissage. Bandeau sur la barre de navigation ; cartes flottantes si `gui/pages.cpp` est patche.
- **Touches au volant** : trames `0x20` -> peripherique uinput `ujc201-wheel`, table `ujc201_keys.conf`
  (`/data/media/0/TWRP/`), apprentissage Advanced > *Steering wheel keys: learn* (VOL+ VOL- MUTE MODE BACK).
  Actions : `volup voldown enter back home power up down left right bl+ bl- none`.
- **Horloge** reglee sur l'heure du MCU (fuseau TWRP avec le patch `pages.cpp`, sinon correction de derive).

### Modifie
- Menus Advanced (Power info, MCU info, touches au volant, USB) : la sortie du script s'affiche dans la console
  (`terminalcommand` ; `cmd` n'affichait rien).
- Valeurs du theme passees par des proprietes systeme `ujc201.*` (`%property.ujc201.<nom>%`) : tableau de bord,
  barre d'etat et bandeau fonctionnent sans recompiler TWRP (`ujc201_postprocess.py` suffit).
- Power info : lignes MCU firmware et Vehicle.
- `tools/ujc201_theme.py` : ajouts au theme partages entre le patch source et le post-traitement.

### Technique
- `touchfix` : 9 Ko -> 33 Ko (MCU, setprop natif, uinput volant, fenetres) ; toujours sans libc.
- `apply_twrp_patches.py` : `gui/pages.cpp` (fenetres + horloge), theme via `ujc201_theme.py`.
- Nouveaux scripts : `mcuinfo`, `wheelkeys` ; nouvelle table par defaut `system/etc/ujc201_keys.conf` (vide).
