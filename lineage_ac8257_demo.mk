#
# Copyright (C) 2026 The LineageOS Project
# Copyright (C) 2026 LibreHU
#
# SPDX-License-Identifier: Apache-2.0
#

# adb sans autorisation, actif des le demarrage, a chaque build : vendor/lineage/config/common.mk met alors
# ro.adb.secure=0 (au lieu de 1) et build/tools/post_process_props.py ajoute persist.sys.usb.config=adb. Pris en compte
# par adbd en userdebug et eng seulement (ALLOW_ADBD_NO_AUTH, system/core/adb/Android.mk) : en user, Android 9 exige
# toujours l'autorisation. Avant les inherit-product : common.mk le lit a son chargement, qui vient apres ce fichier.
# N'importe qui branche sur l'USB de l'unite a alors un shell (et le root une fois « Debogage root » active).
WITH_ADB_INSECURE := true

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common LineageOS stuff (modem 4G present : profil telephone).
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from ac8257_demo device
$(call inherit-product, device/alps/ac8257_demo/device.mk)

PRODUCT_DEVICE := ac8257_demo
PRODUCT_NAME := lineage_ac8257_demo
PRODUCT_BRAND := alps
PRODUCT_MODEL := UJC201_64
PRODUCT_MANUFACTURER := alps

PRODUCT_GMS_CLIENTID_BASE := android-alps

# Empreinte du vendor stock (ro.vendor.build.fingerprint)
PRODUCT_BUILD_PROP_OVERRIDES += \
    TARGET_DEVICE=ac8257_demo \
    PRODUCT_NAME=full_UJC201_64 \
    PRIVATE_BUILD_DESC="full_UJC201_64-user 9 PPR1.180610.011 1356 release-keys"

BUILD_FINGERPRINT := alps/full_UJC201_64/ac8257_demo:9/PPR1.180610.011/1356:user/release-keys
