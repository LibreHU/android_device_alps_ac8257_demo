# Changelog

## Non publie

### Nouveau
- **Sources GPL du noyau** (`docs/kernel_gpl.md`) : paquet `kernel-4.9.tgz` recu de SIXWIN / Jancar le 19/10/2026,
  compare au noyau stock #72 : base Autochips `ac8257_demo` (428 / 435 options), sans les pilotes Jancar
  (`CONFIG_JANCAR_SOLUTION`, `CONFIG_JANCAR_GPIOS`, tactile FTS / Synaptics TCM2, capteur `tp9963`, overlay `UJC201_64`).
- **Noyau #72** : `prebuilt/kernel` = noyau stock de la mise a jour officielle Jancar de janvier 2026 (#72 du
  22/01/2026, patch `want_initramfs`, celui de TWRP v7) ; configuration, exports et CRC identiques a #25.
- **Ethernet et partage de connexion USB** (`docs/ethernet.md`, `tools/usbnet/`) : modules pour le noyau stock
  (Realtek RTL8152 / RTL8153, RNDIS pour le partage d'un telephone Android, iPhone, LAN78xx, SMSC, DM9601, SR9700 /
  SR9800, MCS7830, CH9200, RTL8150, Pegasus, CDC EEM), verifies contre les CRC stock ; zip flashable `usb-net`
  (LibreHU-flashablesZips, categorie Noyau).
- **Audio : musique muette** (`tools/audio/no_deep_buffer.sh`, `docs/audio_deep_buffer.md`) : retire la sortie
  `deep_buffer` (PCM MultiMedia2, muette sur l'unite) de `audio_policy_configuration.xml` pour faire passer la
  musique par `primary`. Sauvegarde, verification et retour arriere (`restore`).

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
