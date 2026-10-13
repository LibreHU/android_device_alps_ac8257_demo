# Ethernet sur l'UJC201 (AC8257, Android 9)

Pas de port Ethernet sur la carte : seulement par un adaptateur **USB Ethernet** sur un port USB en mode hote.
Analyse du noyau stock (`prebuilt/kernel`, Linux 4.9.117+, configuration lue dans l'image : `IKCONFIG`, aussi dans
`/proc/config.gz` sur l'unite) et des sources d'Android 9.

## Noyau : pilotes presents (integres, `=y`)

| Puce de l'adaptateur | Pilote | Etat |
|---|---|---|
| ASIX AX88179 / AX88178A (USB 3, gigabit) | `ax88179_178a` | **Oui** |
| ASIX AX88772 / AX88772B / AX8817x (USB 2, 100 Mb/s) | `asix` (`CONFIG_USB_NET_AX8817X`) | **Oui** |
| Adaptateurs « CDC Ethernet » (ECM) et CDC NCM generiques | `cdc_ether`, `cdc_ncm` | **Oui** |
| Realtek RTL8152 / RTL8153 (la plupart des adaptateurs bon marche, Anker, UGREEN…) | `r8152` | **Non** : `CONFIG_USB_RTL8152` absent, et en 4.9 `cdc_ether` refuse expres les Realtek `0bda:8152` / `0bda:8153` en mode ECM |
| Telephone Android en partage USB (RNDIS) | `rndis_host` | **Non** (`CONFIG_USB_NET_RNDIS_HOST` absent) |
| iPhone en partage USB | `ipheth` | **Non** (`CONFIG_USB_IPHETH` absent) |
| Davicom, SMSC, Microchip LAN78xx, Pegasus… | divers | Non |

`usbnet` nomme `eth0` les adaptateurs Ethernet (drapeau `FLAG_ETHER`).

## Android 9 : prise en charge par le systeme

- `SystemServer` demarre `EthernetService` si l'appareil declare `android.hardware.ethernet` **ou**
  `android.hardware.usb.host`.
- `EthernetTracker` prend les interfaces qui correspondent a `config_ethernet_iface_regex` (`eth\d` par defaut) : DHCP
  automatique, reseau « Ethernet » dans ConnectivityService (icone dans la barre d'etat).
- Pas d'ecran Ethernet dans les Parametres d'Android 9 AOSP ; l'IP fixe passe par l'API cachee `EthernetManager`
  (permission systeme) ou `config_ethernet_interfaces`.

A verifier sur l'unite :
```
pm list features | grep -iE "usb.host|ethernet"     # une des deux = EthernetService demarre
dumpsys ethernet                                      # present si le service tourne
zcat /proc/config.gz | grep -E "USB_NET|RTL8152"      # meme config que ci-dessus
ip link ; lsusb 2>/dev/null || cat /sys/bus/usb/devices/*/idVendor
```
Si aucune des deux features n'est declaree : ajouter `android.hardware.ethernet` dans
`/system/etc/permissions/` (fichier XML `<permissions><feature name="android.hardware.ethernet" /></permissions>`),
puis redemarrer.

## Ajouter les adaptateurs Realtek et le partage USB du telephone

Il faut les pilotes `r8152`, `rndis_host` (et `ipheth`) en modules `.ko` charges au demarrage. Contrainte : le noyau
stock a `CONFIG_MODVERSIONS=y` (vermagic `4.9.117+ SMP preempt mod_unload modversions aarch64`, pas de signature
de modules) : un module doit etre compile sur une source identique, avec les CRC des symboles du noyau stock. Piste :
la source reconstruite (`android_kernel_autochips_ac8257_4.9`) et un `Module.symvers` refait depuis les tables
`__kcrctab` de l'image stock ; risque si MediaTek a modifie des structures reseau (`sk_buff`, `net_device`). A
tester d'abord avec `insmod` a la main, jamais au demarrage avant d'avoir valide.

## Sources
- Linux 4.9 : [drivers/usb/core/generic.c](https://github.com/torvalds/linux/blob/v4.9/drivers/usb/core/generic.c)
  (choix de la configuration USB), [drivers/net/usb/cdc_ether.c](https://github.com/torvalds/linux/blob/v4.9/drivers/net/usb/cdc_ether.c)
  (Realtek exclus), [drivers/net/usb/usbnet.c](https://github.com/torvalds/linux/blob/v4.9/drivers/net/usb/usbnet.c)
  (nom `eth%d`), [drivers/net/usb/ax88179_178a.c](https://github.com/torvalds/linux/blob/v4.9/drivers/net/usb/ax88179_178a.c).
- Android 9 : [SystemServer.java](https://github.com/aosp-mirror/platform_frameworks_base/blob/pie-release/services/java/com/android/server/SystemServer.java)
  (demarrage d'EthernetService), [config.xml](https://github.com/aosp-mirror/platform_frameworks_base/blob/pie-release/core/res/res/values/config.xml)
  (`config_ethernet_iface_regex`).
