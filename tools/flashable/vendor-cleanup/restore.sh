#!/sbin/sh
# LibreHU: puts back the files the LibreHU zip removed from vendor and jancar (see README.md next to this script).
# Run from TWRP: sh <this folder>/restore.sh. files.txt: one line per entry, tab-separated:
# part (vendor / jancar), type (d / f / l), mode, uid, gid, SELinux context, sha256 (files) or link target, path.
HERE=$(cd "$(dirname "$0")" && pwd)
BYNAME=/dev/block/platform/bootdevice/by-name
[ -e $BYNAME/vendor ] || BYNAME=/dev/block/by-name
TAB=$(printf '\t')
# UJC_TEST (tests on a PC): partitions already in UJC_ROOT_vendor / UJC_ROOT_jancar, nothing mounted
root() { if [ -n "$UJC_TEST" ]; then eval echo \$UJC_ROOT_$1; else echo /tmp/librehu_restore_$1; fi; }
unmount_all() { [ -n "$UJC_TEST" ] && return; for m in /tmp/librehu_restore_vendor /tmp/librehu_restore_jancar; do umount $m 2>/dev/null; rmdir $m 2>/dev/null; done; }
fail() { echo "ERROR: $1"; unmount_all; exit 1; }

[ -f "$HERE/files.txt" ] || fail "files.txt not found in $HERE"
for p in vendor jancar; do
	grep -q "^$p$TAB" "$HERE/files.txt" || continue
	[ -n "$UJC_TEST" ] && continue
	m=/tmp/librehu_restore_$p
	mkdir -p $m
	blockdev --setrw $BYNAME/$p 2>/dev/null
	mount -t ext4 -o rw $BYNAME/$p $m || fail "cannot mount $p read-write"
done

N=0
# directories first (files.txt lists a directory before its content), then files and links
while IFS="$TAB" read -r P T MODE U G CTX SUM REL; do
	D=$(root $P)/$REL
	S=$HERE/$P/$REL
	case $T in
		d) mkdir -p "$D" || fail "cannot create $D" ;;
		f)
			mkdir -p "$(dirname "$D")"
			cp "$S" "$D.librehu.new" || fail "cannot copy $REL (partition full?)"
			[ "$(sha256sum "$D.librehu.new" | cut -d' ' -f1)" = "$SUM" ] || fail "$REL: checksum differs"
			mv -f "$D.librehu.new" "$D" || fail "cannot put back $REL"
			;;
		l) rm -f "$D"; ln -s "$SUM" "$D" || fail "cannot recreate the link $REL" ;;
		*) continue ;;
	esac
	[ $T = l ] || chmod "$MODE" "$D"
	chown -h "$U:$G" "$D" 2>/dev/null
	case "$CTX" in u:*) chcon -h "$CTX" "$D" 2>/dev/null ;; esac
	N=$((N + 1))
done < "$HERE/files.txt"
sync
unmount_all
echo "$N entries put back. To keep them after the next LibreHU zip:"
echo "  touch /data/media/0/LibreHU/keep-vendor-apps"
