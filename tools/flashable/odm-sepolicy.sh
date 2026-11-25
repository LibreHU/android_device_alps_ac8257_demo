# LibreHU - politique SELinux ODM des ROM Android 10 et plus sur le vendor stock (Android 9) de l'UJC201.
# Sourcé par update-binary (zip de la ROM) et par la CI, qui compile son résultat avec la politique de la ROM.
#
# GED (/proc/ged, pilote noyau MediaTek drivers/misc/mediatek/gpu/ged) : les bibliothèques graphiques MediaTek
# (gralloc, hwcomposer, libged des applis, mediacodec, bootanimation...) lui envoient leurs commandes par ioctl.
# La politique vendor stock les autorise par des règles simples « (allow X proc_ged (file (ioctl ...))) », sans liste
# d'ioctl : sous Android 9, toutes passent. Android 10 ajoute pour TOUS les domaines et TOUS les fichiers
#   allowxperm domain { file_type fs_type domain dev_type }:{ dir notdevfile_class_set blk_file } ioctl { FIOCLEX FIONCLEX };
# (system/sepolicy/public/domain.te, LineageOS 17.1 à 21.0) : dès qu'une règle allowxperm existe pour un triplet
# source / cible / classe, seuls les ioctl listés passent. Les commandes GED sont alors refusées (en permissif :
# journalisées, des milliers par minute, assez pour faire tourner logcat et dmesg en quelques minutes).
#
# ged_odm_cil VENDOR_CIL : écrit sur la sortie standard, pour chaque source à laquelle la politique vendor donne
# « ioctl » sur proc_ged (classe file), une règle allowx des commandes GED du noyau (ged_bridge_id.h, identiques en
# 4.9 et 4.19 : 0 à 12 et 100 à 105, type 'g' = 0x67), soit exactement ce que le vendor voulait permettre.
# Les sources viennent des règles du vendor installé lui-même : chaque nom existe donc dans la politique compilée au
# démarrage (secilc de l'init : plateforme + mapping + vendor + ce fichier). Les classes dir / chr_file d'autres
# règles ne sont pas reprises : chr_file n'est pas sous liste blanche (ajouter une règle l'y mettrait), et /proc/ged
# est un fichier. N'écrit rien si le vendor n'a aucune règle de ce type.
# Retour : 0 (règles écrites ou rien à écrire), 1 si VENDOR_CIL est illisible.

ODM_SEPOLICY_MARK="; LibreHU: GED ioctls (/proc/ged) allowed again under Android 10+"

ged_odm_cil() {
	[ -r "$1" ] || return 1
	_srcs=$(sed -n 's/^(allow \([A-Za-z0-9_]*\) proc_ged (file (\([a-z_ ]*\))))$/\1 \2/p' "$1" \
		| awk '{ for (i = 2; i <= NF; i++) if ($i == "ioctl" && !seen[$1]++) { print $1; break } }')
	[ -n "$_srcs" ] || return 0
	echo "$ODM_SEPOLICY_MARK"
	echo "; generated from /vendor/etc/selinux/vendor_sepolicy.cil by tools/flashable/odm-sepolicy.sh"
	for _s in $_srcs; do
		echo "(allowx $_s proc_ged (ioctl file ((range 0x6700 0x670c) (range 0x6764 0x6769))))"
	done
	return 0
}
