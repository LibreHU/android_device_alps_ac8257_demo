#
# Copyright (C) 2026 The LineageOS Project
# Copyright (C) 2026 LibreHU
#
# SPDX-License-Identifier: Apache-2.0
#

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/lineage_ac8257_demo.mk

# userdebug seulement : en user, SELinux est toujours enforcing, adb demande l'autorisation et les domaines
# permissifs de sepolicy/private sont refuses au build (system/sepolicy/Android.mk).
COMMON_LUNCH_CHOICES := \
    lineage_ac8257_demo-userdebug
