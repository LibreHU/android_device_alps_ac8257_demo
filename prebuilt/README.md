# prebuilt/

`kernel` : noyau stock Jancar `4.9.117+ #72` (mise a jour officielle UJC201-V1.151R6-260122, 22/01/2026, compile par
`jac0416@jacx` avec AOSP clang 6.0.2), `Image.gz-dtb` avec le DTB stock en fin de fichier.

C'est le noyau de la branche `twrp` **remis dans son etat stock** : pour TWRP, la chaine `skip_initramfs` y est
remplacee par `want_initramfs` (le LK ajoute `skip_initramfs` hors mode recovery) ; ici elle est remise a
`skip_initramfs`, le seul octet change, pour que le demarrage normal se fasse en system-as-root comme le stock.
Image recompressee (gzip -9), DTB inchange (memoire reservee identique aux noyaux #25 et #72).

- SHA-256 de l'`Image` decompressee : `a42980735b4ebed8dc046d3016a64378f89c6ffa804be4a91d6b63b7af14ad6e`

Pas de `dtbo.img` : la partition `dtbo` stock est gardee.

`kernel-librehu` et `modules/` (non versionnes) : **noyau LibreHU** de la branche `experimental-4.19.325` de
[android_kernel_autochips_ac8257_4.9](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9) (Linux
4.19.325, pilotes Autochips portes, KernelSU Next), variante `a10-lto32` (Android 10, ThinLTO) depuis le 19/11/2026
(`a10` le 18/11) : `Image.gz-dtb_a10-lto32` de sa release `latest-experimental-4.19.325`. Wi-Fi / BT / GPS / FM sont
integres a ce noyau : `modules/` n'a aucun `.ko`, seulement `SHA256SUMS` (vide), `BUILTIN`, `kernel_version` (banniere
de l'Image) et `release.txt` ; l'installateur du zip et `tools/vendor_add_conn_modules.sh` ne touchent alors pas a
`/vendor/lib/modules`. Ecrits par `tools/fetch_kernel.sh` (`tools/fetch_kernel.sh stable-4.9.337` : noyau 4.9 de
10 Mio et ses six modules de connectivite).

`boot-librehu-bootmenu.img` et `boot-librehu.img` (non versionnes) : **images de boot de 32 Mio** de la meme release
(`boot_ac8257_bootmenu_a10-lto32.img`, avec le menu TWRP / Android / Fastboot, et `boot_ac8257_a10-lto32.img`),
ecrites par `tools/fetch_kernel.sh` apres verification (en-tete Android, 32 Mio exactement, pied AVB, noyau = celui de
l'Image). La partition boot d'origine fait 10 Mio : `BoardConfig.mk` declare 32 Mio
(`BOARD_BOOTIMAGE_PARTITION_SIZE`), et le zip de la ROM migre la partition d'abord si besoin.

`boot32/librehu_boot32_twrp.zip` (non versionne) : zip de la release du noyau qui passe la partition boot de 10 a
32 Mio (dtbo / tee deplaces, vendor 2048 -> 2033 Mio, sauvegardes dans `/sdcard/LibreHU/boot32`, retour :
`librehu_boot32_restore_twrp.zip`). `tools/make_flashable_zip.py` le met dans le zip de la ROM (empreinte dans
`info/SHA256SUMS`) ; l'installateur le lance quand la partition fait encore 10 Mio, puis fait redemarrer TWRP (son
noyau ne relit la table qu'au demarrage) et se reprogramme. Le TWRP LibreHU l'a aussi en entree de menu (Avance).
`BoardConfig.mk` prend la premiere telle quelle (`TARGET_NO_KERNEL` + `BOARD_PREBUILT_BOOTIMAGE` ;
`LIBREHU_BOOT_IMAGE=plain` pour la seconde) : elles ont l'en-tete, la ligne de commande et le **pied AVB du boot
stock** (`AVBf`, vbmeta chaine du boot), sans lequel le LK refuse l'image, deverrouille ou non (l'unite redemarre au
logo sans journal du noyau : `tools/ac8257/repack_boot.py` du depot du noyau). Un `boot.img` construit par LineageOS
(`BOARD_AVB_ENABLE := false`) n'a pas ce pied. Le zip `mka bacon` reprend cette image (`IMAGES/boot.img`).
Le noyau stock #72 (`kernel`) n'est plus utilise par le build : il n'y a pas d'image de boot stock a publier.

`viper/` (non versionne) : **pilote ViPERFX_RE** v2.1.2 ([likelikeslike/ViPERFX_RE](https://github.com/likelikeslike/ViPERFX_RE),
module officiel non-AIDL, GPL-2.0) : `libv4a_re_armeabi-v7a.so`, `libv4a_re_arm64-v8a.so`, `LICENSE`, `SOURCE`,
`version`, `SHA256SUMS`, ecrits par `tools/fetch_viper.sh` (SHA-256 du module verifie). Meme version que l'appli
ViPER4Android LibreHU de la ROM. Le zip TWRP (`tools/make_flashable_zip.py`) les emporte dans `viper/` : son
installateur met le pilote dans `/vendor/lib[64]/soundfx` et le declare dans les `audio_effects` de vendor.
