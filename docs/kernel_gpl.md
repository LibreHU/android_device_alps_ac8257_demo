# Sources GPL du noyau (reponse Jancar / SIXWIN du 19/10/2026)

Suite a la demande formelle GPLv2 (section 3 : « source complet correspondant »), le distributeur SIXWIN a envoye
le 19/10/2026 un lien OneDrive vers les sources du noyau de l'UJC201 (Linux 4.9.117+).

## Le paquet
- Fichier : `kernel-4.9.tgz`, 156 599 414 octets, SHA-256
  `f0303951aed4ed65eef9da7fdaf0718c50d019f5c956429dc4cdb5cb7d83c577`.
- Contenu : un dossier `kernel-4.9/` (65 641 entrees, 840 Mo decompresse), `Makefile` 4.9.117, arbre Android
  (`Android.mk`, `kenv.mk`, `build.config.*`), `verity_dev_keys.x509` (cle publique de test AOSP).
- Configs AC8257 : `arch/arm64/configs/ac8257_{car,demo,evb,jac}[_debug]_defconfig` et
  `arch/arm/configs/ac8257_demo_1g_32[_debug]_defconfig` ; device trees `arch/arm64/boot/dts/mediatek/ac8257*.dts`.
- Plateforme Autochips presente : `drivers/misc/autochips/` (`metazone`, `tvd`, `avin`, `backcar`,
  `n4_video_decoder`, `dualarm`, `arm2_log`, `nr`, `wch`, `di`, `rsv_cpu`, `boot_state`), affichage
  `drivers/misc/mediatek/video/ac8257/` (dont l'ecran externe `ext_disp` / multidisp), capteurs `tp2850`, `tp2854`,
  `tp2855`, `n4`.

## Comparaison avec le noyau stock (#72)
Methode : config integree au noyau stock (`IKCONFIG`, extraite de `prebuilt/kernel`) comparee en texte aux
defconfigs et aux symboles des `Kconfig` du paquet (rien n'a ete compile ni execute depuis le paquet).

- Bannieres : stock `4.9.117+ (jac0416@jacx) ... clang 6.0.2 (r316199) #72 SMP PREEMPT Thu Jan 22 2026`.
- `ac8257_demo_defconfig` est la base : 428 des 435 options identiques. Les 7 ecarts sont les reglages du produit
  (le stock vaut) : `CONFIG_BUILD_ARM64_DTB_OVERLAY_IMAGE_NAMES` (`mediatek/UJC201_64`), capteurs
  (`tp2850_yuv tp2854_yuv tp9963_yuv`), ecran `CONFIG_LCM_WIDTH/HEIGHT` (1024 x 600), `CONFIG_SND_SOC_ATC` (non).
  `ac8257_jac_defconfig` donne 427 / 435.
- **Absent du paquet** (actif dans le noyau stock, sans `Kconfig` ni source dans le paquet) :
  - `CONFIG_JANCAR_SOLUTION`, `CONFIG_JANCAR_GPIOS` : les pilotes propres a Jancar ; le mot « jancar »
    n'apparait dans aucun fichier source du paquet ;
  - `CONFIG_TOUCHSCREEN_FTS` (FocalTech), `CONFIG_TOUCHSCREEN_SYNA_TCM2`, `CONFIG_TOUCHSCREEN_SYNA_TCM2_I2C`
    (Synaptics) : pilotes tactiles ;
  - overlay de device tree `mediatek/UJC201_64` ;
  - pilote du capteur `tp9963_yuv` (decodeur video AHD / CVBS).

Conclusion : c'est le noyau Autochips de reference de la plateforme, presque identique en configuration, **sans les
ajouts Jancar**. Un noyau compile depuis ce paquet ne gererait ni le tactile, ni les GPIO Jancar, ni la camera
`tp9963`, ni la description materielle de l'UJC201 : pas de noyau de remplacement pour l'instant.

## Ce que le paquet apporte deja
- Les pilotes de plateforme a lire au lieu de desassembler : metazone (`metazone_drv.c`, format de la partition),
  entree video (`tvd`, `avin`), recul (`backcar`), ecran externe (`mtk_disp_mgr.c`, `g_open_ext_disp`), ARM2.
- Des en-tetes et une config exacts pour compiler des modules (`tools/usbnet/` compile aujourd'hui contre un 4.9.117
  standard puis verifie les CRC du stock).

## Suite
- Redemander a SIXWIN / Jancar les parties manquantes, nommees ci-dessus (la GPLv2 couvre tout le code compile dans
  le noyau distribue, pilotes Jancar inclus) : sources de `CONFIG_JANCAR_SOLUTION` et `CONFIG_JANCAR_GPIOS`, des
  pilotes tactiles FTS / Synaptics TCM2, du capteur `tp9963`, du device tree `UJC201_64`, et la defconfig utilisee
  pour le #72.
- Garder une copie du paquet (les liens OneDrive partages expirent) ; la GPL permet de le redistribuer.
- Aucun flash de noyau n'est automatise : il demande vbmeta sans verification, fait a la main
  (`fastboot --disable-verity flash vbmeta vbmeta.img`).
