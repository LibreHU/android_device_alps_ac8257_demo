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
`tools/fetch_kernel.sh`. Quand `kernel-librehu` existe, `BoardConfig.mk` le prend a la place de `kernel` ; les modules
vont alors dans l'image vendor (`tools/vendor_add_conn_modules.sh`), ce noyau refusant ceux du stock.
