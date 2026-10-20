#
# Copyright (C) 2026 The LineageOS Project
# Copyright (C) 2026 LibreHU
#
# SPDX-License-Identifier: Apache-2.0
#
# LineageOS 16.0 (Android 9) pour l'UJC201 (Jancar, Autochips AC8257).
# Phase 1 : systeme LineageOS + partition vendor stock (Android 9, VNDK 28, Treble) + noyau stock #72.
#

DEVICE_PATH := device/alps/ac8257_demo

# Architecture (Cortex-A53 x 8)
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53

TARGET_BOARD_SUFFIX := _64
TARGET_USES_64_BIT_BINDER := true

# Bootloader / plateforme (ro.product.board et ro.board.platform du stock)
TARGET_BOOTLOADER_BOARD_NAME := ac8257_demo
TARGET_NO_BOOTLOADER := true
TARGET_BOARD_PLATFORM := ac8257

# Display (1280 x 720 en paysage, ro.sf.lcd_density=160 du stock)
TARGET_SCREEN_DENSITY := 160

# Kernel : noyau stock #72 (22/01/2026) en prebuilt, voir prebuilt/README.md.
# Plus tard : noyau LibreHU (android_kernel_autochips_ac8257_4.9, branche LibreHU-main).
BOARD_BOOTIMG_HEADER_VERSION := 1
BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 buildvariant=user
# Mise au point : SELinux permissif comme le stock (summary du dump : Permissive), a retirer ensuite
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11a88000
BOARD_KERNEL_TAGS_OFFSET := 0x07808000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
# La partition dtbo stock est gardee : pas de dtbo.img construit.

# Partitions (table eMMC du noyau stock #72)
BOARD_FLASH_BLOCK_SIZE := 131072 # (BOARD_KERNEL_PAGESIZE * 64)
BOARD_BOOTIMAGE_PARTITION_SIZE := 10485760          # boot   0x00a00000
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432      # recovery 0x02000000
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 3221225472      # system 0xc0000000
BOARD_VENDORIMAGE_PARTITION_SIZE := 2147483648      # vendor 0x80000000
BOARD_CACHEIMAGE_PARTITION_SIZE := 452984832        # cache  0x1b000000
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_HAS_LARGE_FILESYSTEM := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_COPY_OUT_VENDOR := vendor

# System-as-root (ro.build.system_root_image=true du stock)
BOARD_BUILD_SYSTEM_ROOT_IMAGE := true

# Vendor stock (Android 9, PPR1.180610.011) : image lue sur l'unite par tools/get_vendor_img.sh,
# jamais publiee dans ce depot. Ne pas definir BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE : sinon le build
# d'Android 9 reconstruit une vendor depuis les sources et ignore celle-ci (build/core/Makefile).
BOARD_PREBUILT_VENDORIMAGE := vendor/jancar/ac8257_demo/vendor.img

# Treble / VNDK (ro.vndk.version=28)
BOARD_VNDK_VERSION := current

# Recovery : on garde TWRP (branche twrp) ; le recovery LineageOS n'est pas a flasher.
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.ac8257
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888

# Verified Boot : rien n'est signe ni desactive automatiquement. vbmeta se passe a la main :
#   fastboot --disable-verity flash vbmeta vbmeta.img
BOARD_AVB_ENABLE := false

# SELinux : la politique vendor est dans la partition vendor stock (Treble, mapping 28.0)

# Security patch (vendor stock)
VENDOR_SECURITY_PATCH := 2021-10-05

# Proprietaires (cote system, voir proprietary-files.txt)
-include vendor/jancar/ac8257_demo/BoardConfigVendor.mk
