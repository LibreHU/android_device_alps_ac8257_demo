#!/sbin/sh
# LibreHU - LineageOS 20.0 (Android 13, portage experimental) pour l'UJC201 (ac8257_demo) : installateur TWRP fait par tools/make_flashable_zip.py.
# Ecrit system (image brute en morceaux de 1 Gio, empreinte relue sur toute la partition), boot (image du noyau LibreHU
# avec androidboot.selinux=permissive ; « bootmenu » ou « plain » dans le nom du zip, sinon le type deja installe) et les
# modules Wi-Fi / BT / GPS / FM de ce noyau dans /vendor/lib/modules (originaux sauvegardes une fois), et installe ou
# met a jour le pilote ViPER4Android RE dans /vendor (sauf LibreHU/no-viper dans la memoire interne), puis retire les
# applis du fabricant, le RRO MediaTek et l'ECNR uVoice apres les avoir sauvegardes dans la memoire interne (sauf
# LibreHU/keep-vendor-apps ; README.md et restore.sh avec la sauvegarde). Ne touche jamais
# vbmeta : s'arrete sans rien ecrire si sa verification n'est pas desactivee. N'efface pas /data.
OUTFD=$2
ZIPFILE=$3
# chemin d'origine (« @/cache/recovery/block.map » pour l'appli Mises a jour), pour se relancer apres la migration boot32
ORIGZIP=$3
ui_print() { if [ -n "$OUTFD" ] && [ -e /proc/self/fd/$OUTFD ] && [ -z "$UJC_TEST" ]; then echo "ui_print $1" > /proc/self/fd/$OUTFD; echo "ui_print" > /proc/self/fd/$OUTFD; else echo "$1"; fi; }
abort() { ui_print "ERROR: $1"; cleanup; exit 1; }

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
	# jancar est montee hors de $TMPD : jamais effacee par le rm qui suit
	[ "$MOUNTED_JAN" = 1 ] && umount $JANMNT 2>/dev/null && rmdir $JANMNT 2>/dev/null
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
OTA=0
case "$ZIPFILE" in
	@*)
		OTA=1
		ui_print "Zip of the Updater app: reading it back from /data (block map)..."
		blockmap_zip "${ZIPFILE#@}" $OTAZIP || abort "update zip unreadable (${ZIPFILE#@})"
		ZIPFILE=$OTAZIP
		;;
esac

part() { [ -n "$UJC_TEST" ] && echo "$BYNAME/$1" && return; [ -e $BYNAME/$1 ] && echo $BYNAME/$1 && return; echo /dev/block/by-name/$1; }
info() { unzip -p "$ZIPFILE" info/$1 2>/dev/null; }

ui_print "LibreHU - crDroid 9 (Android 13), PORT (UJC201)"
ui_print "--------------------------------"
ui_print "build: $(info build)"

# --- appareil
if [ -z "$UJC_TEST" ]; then
	DEV=$(getprop ro.product.device)
	case "$DEV" in ac8257_demo) ;; *) abort "device \"$DEV\" not supported (ac8257_demo)";; esac
fi

# --- vbmeta : verification desactivee (drapeau 2), jamais ecrite ici
VB=$(part vbmeta)
[ "$(dd if=$VB bs=1 count=4 2>/dev/null)" = AVB0 ] || abort "vbmeta unreadable ($VB)"
FLAGS=$(dd if=$VB bs=1 skip=123 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
if [ $(( ${FLAGS:-0} & 2 )) != 2 ]; then
	ui_print " "
	ui_print "AVB verification (vbmeta) is on: the stock vbmeta"
	ui_print "chains the system partition, and the LineageOS system has no"
	ui_print "AVB footer: the head unit would no longer boot."
	ui_print "Nothing was written. Do it yourself, once, from a PC:"
	ui_print "  fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img"
	ui_print "(vbmeta.img = the stock one, TWRP backup or Helper report),"
	ui_print "then flash this zip again."
	abort "vbmeta: verification on"
fi
ui_print "vbmeta: verification disabled (flags $FLAGS): OK"

# --- canal de mise a jour (19/11/2026) : une mise a jour par l'appli de mise a jour (zip « @... ») ne passe que sur la
# meme ROM (info/rom : lineage ou crdroid) et la meme version (info/lineage_version : ro.lineage.build.version pour
# LineageOS, ro.crdroid.version pour crDroid). Chaque ROM et chaque version a son flux (release <branche>-ota du depot :
# lineage-17.1-ota, crdroid-13.0-ota...) ; ce controle arrete en plus le zip d'un autre flux. Un flash a la main dans
# TWRP reste libre (changement de ROM ou de version voulu). Rien n'est ecrit avant ce point.
OTA=${OTA:-0}
case "$3" in @*) OTA=1;; esac
ZROM=$(info rom); [ -n "$ZROM" ] || ZROM=lineage
ZVER=$(info lineage_version)
if [ "$OTA" = 1 ]; then
	[ -n "$ZVER" ] || abort "zip without a ROM version (info/lineage_version): update refused"
	SYSRO=${UJC_TMP:-/tmp}/librehu_sysro
	mkdir -p $SYSRO
	CUR=; CURROM=
	if mount -t ext4 -o ro $(part system) $SYSRO 2>/dev/null; then
		for bp in $SYSRO/system/build.prop $SYSRO/build.prop; do
			[ -f $bp ] || continue
			if grep -q '^ro.crdroid.version=' $bp; then
				CURROM=crdroid; CUR=$(sed -n 's/^ro.crdroid.version=//p' $bp | head -n 1)
			else
				CURROM=lineage; CUR=$(sed -n 's/^ro.lineage.build.version=//p' $bp | head -n 1)
			fi
			break
		done
		umount $SYSRO 2>/dev/null
	fi
	rmdir $SYSRO 2>/dev/null
	[ -n "$CURROM" ] || abort "installed system unreadable: update refused (flash the zip by hand in TWRP)"
	if [ "$CURROM" != "$ZROM" ] || [ "$CUR" != "$ZVER" ]; then
		ui_print "Update $ZROM $ZVER over $CURROM ${CUR:-?}: refused,"
		ui_print "each ROM and version has its own update channel."
		ui_print "To change ROM or version: flash the zip by hand in TWRP."
		abort "update channel: installed $CURROM ${CUR:-?}, zip $ZROM $ZVER"
	fi
	ui_print "update channel: $CURROM $CUR -> $ZROM $ZVER: OK"
fi

rm -rf $TMPD; mkdir -p $TMPD
unzip -o -q "$ZIPFILE" 'info/*' 'boot*.img' 'modules/*' -d $TMPD || abort "cannot extract the zip"
unzip -o -q "$ZIPFILE" 'boot32/*' -d $TMPD 2>/dev/null

# --- partition boot de 32 Mio (19/11/2026) : Android 10 et plus prennent le noyau 4.19 -lto32, une image de 32 Mio.
# Partition encore a 10 Mio : migration d'abord, avec le zip librehu_boot32_twrp.zip de la release du noyau (memes
# verifications et sauvegardes que flashe a la main : vbmeta, 4,4 Go libres, /sdcard/LibreHU/boot32), avant toute
# ecriture de LineageOS. Le noyau de TWRP ne relit la nouvelle table qu'au redemarrage : ce zip se reprogramme
# (OpenRecoveryScript, ou la commande de l'appli Mises a jour), puis TWRP redemarre et l'installe tout seul.
BOOT=$(part boot)
BIMG=$(stat -c %s $TMPD/boot-bootmenu.img 2>/dev/null)
BPART=$(blockdev --getsize64 $BOOT 2>/dev/null); [ -z "$BPART" ] && BPART=$(stat -c %s $BOOT 2>/dev/null)
if [ -n "$BIMG" ] && [ -n "$BPART" ] && [ "$BIMG" -gt "$BPART" ] 2>/dev/null; then
	ui_print " "
	ui_print "This LineageOS needs the 32 MiB boot partition (now $((BPART / 1048576)) MiB)."
	B32Z=$TMPD/boot32/librehu_boot32_twrp.zip
	[ -f $B32Z ] || abort "boot partition too small and no boot32 zip in this zip: nothing was written"
	E=$(grep ' boot32/librehu_boot32_twrp.zip$' $TMPD/info/SHA256SUMS | cut -d' ' -f1)
	[ "$(sha256sum $B32Z | cut -d' ' -f1)" = "$E" ] || abort "boot32 zip damaged (checksum): nothing was written"
	ui_print "Step 1: boot partition 10 -> 32 MiB (librehu_boot32_twrp.zip),"
	ui_print "then TWRP restarts and installs this zip again by itself."
	ui_print "-----------------------------------------------------------"
	B32X=$TMPD/boot32x; rm -rf $B32X; mkdir -p $B32X
	unzip -o -q $B32Z META-INF/com/google/android/update-binary -d $B32X || abort "cannot extract the boot32 zip"
	sh $B32X/META-INF/com/google/android/update-binary 3 "$OUTFD" $B32Z || abort "boot partition migration stopped (see above): LineageOS not written"
	[ -f $SDCARD/LibreHU/boot32/MIGRATED ] || abort "boot partition migration not confirmed: LineageOS not written"
	ui_print "-----------------------------------------------------------"
	CACHE=${UJC_CACHE:-/cache}
	[ -z "$UJC_TEST" ] && mount /cache 2>/dev/null
	mkdir -p $CACHE/recovery
	if [ "$OTA" = 1 ]; then
		echo "--update_package=$ORIGZIP" > $CACHE/recovery/command
		ui_print "Update scheduled again after the restart (Updater app)."
	else
		case "$ZIPFILE" in
		/tmp/*|/sideload/*|/usb*|/external*)
			ui_print "This zip is not in the internal storage: after the restart,"
			ui_print "flash it again by hand (Install).";;
		*)
			echo "install $ZIPFILE" > $CACHE/recovery/openrecoveryscript
			ui_print "Install of $(basename "$ZIPFILE") scheduled after the restart.";;
		esac
	fi
	sync
	ui_print "TWRP restarts in 5 s (new partition table)."
	rm -rf $TMPD
	[ -z "$UJC_TEST" ] && { sleep 5; reboot recovery; }
	exit 0
fi

# --- sauvegardes (memoire interne)
BK=""
if [ -d $SDCARD ]; then
	BK=$SDCARD/LibreHU/backup
	mkdir -p $BK || BK=""
fi
[ -n "$BK" ] || ui_print "No internal storage: no backup of boot or of the modules (a TWRP backup is advised)"

# --- system : morceaux bruts ecrits a leur place, puis empreinte de toute l'image relue sur la partition
SYS=$(part system)
SIZE=$(cat $TMPD/info/system.size)
CHUNK_MIB=$(cat $TMPD/info/system.chunk_mib)
PSZ=$(blockdev --getsize64 $SYS 2>/dev/null); [ -z "$PSZ" ] && PSZ=$(stat -c %s $SYS)
# awk: sizes over 2 GiB overflow the 32-bit arithmetic of TWRP's mksh, [ -le ] included
[ -n "$PSZ" ] && awk -v s="$SIZE" -v p="$PSZ" 'BEGIN { exit !(s + 0 > 0 && s + 0 <= p + 0) }' \
	|| abort "system ($SIZE bytes) larger than the partition ($PSZ)"
umount /system_root 2>/dev/null; umount /system 2>/dev/null
blockdev --setrw $SYS 2>/dev/null
N=0
for c in $(cat $TMPD/info/system.chunks); do
	ui_print "system: chunk $((N + 1)) / $(wc -w < $TMPD/info/system.chunks)"
	unzip -p "$ZIPFILE" $c | dd of=$SYS bs=1048576 seek=$((N * CHUNK_MIB)) conv=notrunc 2>/dev/null || abort "cannot write system ($c)"
	N=$((N + 1))
done
sync
ui_print "system: check (whole image, about one minute)"
[ "$(head -c $SIZE $SYS | sha256sum | cut -d' ' -f1)" = "$(cat $TMPD/info/system.sha256)" ] || abort "system read back different: flash the zip again (or restore the TWRP backup)"
ui_print "system written and checked ($SIZE bytes)"

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
[ "$(sha256sum $TMPD/$IMG | cut -d' ' -f1)" = "$E" ] || abort "$IMG damaged (checksum)"
ISZ=$(stat -c %s $TMPD/$IMG)
if [ -n "$BK" ]; then
	B=$BK/boot-$(date +%Y%m%d-%H%M%S).img
	dd if=$BOOT of=$B bs=1048576 2>/dev/null && ui_print "current boot backed up: $B"
fi
blockdev --setrw $BOOT 2>/dev/null
dd if=$TMPD/$IMG of=$BOOT bs=1048576 2>/dev/null || abort "cannot write boot"
sync
[ "$(head -c $ISZ $BOOT | sha256sum | cut -d' ' -f1)" = "$E" ] || abort "boot read back different: restore $B"
ui_print "boot: $IMG written and checked"

# --- modules du meme noyau dans /vendor/lib/modules (aucun pour un noyau -lto32 : connectivite integree, SHA256SUMS vide)
MODS="wmt_drv wmt_chrdev_wifi bt_drv gps_drv fmradio_drv wlan_drv_gen4m"
if [ ! -s $TMPD/modules/SHA256SUMS ]; then
	ui_print "modules: connectivity built into the kernel, nothing to install in vendor"
	NOMODS=1
fi
while read -r S M; do
	[ "$(sha256sum $TMPD/modules/$M | cut -d' ' -f1)" = "$S" ] || abort "wrong checksum for $M"
done < $TMPD/modules/SHA256SUMS
if [ -z "$UJC_TEST" ]; then
	umount $VENMNT 2>/dev/null; mkdir -p $VENMNT
	blockdev --setrw $(part vendor) 2>/dev/null
	mount -t ext4 -o rw $(part vendor) $VENMNT || abort "cannot mount vendor read-write"
	MOUNTED_VEN=1
fi
MD=$VENMNT/lib/modules
[ -d $MD ] || abort "$MD not found"
# Meme format que les zips conn-modules-stable (fichiers, meta.txt, SHA256SUMS) : conn-modules-stable-restore remet
# conn-modules-orig.
save_mods() {
	mkdir -p $1 || abort "cannot create folder $1"
	: > $1/meta.txt; : > $1/SHA256SUMS
	for m in $MODS; do
		k=$MD/$m.ko
		if [ -f $k ]; then
			cp $k $1/ || abort "cannot back up $m.ko (storage full?)"
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
if [ -z "$NOMODS" ]; then
if [ -n "$BK" ]; then
	# Les modules d'origine une seule fois (pas encore remplaces par LibreHU), jamais ecrases.
	if [ ! -f $MD/.librehu_conn ] && [ ! -d $BK/conn-modules-orig ]; then
		save_mods $BK/conn-modules-orig
		ui_print "original modules backed up: $BK/conn-modules-orig"
	fi
	D=$BK/conn-modules-$(date +%Y%m%d-%H%M%S)
	save_mods $D
	ui_print "current modules backed up: $D"
fi
for m in $MODS; do
	K=$MD/$m.ko
	cp $TMPD/modules/$m.ko $K.librehu.new || abort "cannot copy $m.ko (vendor full?)"
	chmod 0644 $K.librehu.new; chown 0:0 $K.librehu.new 2>/dev/null
	[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_file:s0 $K.librehu.new
	mv -f $K.librehu.new $K || abort "cannot replace $m.ko"
done
{ echo "lineage $(info build)"; cat $TMPD/modules/kernel_version; } > $MD/.librehu_conn
chmod 0644 $MD/.librehu_conn
[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_file:s0 $MD/.librehu_conn
ui_print "LibreHU kernel modules installed in $MD"
fi

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
	ui_print "leftovers of the usbnet zip removed from vendor (USB Ethernet drivers built into the kernel)"
fi

# --- pilote ViPER4Android RE (ViPERFX_RE de l'appli ViPER4Android LibreHU de la ROM, meme version) : installe ou mis a
# jour dans /vendor/lib[64]/soundfx et declare dans les audio_effects de vendor (bibliotheque "v4a_re", effet
# "v4a_standard_re"), comme le zip viper4android-re de LibreHU-flashablesZips : meme sauvegarde <fichier>.v4a-orig
# (fichier sans ViPER), que son zip viper4android-re-restore remet. Le fichier en place est repris (ce que d'autres zips
# y ont ajoute reste) et reecrit seulement s'il change. Rien n'est fait si la memoire interne contient LibreHU/no-viper
# (cree par le zip viper4android-re-restore). Un echec ici n'arrete pas l'installation : system, boot et modules sont
# deja ecrits.
V4A_UUID=90380da3-8536-4744-a6a3-5731970e640f
# Le fichier $1 sans les lignes de ViPER
v4a_strip() {
	case $1 in
		*.xml) sed -e '/v4a_standard_re/d' -e '/"v4a_re"/d' "$1" ;;
		*) sed -e '/v4a_standard_re {/,/}/d' -e '/v4a_re {/,/}/d' "$1" ;;
	esac
}
viper_install() {
	unzip -o -q "$ZIPFILE" 'viper/*' -d $TMPD || { ui_print "ViPER: cannot extract the zip"; return 1; }
	while read -r S F; do
		[ "$(sha256sum $TMPD/viper/$F | cut -d' ' -f1)" = "$S" ] || { ui_print "ViPER: wrong checksum for $F"; return 1; }
	done < $TMPD/viper/SHA256SUMS
	VV=$(cat $TMPD/viper/version)
	NL=0
	for arch in lib lib64; do
		d=$VENMNT/$arch/soundfx
		[ -d $d ] || continue
		NL=$((NL + 1))
		so=$TMPD/viper/libv4a_re_armeabi-v7a.so; [ $arch = lib64 ] && so=$TMPD/viper/libv4a_re_arm64-v8a.so
		if cmp -s $so $d/libv4a_re.so; then
			ui_print "ViPER: $d/libv4a_re.so already $VV"
			continue
		fi
		if [ -f $d/libv4a_re.so ]; then ST="updated"; else ST="installed"; fi
		cp $so $d/libv4a_re.so.librehu.new || { rm -f $d/libv4a_re.so.librehu.new; ui_print "ViPER: cannot copy into $d (vendor full?)"; return 1; }
		chmod 0644 $d/libv4a_re.so.librehu.new; chown 0:0 $d/libv4a_re.so.librehu.new 2>/dev/null
		[ -z "$UJC_TEST" ] && chcon u:object_r:vendor_file:s0 $d/libv4a_re.so.librehu.new
		mv -f $d/libv4a_re.so.librehu.new $d/libv4a_re.so || { ui_print "ViPER: cannot replace in $d"; return 1; }
		ui_print "ViPER: $d/libv4a_re.so $ST ($VV)"
	done
	[ $NL -gt 0 ] || { ui_print "ViPER: $VENMNT/lib/soundfx not found"; return 1; }
	NC=0
	VBK=""
	for f in $VENMNT/etc/audio_effects*.xml $VENMNT/etc/audio_effects*.conf; do
		[ -f "$f" ] && [ ! -L "$f" ] || continue
		T=$TMPD/v4a_cfg
		case $f in
			*.xml)
				grep -q '<libraries>' "$f" && grep -q '<effects>' "$f" || continue
				v4a_strip "$f" | sed \
				    -e "s|<libraries>|<libraries>\n        <library name=\"v4a_re\" path=\"libv4a_re.so\"/>|" \
				    -e "s|<effects>|<effects>\n        <effect name=\"v4a_standard_re\" library=\"v4a_re\" uuid=\"$V4A_UUID\"/>|" \
				    > $T || { ui_print "ViPER: cannot read $f"; return 1; }
				;;
			*)
				grep -q '^libraries {' "$f" && grep -q '^effects {' "$f" || continue
				v4a_strip "$f" | sed \
				    -e "s|^libraries {|libraries {\n  v4a_re {\n    path /vendor/lib/soundfx/libv4a_re.so\n  }|" \
				    -e "s|^effects {|effects {\n  v4a_standard_re {\n    library v4a_re\n    uuid $V4A_UUID\n  }|" \
				    > $T || { ui_print "ViPER: cannot read $f"; return 1; }
				;;
		esac
		NC=$((NC + 1))
		grep -q "$V4A_UUID" $T || { ui_print "ViPER: change of $f failed"; return 1; }
		if cmp -s $T "$f"; then
			ui_print "ViPER: effect already declared in $f"
			continue
		fi
		if [ ! -f "$f.v4a-orig" ]; then
			cp -p "$f" "$f.v4a-orig" && v4a_strip "$f" > "$f.v4a-orig" || { rm -f "$f.v4a-orig"; ui_print "ViPER: cannot back up $f.v4a-orig"; return 1; }
		fi
		if [ -n "$BK" ]; then
			[ -n "$VBK" ] || VBK=$BK/viper-$(date +%Y%m%d-%H%M%S)
			mkdir -p $VBK && cp -p "$f" $VBK/
		fi
		# reecriture sur place : garde l'inode, les droits et le contexte SELinux
		cat $T > "$f" || { ui_print "ViPER: cannot write $f (restore $f.v4a-orig)"; return 1; }
		cmp -s $T "$f" || { ui_print "ViPER: check of $f failed (restore $f.v4a-orig)"; return 1; }
		ui_print "ViPER: effect v4a_standard_re declared in $f"
	done
	[ $NC -gt 0 ] || { ui_print "ViPER: no usable audio_effects in $VENMNT/etc"; return 1; }
	[ -n "$VBK" ] && ui_print "ViPER: previous configuration backed up: $VBK"
	return 0
}
if [ -f $SDCARD/LibreHU/no-viper ]; then
	ui_print "ViPER: LibreHU/no-viper in internal storage, driver left alone"
elif ! viper_install; then
	ui_print "ViPER: driver not installed, the rest of the ROM is. Try again:"
	ui_print "  zip viper4android-re (LibreHU Apps)"
fi

# --- WPA3 (SAE) et OWE : wpa_supplicant avec le HAL 1.2 (wifi/ du zip, construit et verifie contre le VNDK 28 par la CI) a la
# place de celui du vendor Android 9 (HAL 1.1) ; tools/flashable/wifi-wpa3.sh, originaux sauvegardes une fois dans
# LibreHU/backup/wifi-hal11-orig. Rien si LibreHU/no-wpa3 est dans la memoire interne (laisse par le zip
# librehu_wifi_wpa3_restore_twrp.zip). Un echec ici n'arrete pas l'installation et laisse le Wi-Fi d'origine.
if unzip -o -q "$ZIPFILE" 'wifi/*' -d $TMPD 2>/dev/null && [ -f $TMPD/wifi/version ]; then
	if [ -f $SDCARD/LibreHU/no-wpa3 ]; then
		ui_print "WPA3: LibreHU/no-wpa3 in internal storage, original supplicant left alone"
	elif [ -z "$BK" ]; then
		ui_print "WPA3: no internal storage, no backup possible: not installed"
	else
		. $TMPD/wifi/wifi-wpa3.sh
		wifi_wpa3_install $TMPD/wifi || ui_print "WPA3: not installed (see above), Wi-Fi unchanged"
	fi
fi

# --- applis d'origine et restes du fabricant (confiance zero) : toutes les applis de /vendor/app (Jancar, Autochips,
# MediaTek, tiers), le RRO MediaTek de framework-res (/vendor/overlay, il passe par-dessus les reglages de la ROM),
# l'ECNR uVoice des appels (bibliotheques a licence avec client HTTP, chargees par dlopen depuis libecnrhelper.so, qui
# reste : le HAL audio en a besoin) et les applis de /jancar/oem/app. Tout est d'abord copie dans la memoire interne
# (LibreHU/backup/vendor-cleanup-<date> : fichiers, droits, proprietaire, contexte SELinux, SHA-256, README.md en
# anglais, restore.sh), chaque copie relue, puis seulement retire. Pas de memoire interne, pas assez de place ou une
# copie differente : rien n'est retire. Rien n'est fait si la memoire interne contient LibreHU/keep-vendor-apps. Un echec
# ici n'arrete pas l'installation : system, boot et modules sont deja ecrits.
JANMNT=${UJC_JANMNT:-/tmp/librehu_jancar}
MOUNTED_JAN=0
CLEAN_LIBS="libEcnrForCustomer.so libuvoice_ecnr_sdk.so libuvoice_ecnr_license.so"
TAB=$(printf '\t')
# Chemins a retirer, relatifs a la racine de la partition, un par ligne : « vendor <chemin> » ou « jancar <chemin> »
clean_targets() {
	for d in $VENMNT/app/*; do [ -e "$d" ] && echo "vendor app/${d##*/}"; done
	[ -e $VENMNT/overlay/framework-res__auto_generated_rro.apk ] && echo "vendor overlay/framework-res__auto_generated_rro.apk"
	for a in lib lib64; do for l in $CLEAN_LIBS; do [ -e $VENMNT/$a/$l ] && echo "vendor $a/$l"; done; done
	if [ $MOUNTED_JAN = 1 ] || [ -n "$UJC_TEST" ]; then
		for d in $JANMNT/oem/app/*; do [ -e "$d" ] && echo "jancar oem/app/${d##*/}"; done
	fi
}
root_of() { [ $1 = vendor ] && echo $VENMNT || echo $JANMNT; }
# Une ligne de files.txt par entree (dossiers avant leur contenu) : partie, type, droits, uid, gid, contexte, sha256 ou
# cible du lien, chemin
clean_list() {
	R=$(root_of $1)
	find "$R/$2" | while read -r F; do
		REL=${F#$R/}
		CTX=$(ls -dZ "$F" 2>/dev/null | awk '{print $1}')
		case "$CTX" in u:*) ;; *) CTX=-;; esac
		if [ -L "$F" ]; then T=l; X=$(readlink "$F")
		elif [ -d "$F" ]; then T=d; X=-
		else T=f; X=$(sha256sum "$F" | cut -d' ' -f1)
		fi
		echo "$1$TAB$T$TAB$(stat -c "%a$TAB%u$TAB%g" "$F")$TAB$CTX$TAB$X$TAB$REL"
	done
}
vendor_cleanup() {
	if [ -z "$UJC_TEST" ]; then
		mkdir -p $JANMNT
		blockdev --setrw $(part jancar) 2>/dev/null
		if mount -t ext4 -o rw $(part jancar) $JANMNT; then MOUNTED_JAN=1; else ui_print "cleanup: jancar partition not mounted, /jancar/oem/app left alone"; fi
	fi
	LIST=$TMPD/clean_targets
	clean_targets > $LIST
	if [ ! -s $LIST ]; then
		ui_print "cleanup: no maker app, MediaTek overlay or uVoice ECNR left: nothing to do"
		return 0
	fi
	[ -n "$BK" ] || { ui_print "cleanup: no internal storage for the backup, nothing removed"; return 1; }
	NEED=0
	while read -r P REL; do
		K=$(du -sk "$(root_of $P)/$REL" 2>/dev/null | awk '{print $1}')
		NEED=$((NEED + ${K:-0}))
	done < $LIST
	FREE=$(df -k $SDCARD 2>/dev/null | tail -1 | awk '{print $4}')
	[ "${FREE:-0}" -gt $((NEED + 65536)) ] 2>/dev/null || { ui_print "cleanup: $((NEED / 1024)) MiB needed for the backup, $((${FREE:-0} / 1024)) MiB free: nothing removed"; return 1; }
	CB=$BK/vendor-cleanup-$(date +%Y%m%d-%H%M%S)
	mkdir -p $CB || { ui_print "cleanup: cannot create $CB, nothing removed"; return 1; }
	ui_print "cleanup: backing up $((NEED / 1024)) MiB to $CB"
	: > $CB/files.txt
	while read -r P REL; do
		R=$(root_of $P)
		clean_list $P "$REL" >> $CB/files.txt
		mkdir -p "$CB/$P/$(dirname "$REL")"
		cp -a "$R/$REL" "$CB/$P/$(dirname "$REL")/" || { ui_print "cleanup: cannot back up $P/$REL, nothing removed"; return 1; }
	done < $LIST
	# chaque fichier relu dans la sauvegarde avant de retirer quoi que ce soit
	BAD=0
	while IFS="$TAB" read -r P T MODE U G CTX SUM REL; do
		[ $T = f ] || continue
		[ "$(sha256sum "$CB/$P/$REL" 2>/dev/null | cut -d' ' -f1)" = "$SUM" ] || { BAD=$((BAD + 1)); ui_print "cleanup: backup of $P/$REL differs"; }
	done < $CB/files.txt
	[ $BAD = 0 ] || { ui_print "cleanup: $BAD file(s) not backed up correctly, nothing removed"; return 1; }
	unzip -o -q "$ZIPFILE" 'vendor-cleanup/*' -d $TMPD && cp $TMPD/vendor-cleanup/README.md $TMPD/vendor-cleanup/restore.sh $CB/ \
		|| ui_print "cleanup: README.md / restore.sh not found in the zip (see files.txt)"
	cp $LIST $CB/removed.txt
	N=0
	while read -r P REL; do
		rm -rf "$(root_of $P)/$REL" && N=$((N + 1))
	done < $LIST
	sync
	ui_print "cleanup: $N item(s) removed: maker apps, MediaTek overlay, uVoice ECNR (list: $CB/removed.txt)"
	ui_print "cleanup: why, and how to put them back: $CB/README.md"
	return 0
}
if [ -f $SDCARD/LibreHU/keep-vendor-apps ]; then
	ui_print "cleanup: LibreHU/keep-vendor-apps in internal storage, maker apps left alone"
elif ! vendor_cleanup; then
	ui_print "cleanup: the maker apps stay; the rest of the ROM is installed"
fi
if [ $MOUNTED_JAN = 1 ]; then sync; umount $JANMNT 2>/dev/null && rmdir $JANMNT 2>/dev/null; MOUNTED_JAN=0; fi

# --- /data : jamais effacee ici
if [ -f /data/system/packages.xml ] && ! grep -q "org.lineageos" /data/system/packages.xml 2>/dev/null; then
	ui_print " "
	ui_print "WARNING: /data comes from another ROM (stock?)."
	ui_print "First install: Wipe > Format Data (type yes)"
	ui_print "BEFORE rebooting, or LineageOS does not boot."
fi
# Donnees d'Android 9 (LineageOS 16.0) sous Android 10 : mise a niveau des applis et de leurs donnees au premier
# demarrage, jamais essayee sur l'unite (branche lineage-17.1 experimentale).
if grep -q 'sdkVersion="28"' /data/system/packages.xml 2>/dev/null; then
	ui_print " "
	ui_print "WARNING: /data comes from Android 9 (LineageOS 16.0)."
	ui_print "Android 10 is experimental: if anything goes wrong,"
	ui_print "Wipe > Format Data, or restore the TWRP backup."
fi

ui_print " "
ui_print "Done. To go back: restore the TWRP backup."
cleanup
exit 0
