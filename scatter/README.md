# Scatters SP Flash Tool / SP Flash Tool scatters — Jancar UJC201 (AC8257)

*English below.*

Scatters de l'UJC201 (AutoChips AC8257, plateforme `MT6761`, projet `ac8257_demo`) pour chaque taille d'eMMC et les
deux tables de la partition boot :

| Fichier | eMMC | userdata (`partition_size`) | Disque (octets) | Origine de la taille de userdata |
|---|---|---|---|---|
| `AC8257_16GB_boot10MiB_Android_scatter.txt` / `…boot32MiB…` | 16 Go | `0x1E60FBE00` | `0x389C00000` | **estimée** (95 % de 16 Go) |
| `AC8257_32GB_boot10MiB_Android_scatter.txt` / `…boot32MiB…` | 32 Go | `0x5700FBE00` | `0x713C00000` | **estimée** (95 % de 32 Go) |
| `AC8257_64GB_boot10MiB_Android_scatter.txt` / `…boot32MiB…` | 64 Go | `0xCC3CFBE00` | `0xE67800000` | **déduite** d'un scatter réel AC8259 4/64 (Junsun V1 Pro, même projet `ac8257_demo`) |
| `AC8257_128GB_boot10MiB_Android_scatter.txt` / `…boot32MiB…` | 128 Go | `0x1B7A4FBE00` | `0x1D1E000000` | **exacte** (UJC201 6/128, eMMC `0xdf` / `128SV8`, 244 252 672 secteurs) |
| `AC8257_256GB_boot10MiB_Android_scatter.txt` / `…boot32MiB…` | 256 Go | `0x36FC0FBE00` | `0x389FC00000` | **estimée** (95 % de 256 Go) |

Seules deux choses changent d'un fichier à l'autre ; tout le reste est l'octet près le scatter d'une UJC201 (WwR MTK
2.50, 44 entrées, fins de ligne CRLF) :

- **`boot10MiB`** = table d'origine ; **`boot32MiB`** = table de `librehu_boot32_twrp.zip` (dépôt du noyau 4.19,
  release `latest-rc-4.19.325`) : boot `0x1F200000` / **`0x2000000`**, dtbo **`0x21200000` / `0x100000`**,
  tee1 **`0x21300000`**, tee2 **`0x21800000`**, vendor **`0x21F00000` / `0x7F100000`** (2033 Mio). system et la suite
  ne bougent pas.
- **taille de l'eMMC** = taille de userdata, la dernière partition (elle commence à `0x1A0000000` et finit
  `0x3B04200` octets avant la fin du disque, là où commencent otp, flashinfo et la GPT de secours).

### À lire avant de s'en servir

- **La taille réelle d'une eMMC varie** même à capacité égale : deux UJC201 « 128 Go » mesurées ont 12 Mio d'écart
  (puces différentes). La valeur de userdata n'est exacte que pour l'unité mesurée ; 16, 32 et 256 Go sont des
  estimations prudentes (95 % de la capacité, sous les 96,7 à 97,7 % mesurés sur les puces connues). Taille de la vôtre, dans TWRP : `cat /sys/block/mmcblk0/size`
  (secteurs de 512 octets), puis **userdata = secteurs × 512 − 0x3B04200 − 0x1A0000000**.
- **La RAM ne change pas la table** (même scatter pour 2, 4, 6 ou 8 Go de RAM). Elle change le **preloader** : il y
  en a un par configuration de RAM. Ne flashez jamais le preloader d'une autre unité : décochez-le, ou prenez celui de
  votre propre sauvegarde.
- **`otp`, `flashinfo`, `sgpt`** ont des adresses symboliques (`0xFFFF01d8`, `0xFFFF0080`, `0xFFFF0000`), normales
  dans un scatter MTK (`is_download: false`). Un *Readback* les lit telles quelles, donc ailleurs (vers 4 Gio, dans
  system). Adresses réelles à mettre dans le readback, D = taille du disque en octets : sgpt **D − 0x4200** (longueur
  `0x4200`), flashinfo **D − 0x1004200** (`0x1000000`), otp **D − 0x3B04200** (`0x2B00000`). Ou par adb :
  `dd if=/dev/block/mmcblk0 of=/sdcard/sgpt.bin bs=512 skip=$(( $(cat /sys/block/mmcblk0/size) - 33 )) count=33`.
- **`boot32MiB` seulement APRÈS la migration** (`librehu_boot32_twrp.zip`), `boot10MiB` seulement sur la table
  d'origine. **Jamais « Format All » ni « Firmware Upgrade »** : *Readback* et *Download Only* uniquement.
- Avec `boot32MiB`, SP Flash Tool refuse les images trop grandes (`boundary_check`) : le `vendor.img` d'origine
  (2 Gio) ne tient plus ; un `dtbo.img` de 8 Mio est à couper à 1 Mio ; boot : seulement une image de 32 Mio (pied AVB
  en fin de partition), une image de 10 Mio laisserait le pied de la précédente.
- Le champ `platform: MT6761` doit rester tel quel (SP Flash Tool choisit la puce avec) ; seul le nom des fichiers
  dit AC8257.

Régénérer : `python3 scatter/make_scatters.py <scatter d'une UJC201> scatter` (accepte aussi un fichier de ce
dossier ; tailles et sources dans le script).

Sources : scatter de l'unité de référence (sauvegarde SP Flash Tool, GPT relue par adb le 17/11/2026) ; scatter
AC8259 4/64 de [initialChris/junsun-v1pro-recovery](https://github.com/initialChris/junsun-v1pro-recovery)
(`AC8259_V1PRO_Android_scatter.txt` : userdata `0xFE800000` + `0xD654FBE00`, même longueur de readback
`0xE67800000` dans son README).

---

## English

Scatters of the UJC201 (AutoChips AC8257, platform `MT6761`, project `ac8257_demo`) for every eMMC size and both
boot partition tables (table above). Only two things change between the files: the boot table (`boot10MiB` = stock,
`boot32MiB` = table of `librehu_boot32_twrp.zip`: boot 32 MiB, dtbo 1 MiB at `0x21200000`, tee1 `0x21300000`, tee2
`0x21800000`, vendor `0x21F00000` / 2033 MiB) and the size of userdata, the last partition (starts at
`0x1A0000000`, ends `0x3B04200` bytes before the end of the disk). Everything else is byte for byte the scatter of a
UJC201 (WwR MTK 2.50, 44 entries, CRLF).

- **The real size of an eMMC varies** even at the same capacity (two measured 128 GB UJC201: 12 MiB apart). The
  128 GB value is exact for the measured unit, 64 GB is derived from a real AC8259 4/64 scatter, 16 / 32 / 256 GB are
  cautious estimates (95 % of the capacity). Yours, in TWRP: `cat /sys/block/mmcblk0/size` (512-byte sectors), then
  **userdata = sectors × 512 − 0x3B04200 − 0x1A0000000**.
- **RAM does not change the table** (same scatter for 2, 4, 6 or 8 GB of RAM). It changes the **preloader**: one per
  RAM configuration. Never flash the preloader of another unit: untick it, or use the one of your own backup.
- **`otp`, `flashinfo`, `sgpt`** have symbolic addresses (`0xFFFF01d8`, `0xFFFF0080`, `0xFFFF0000`), normal in an
  MTK scatter. A *Readback* takes them literally (it reads system). Real addresses, D = disk size in bytes: sgpt
  **D − 0x4200** (length `0x4200`), flashinfo **D − 0x1004200** (`0x1000000`), otp **D − 0x3B04200** (`0x2B00000`).
- **`boot32MiB` only AFTER the migration**, `boot10MiB` only on the stock table. **Never "Format All" or "Firmware
  Upgrade"**: *Readback* and *Download Only* only. With `boot32MiB`, the stock `vendor.img` (2 GiB) no longer fits,
  a dtbo of 8 MiB must be cut to 1 MiB, and boot takes only a 32 MiB image (AVB footer at the end of the partition).
- `platform: MT6761` must stay as it is (SP Flash Tool picks the chip with it); only the file names say AC8257.

Regenerate: `python3 scatter/make_scatters.py <scatter of a UJC201> scatter`.
