# prebuilt/

`kernel` : noyau stock Jancar `4.9.117+ #72` (mise a jour officielle UJC201-V1.151R6-260122, 22/01/2026, compile par
`jac0416@jacx` avec AOSP clang 6.0.2), `Image.gz-dtb` avec le DTB stock en fin de fichier.

C'est le noyau de la branche `twrp` **remis dans son etat stock** : pour TWRP, la chaine `skip_initramfs` y est
remplacee par `want_initramfs` (le LK ajoute `skip_initramfs` hors mode recovery) ; ici elle est remise a
`skip_initramfs`, le seul octet change, pour que le demarrage normal se fasse en system-as-root comme le stock.
Image recompressee (gzip -9), DTB inchange (memoire reservee identique aux noyaux #25 et #72).

- SHA-256 de l'`Image` decompressee : `a42980735b4ebed8dc046d3016a64378f89c6ffa804be4a91d6b63b7af14ad6e`

Pas de `dtbo.img` : la partition `dtbo` stock est gardee.

`kernel-librehu` et `modules/` (non versionnes) : **noyau LibreHU** de la branche `stable-4.9.337` de
[android_kernel_autochips_ac8257_4.9](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9) (sources GPL
Autochips, correctifs linux-stable jusqu'a 4.9.337, KernelSU Next), `Image.gz-dtb` de sa release
`latest-stable-4.9.337`, et ses six modules de connectivite (`wmt_drv`, `wmt_chrdev_wifi`, `wlan_drv_gen4m`,
`bt_drv`, `gps_drv`, `fmradio_drv`, avec `SHA256SUMS`, `kernel_version` et `release.txt`), ecrits par
`tools/fetch_kernel.sh`. Les modules vont dans l'image vendor (`tools/vendor_add_conn_modules.sh`), ce noyau
refusant ceux du stock.

`boot-librehu-bootmenu.img` et `boot-librehu.img` (non versionnes) : **images de boot** de la meme release
(`boot_ac8257_bootmenu.img`, avec le menu TWRP / Android / Fastboot, et `boot_ac8257.img`), ecrites par
`tools/fetch_kernel.sh` apres verification (en-tete Android, 10 Mio au plus, pied AVB, noyau = celui des modules).
`BoardConfig.mk` prend la premiere telle quelle (`TARGET_NO_KERNEL` + `BOARD_PREBUILT_BOOTIMAGE` ;
`LIBREHU_BOOT_IMAGE=plain` pour la seconde) : elles ont l'en-tete, la ligne de commande et le **pied AVB du boot
stock** (`AVBf`, vbmeta chaine du boot), sans lequel le LK refuse l'image, deverrouille ou non (l'unite redemarre au
logo sans journal du noyau : `tools/ac8257/repack_boot.py` du depot du noyau). Un `boot.img` construit par LineageOS
(`BOARD_AVB_ENABLE := false`) n'a pas ce pied. Le zip `mka bacon` reprend cette image (`IMAGES/boot.img`).
Le noyau stock #72 (`kernel`) n'est plus utilise par le build : il n'y a pas d'image de boot stock a publier.
