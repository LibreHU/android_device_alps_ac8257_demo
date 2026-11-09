# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Droits des dossiers ajoutes a la racine de system (BOARD_ROOT_EXTRA_FOLDERS), ceux du stock (UJC201, Android 9),
# relevés par Reo Au In dans sa reparation du build du 07/11/2026 : /avm 0775 root:system, /jancar 0755 root:root.
# Format : build/tools/fs_config/README (TARGET_FS_CONFIG_GEN).

[avm/]
mode: 0775
user: AID_ROOT
group: AID_SYSTEM
caps: 0

[jancar/]
mode: 0755
user: AID_ROOT
group: AID_ROOT
caps: 0
