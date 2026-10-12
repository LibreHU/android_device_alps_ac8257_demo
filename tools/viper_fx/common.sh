# Fonctions communes aux zips ViPER (inclus dans update-binary par build.sh)
ui_print() { if [ -n "$OUTFD" ] && [ -e /proc/self/fd/$OUTFD ] && [ -z "$UJC_TEST" ]; then echo "ui_print $1" > /proc/self/fd/$OUTFD; echo "ui_print" > /proc/self/fd/$OUTFD; else echo "$1"; fi; }
abort() { ui_print "ERREUR : $1"; cleanup; exit 1; }

BYNAME=/dev/block/platform/bootdevice/by-name
SYSMNT=${UJC_SYSMNT:-/system_root}
VENMNT=${UJC_VENMNT:-/vendor}
SDCARD=${UJC_SDCARD:-/data/media/0}
VBMETA=${UJC_VBMETA:-$BYNAME/vbmeta}
MOUNTED_SYS=0; MOUNTED_VEN=0

cleanup() {
	[ -n "$UJC_TEST" ] && return
	sync
	[ $MOUNTED_VEN = 1 ] && umount $VENMNT 2>/dev/null
	[ $MOUNTED_SYS = 1 ] && umount $SYSMNT 2>/dev/null
}

# system et vendor en lecture-ecriture
mount_rw() {
	[ -n "$UJC_TEST" ] && return
	for p in system:$SYSMNT vendor:$VENMNT; do
		part=${p%%:*}; mnt=${p#*:}
		umount $mnt 2>/dev/null
		[ $part = system ] && umount /system 2>/dev/null
		mkdir -p $mnt
		blockdev --setrw $BYNAME/$part 2>/dev/null
		mount -t ext4 -o rw $BYNAME/$part $mnt || abort "montage de $part en ecriture impossible"
		[ $part = system ] && MOUNTED_SYS=1 || MOUNTED_VEN=1
	done
}

# Dossier "system" de la partition system (system-as-root : /system_root/system)
sysdir() { [ -d $SYSMNT/system/etc ] && echo $SYSMNT/system || echo $SYSMNT; }

# Fichiers de configuration des effets audio : ceux de vendor (Android 9 les lit en priorite), sinon ceux de system
effect_configs() {
	for d in $VENMNT/etc $(sysdir)/etc; do
		found=""
		for f in $d/audio_effects*.xml $d/audio_effects*.conf; do
			[ -f "$f" ] && [ ! -L "$f" ] && echo "$f" && found=1
		done
		[ -n "$found" ] && return
	done
}

# --- dm-verity de /vendor (AVB) : modifier vendor sous verity actif = Android ne demarre plus
# Drapeaux fs_mgr d'une partition : fstab du device tree (montage anticipe d'Android 9) ou fstab de vendor.
# $1 = vendor ou system
fsmgr_flags() {
	dt=${UJC_DT:-/proc/device-tree}/firmware/android/fstab/$1/fsmgr_flags
	[ -f $dt ] && tr '\0' ' ' < $dt
	for f in $VENMNT/etc/fstab.*; do
		[ -f "$f" ] && grep -E "^[^#]*[[:space:]]/$1[[:space:]]" "$f" | awk '{print $NF}'
	done
}
# 1 octet (decimal) de vbmeta a l'offset $1
vbmeta_byte() { dd if=$VBMETA bs=1 skip=$1 count=1 2>/dev/null | od -An -tu1 | tr -d ' '; }
vbmeta_ok() { [ "$(dd if=$VBMETA bs=1 count=4 2>/dev/null)" = AVB0 ]; }
# AvbVBMetaImageHeader.flags (offset 120, big-endian) : bit 0 = HASHTREE_DISABLED (adb disable-verity)
hashtree_disabled() { v=$(vbmeta_byte 123); [ -n "$v" ] && [ $((v & 1)) = 1 ]; }
