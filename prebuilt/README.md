# prebuilt/

`kernel` : noyau stock Jancar `4.9.117+ #72` (mise a jour officielle UJC201-V1.151R6-260122, 22/01/2026, compile par
`jac0416@jacx` avec AOSP clang 6.0.2), `Image.gz-dtb` avec le DTB stock en fin de fichier.

C'est le noyau de la branche `twrp` **remis dans son etat stock** : pour TWRP, la chaine `skip_initramfs` y est
remplacee par `want_initramfs` (le LK ajoute `skip_initramfs` hors mode recovery) ; ici elle est remise a
`skip_initramfs`, le seul octet change, pour que le demarrage normal se fasse en system-as-root comme le stock.
Image recompressee (gzip -9), DTB inchange (memoire reservee identique aux noyaux #25 et #72).

- SHA-256 de l'`Image` decompressee : `a42980735b4ebed8dc046d3016a64378f89c6ffa804be4a91d6b63b7af14ad6e`

Pas de `dtbo.img` : la partition `dtbo` stock est gardee.

Plus tard : noyau LibreHU construit depuis
[android_kernel_autochips_ac8257_4.9](https://github.com/LibreHU/android_kernel_autochips_ac8257_4.9) (branche
`LibreHU-main`, sources GPL Autochips).
