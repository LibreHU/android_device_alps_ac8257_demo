#!/bin/bash
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Test de tools/flashable/odm-sepolicy.sh (politique ODM des commandes GED, sourcée par update-binary), sans le vendor
# de l'unite (jamais publie) : regles extraites d'un extrait de vendor_sepolicy.cil au format du stock, puis compilees
# par secilc avec les memes options que l'init d'Android 10 (init/selinux.cpp : -m -M true -G -N) dans une politique
# minimale : une regle mal formee ferait echouer la compilation de l'init, donc le demarrage.
#   tools/ci/test_odm_sepolicy.sh        (secilc requis : paquet secilc)
set -e

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$MY_DIR/../flashable/odm-sepolicy.sh"
command -v secilc >/dev/null || { echo "secilc manquant (paquet secilc)" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Lignes au format exact du vendor_sepolicy.cil stock : attribut et types sources, classes file / dir / chr_file,
# regle sans ioctl, autre cible
cat > "$T/vendor.cil" <<'EOF'
(type proc_ged)
(roletype object_r proc_ged)
(allow appdomain proc_ged (file (ioctl read write getattr open)))
(allow hal_graphics_composer_default proc_ged (file (ioctl read open)))
(allow surfaceflinger_28_0 proc_ged (file (ioctl read write getattr open)))
(allow carplaypluginservice_28_0 proc_ged (dir (ioctl read getattr search open)))
(allow carplaypluginservice_28_0 proc_ged (chr_file (ioctl read getattr open)))
(allow ged_srv proc_ged (file (read open)))
(allow hal_graphics_composer_default proc_gpulog (file (ioctl read open)))
EOF

ged_odm_cil "$T/vendor.cil" > "$T/odm.cil"
cat > "$T/expected.cil" <<EOF
$ODM_SEPOLICY_MARK
; generated from /vendor/etc/selinux/vendor_sepolicy.cil by tools/flashable/odm-sepolicy.sh
(allowx appdomain proc_ged (ioctl file ((range 0x6700 0x670c) (range 0x6764 0x6769))))
(allowx hal_graphics_composer_default proc_ged (ioctl file ((range 0x6700 0x670c) (range 0x6764 0x6769))))
(allowx surfaceflinger_28_0 proc_ged (ioctl file ((range 0x6700 0x670c) (range 0x6764 0x6769))))
EOF
diff -u "$T/expected.cil" "$T/odm.cil"

# Vendor sans regle GED : rien n'est ecrit
grep -v proc_ged "$T/vendor.cil" > "$T/none.cil"
ged_odm_cil "$T/none.cil" > "$T/odm-none.cil"
[ ! -s "$T/odm-none.cil" ]
# Vendor illisible : code 1
! ged_odm_cil "$T/absent.cil" >/dev/null

# Politique minimale (MLS comme Android) avec les sources et la cible du test
cat > "$T/base.cil" <<'EOF'
(class file (ioctl read write getattr open))
(class dir (ioctl read getattr search open))
(class chr_file (ioctl read getattr open))
(classorder (file dir chr_file))
(sid kernel)
(sidorder (kernel))
(mls true)
(handleunknown allow)
(sensitivity s0)
(sensitivityorder (s0))
(category c0)
(categoryorder (c0))
(sensitivitycategory s0 (c0))
(user u)
(role r)
(userrole u r)
(userlevel u (s0))
(userrange u ((s0) (s0)))
(type kernel_t)
(roletype r kernel_t)
(role object_r)
(sidcontext kernel (u r kernel_t ((s0) (s0))))
(typeattribute appdomain)
(type platform_app)
(roletype r platform_app)
(typeattributeset appdomain (platform_app))
(type hal_graphics_composer_default)
(roletype r hal_graphics_composer_default)
(type surfaceflinger_28_0)
(roletype r surfaceflinger_28_0)
(type carplaypluginservice_28_0)
(roletype r carplaypluginservice_28_0)
(type ged_srv)
(roletype r ged_srv)
(type proc_gpulog)
(roletype object_r proc_gpulog)
(allow kernel_t self (file (read)))
EOF
secilc "$T/base.cil" -m -M true -G -N -c 30 -o "$T/policy" -f /dev/null "$T/vendor.cil" "$T/odm.cil"
echo "odm-sepolicy: OK ($(grep -c '^(allowx' "$T/odm.cil") rules, compiled by secilc)"
