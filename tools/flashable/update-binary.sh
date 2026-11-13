#!/sbin/sh
# LibreHU - LineageOS 16.0 pour l'UJC201 (ac8257_demo) : installateur TWRP fait par tools/make_flashable_zip.py.
# Ecrit system (image brute en morceaux de 1 Gio, empreinte relue sur toute la partition), boot (image du noyau LibreHU
# avec androidboot.selinux=permissive ; « bootmenu » ou « plain » dans le nom du zip, sinon le type deja installe) et les
# modules Wi-Fi / BT / GPS / FM de ce noyau dans /vendor/lib/modules (originaux sauvegardes une fois). Ne touche jamais
# vbmeta : s'arrete sans rien ecrire si sa verification n'est pas desactivee. N'efface pas /data.
OUTFD=$2
ZIPFILE=$3
ui_print() { if [ -n "$OUTFD" ] && [ -e /proc/self/fd/$OUTFD ] && [ -z "$UJC_TEST" ]; then echo "ui_print $1" > /proc/self/fd/$OUTFD; echo "ui_print" > /proc/self/fd/$OUTFD; else echo "$1"; fi; }
abort() { ui_print "ERREUR : $1"; cleanup; exit 1; }

BYNAME=${UJC_BYNAME:-/dev/block/platform/bootdevice/by-name}
VENMNT=${UJC_VENMNT:-/vendor}
SDCARD=${UJC_SDCARD:-/data/media/0}
TMPD=${UJC_TMP:-/tmp}/librehu_lineage
OTAZIP=${UJC_TMP:-/tmp}/librehu_lineage_ota.zip
MOUNTED_VEN=0

cleanup() {
	rm -f $OTAZIP
	[ -n "$UJC_TEST" ] && return
	sync
	[ $MOUNTED_VEN = 1 ] && umount $VENMNT 2>/dev/null
	rm -rf $TMPD
}

# Mise a jour par l'appli Mises a jour de LineageOS (RecoverySystem.installPackage) : le zip est dans /data, TWRP passe
# « @/cache/recovery/block.map », ecrit par uncrypt : 1re ligne le peripherique bloc de /data, 2e la taille du zip et
# celle d'un bloc, 3e le nombre de plages, puis une plage « debut fin » par ligne, en blocs, fin exclue
# (bootable/recovery : uncrypt/uncrypt.cpp, otautil/SysUtil.cpp). Le zip est relu plage par plage sur la partition,
# comme le fait le recovery d'AOSP (il marche aussi sur un /data chiffre : uncrypt y a remis le zip en clair), dans
# un fichier temporaire de /tmp (en memoire).
blockmap_zip() {
	{
		read -r DEV || return 1
		read -r FSIZE BSIZE || return 1
		read -r NRANGES || return 1
		[ -b "$DEV" ] || [ -f "$DEV" ] || return 1
		case "$FSIZE$BSIZE$NRANGES" in ''|*[!0-9]*) return 1;; esac
		[ "$BSIZE" -gt 0 ] && [ "$NRANGES" -gt 0 ] || return 1
		: > "$2" || return 1
		POS=0
		I=0
		while [ $I -lt "$NRANGES" ]; do
			read -r START END || return 1
			[ "$END" -gt "$START" ] || return 1
			dd if="$DEV" of="$2" bs="$BSIZE" skip="$START" seek="$POS" count=$((END - START)) conv=notrunc 2>/dev/null || return 1
			POS=$((POS + END - START))
			I=$((I + 1))
		done
	} < "$1"
	# dernier bloc rempli au-dela de la taille du zip : coupe a sa taille
	dd if=/dev/null of="$2" bs=1 seek="$FSIZE" 2>/dev/null
	[ "$(stat -c %s "$2")" = "$FSIZE" ]
}
case "$ZIPFILE" in
	@*)
		ui_print "Zip de l'appli Mises a jour : relecture depuis /data (block map)..."
		blockmap_zip "${ZIPFILE#@}" $OTAZIP || abort "zip de la mise a jour illisible (${ZIPFILE#@})"
		ZIPFILE=$OTAZIP
		;;
esac

part() { [ -n "$UJC_TEST" ] && echo "$BYNAME/$1" && return; [ -e $BYNAME/$1 ] && echo $BYNAME/$1 && return; echo /dev/block/by-name/$1; }
info() { unzip -p "$ZIPFILE" info/$1 2>/dev/null; }

ui_print "LibreHU - LineageOS 16.0 (UJC201)"
ui_print "--------------------------------"
ui_print "build : $(info build)"

# --- appareil
if [ -z "$UJC_TEST" ]; then
	DEV=$(getprop ro.product.device)
	case "$DEV" in ac8257_demo) ;; *) abort "appareil \"$DEV\" non pris en charge (ac8257_demo)";; esac
fi

# --- vbmeta : verification desactivee (drapeau 2), jamais ecrite ici
VB=$(part vbmeta)
[ "$(dd if=$VB bs=1 count=4 2>/dev/null)" = AVB0 ] || abort "vbmeta illisible ($VB)"
FLAGS=$(dd if=$VB bs=1 skip=123 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
if [ $(( ${FLAGS:-0} & 2 )) != 2 ]; then
	ui_print " "
	ui_print "La verification AVB (vbmeta) est active : le vbmeta du stock"
	ui_print "chaine la partition system, et le system de LineageOS n'a pas"
	ui_print "de pied AVB : l'autoradio ne demarrerait plus."
	ui_print "Rien n'a ete ecrit. A faire vous-meme, une fois, depuis un PC :"
	ui_print "  fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img"
	ui_print "(vbmeta.img = celui du stock, sauvegarde TWRP ou rapport Helper),"
	ui_print "puis reflasher ce zip."
	abort "vbmeta : verification active"
fi
ui_print "vbmeta : verification desactivee (drapeaux $FLAGS) : OK"

rm -rf $TMPD; mkdir -p $TMPD
unzip -o -q "$ZIPFILE" 'info/*' 'boot*.img' 'modules/*' -d $TMPD || abort "extraction du zip impossible"

# --- sauvegardes (memoire interne)
BK=""
if [ -d $SDCARD ]; then
	BK=$SDCARD/LibreHU/backup
	mkdir -p $BK || BK=""
fi
[ -n "$BK" ] || ui_print "Memoire interne absente : pas de sauvegarde de boot ni des modules (sauvegarde TWRP conseillee)"

# --- system : morceaux bruts ecrits a leur place, puis empreinte de toute l'image relue sur la partition
SYS=$(part system)
SIZE=$(cat $TMPD/info/system.size)
CHUNK_MIB=$(cat $TMPD/info/system.chunk_mib)
PSZ=$(blockdev --getsize64 $SYS 2>/dev/null); [ -z "$PSZ" ] && PSZ=$(stat -c %s $SYS)
[ -n "$PSZ" ] && [ "$SIZE" -le "$PSZ" ] || abort "system ($SIZE octets) plus grand que la partition ($PSZ)"
umount /system_root 2>/dev/null; umount /system 2>/dev/null
blockdev --setrw $SYS 2>/dev/null
N=0
for c in $(cat $TMPD/info/system.chunks); do
	ui_print "system : morceau $((N + 1)) / $(wc -w < $TMPD/info/system.chunks)"
	unzip -p "$ZIPFILE" $c | dd of=$SYS bs=1048576 seek=$((N * CHUNK_MIB)) conv=notrunc 2>/dev/null || abort "ecriture de system impossible ($c)"
	N=$((N + 1))
done
sync
ui_print "system : verification (toute l'image, une minute environ)"
[ "$(head -c $SIZE $SYS | sha256sum | cut -d' ' -f1)" = "$(cat $TMPD/info/system.sha256)" ] || abort "system relu different : reflasher le zip (ou restaurer la sauvegarde TWRP)"
ui_print "system ecrit et verifie ($SIZE octets)"

# --- boot : « bootmenu » ou « plain » dans le nom du zip impose l'image ; sinon (zip de la release, mise a jour par
# l'appli Mises a jour) celle qui est installee est gardee : l'image du menu a un ramdisk (taille a l'octet 16 de
# l'en-tete), l'autre non.
BOOT=$(part boot)
case "$(basename "$ZIPFILE")" in
	*bootmenu*) IMG=boot-bootmenu.img ;;
	*plain*) IMG=boot.img ;;
	*)
		RD=$(dd if=$BOOT bs=1 skip=16 count=4 2>/dev/null | od -An -tu4 | tr -d ' ')
		if [ "${RD:-0}" -gt 0 ] 2>/dev/null; then IMG=boot-bootmenu.img; else IMG=boot.img; fi
		;;
esac
E=$(grep " $IMG\$" $TMPD/info/SHA256SUMS | cut -d' ' -f1)
[ "$(sha256sum $TMPD/$IMG | cut -d' ' -f1)" = "$E" ] || abort "$IMG abimee (empreinte)"
ISZ=$(stat -c %s $TMPD/$IMG)
if [ -n "$BK" ]; then
	B=$BK/boot-$(date +%Y%m%d-%H%M%S).img
	dd if=$BOOT of=$B bs=1048576 2>/dev/null && ui_print "boot actuel sauvegarde : $B"
fi
blockdev --setrw $BOOT 2>/dev/null
dd if=$TMPD/$IMG of=$BOOT bs=1048576 2>/dev/null || abort "ecriture de boot impossible"
sync
[ "$(head -c $ISZ $BOOT | sha256sum | cut -d' ' -f1)" = "$E" ] || abort "boot relu different : restaurer $B"
ui_print "boot : $IMG ecrit et verifie"

# --- modules du meme noyau dans /vendor/lib/modules
MODS="wmt_drv wmt_chrdev_wifi bt_drv gps_drv fmradio_drv wlan_drv_gen4m"
while read -r S M; do
	[ "$(sha256sum $TMPD/modules/$M | cut -d' ' -f1)" = "$S" ] || abort "empreinte de $M incorrecte"
done < $TMPD/modules/SHA256SUMS
if [ -z "$UJC_TEST" ]; then
	umount $VENMNT 2>/dev/null; mkdir -p $VENMNT
	blockdev --setrw $(part vendor) 2>/dev/null
	mount -t ext4 -o rw $(part vendor) $VENMNT || abort "montage de vendor en ecriture impossible"
	MOUNTED_VEN=1
fi
MD=$VENMNT/lib/modules
[ -d $MD ] || abort "$MD introuvable"
# Meme format que les zips conn-modules-stable (fichiers, meta.txt, SHA256SUMS) : conn-modules-stable-restore remet
# conn-modules-orig.
save_mods() {
	mkdir -p $1 || abort "dossier $1 impossible"
	: > $1/meta.txt; : > $1/SHA256SUMS
	for m in $MODS; do
		k=$MD/$m.ko
		if [ -f $k ]; then
			cp $k $1/ || abort "sauvegarde de $m.ko impossible (memoire pleine ?)"
			ctx=$(ls -Z $k 2>/dev/null | awk '{print $1}')
			case "$ctx" in u:*) ;; *) ctx=u:object_r:vendor_file:s0;; esac
			echo "$m $(stat -c '%a %u %g' $k) $ctx" >> $1/meta.txt
			echo "$(sha256sum $k | cut -d' ' -f1)  $m.ko" >> $1/SHA256SUMS
		else
			echo "$m absent" >> $1/meta.txt
		fi
	done
	[ -f $MD/.librehu_conn ] && cp $MD/.librehu_conn $1/librehu_conn.txt
}
if [ -n "$BK" ]; then
	# Les modules d'origine une seule fois (pas encore remplaces par LibreHU), jamais ecrases.
	if [ ! -f $MD/.librehu_conn ] && [ ! -d $BK/conn-modules-orig ]; then
		save_mods $BK/conn-modules-orig
		ui_print "modules d'origine sauvegardes : $BK/conn-modules-orig"
	fi
	D=$BK/conn-modules-$(date +%Y%m%d-%H%M%S)
	save_mods $D
	ui_print "modules actuels sauvegardes : $D"
fi
for m in $MODS; do
	K=$MD/$m.ko
	cp $TMPD/modules/$m.ko $K.librehu.new || abort "copie de $m.ko impossible (vendor plein ?)"
	chmod 0644 $K.librehu.new; chown 0:0 $K.librehu.new 2>/dev/null
	[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_file:s0 $K.librehu.new
	mv -f $K.librehu.new $K || abort "remplacement de $m.ko impossible"
done
{ echo "lineage $(info build)"; cat $TMPD/modules/kernel_version; } > $MD/.librehu_conn
chmod 0644 $MD/.librehu_conn
[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_file:s0 $MD/.librehu_conn
ui_print "modules du noyau LibreHU installes dans $MD"

# --- restes du zip usbnet (fait pour le noyau stock) : son init.librehu_usbnet.rc charge un r8152.ko d'un autre noyau,
# refuse par le noyau LibreHU (« Exec format error » ; pilotes Ethernet USB integres). Sauvegardes puis retires.
if [ -n "$VENMNT" ] && { [ -f "$VENMNT/etc/init/init.librehu_usbnet.rc" ] || [ -d "$VENMNT/lib/modules/librehu-usbnet" ]; }; then
	if [ -n "$BK" ]; then
		mkdir -p "$BK/usbnet-old"
		cp -a "$VENMNT/etc/init/init.librehu_usbnet.rc" "$VENMNT/lib/modules/librehu-usbnet" "$BK/usbnet-old/" 2>/dev/null
	fi
	rm -f "$VENMNT/etc/init/init.librehu_usbnet.rc"
	rm -f "$VENMNT/lib/modules/librehu-usbnet/"*.ko
	rmdir "$VENMNT/lib/modules/librehu-usbnet" 2>/dev/null
	ui_print "restes du zip usbnet retires du vendor (pilotes Ethernet USB integres au noyau)"
fi

# --- /data : jamais effacee ici
if [ -f /data/system/packages.xml ] && ! grep -q "org.lineageos" /data/system/packages.xml 2>/dev/null; then
	ui_print " "
	ui_print "ATTENTION : /data vient d'une autre ROM (stock ?)."
	ui_print "Premiere installation : Wipe > Format Data (taper yes)"
	ui_print "AVANT de redemarrer, sinon LineageOS ne demarre pas."
fi

ui_print " "
ui_print "Termine. Retour arriere : restaurer la sauvegarde TWRP."
cleanup
exit 0
