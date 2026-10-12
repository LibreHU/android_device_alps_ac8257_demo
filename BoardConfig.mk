#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 SebaUbuntu's TWRP device tree generator
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/alps/ac8257_demo

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := true

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 := 
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := generic

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := generic

# APEX
OVERRIDE_TARGET_FLATTEN_APEX := true

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := ac8257_demo
TARGET_NO_BOOTLOADER := true

# Display
TARGET_SCREEN_DENSITY := 160

# Kernel
BOARD_BOOTIMG_HEADER_VERSION := 1
BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 buildvariant=user androidboot.selinux=permissive
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11a88000
BOARD_KERNEL_TAGS_OFFSET := 0x07808000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
BOARD_KERNEL_SEPARATED_DTBO := true
TARGET_KERNEL_CONFIG := ac8257_demo_defconfig
TARGET_KERNEL_SOURCE := kernel/alps/ac8257_demo

# Kernel - prebuilt : noyau stock UJC201-V1.151R6-260122_0427-RH-C0-CYA (#72 du 22 janvier 2026), extrait du recovery stock,
# patche "skip_initramfs" -> "want_initramfs" (le LK ajoute skip_initramfs hors mode recovery).
# prebuilt/dtbo.img = recovery_dtbo du recovery stock 250718.
TARGET_FORCE_PREBUILT_KERNEL := true
ifeq ($(TARGET_FORCE_PREBUILT_KERNEL),true)
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img
BOARD_KERNEL_SEPARATED_DTBO := 
endif

# Partitions
BOARD_BUILD_SYSTEM_ROOT_IMAGE := true
BOARD_FLASH_BLOCK_SIZE := 131072 # (BOARD_KERNEL_PAGESIZE * 64)
BOARD_BOOTIMAGE_PARTITION_SIZE := 10485760
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR := vendor

# Platform
TARGET_BOARD_PLATFORM := ac8257

# Recovery
BOARD_INCLUDE_RECOVERY_DTBO := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
BOARD_USES_MTK_HARDWARE := true
TARGET_USES_MKE2FS := true

# Security patch level
VENDOR_SECURITY_PATCH := 2021-10-05

# Verified Boot
# NE PAS signer le recovery avec une cle de test : le vbmeta stock chaine "recovery" avec la cle Jancar
# et le fs_mgr d'Android 9 rejette une cle differente (avb_slot_verify result 5) -> kernel panic -> bootloop.
# tools/ujc201_postprocess.py pose a la place la signature AVB du recovery stock (erreur de hash seulement,
# toleree car device_state=unlocked).
BOARD_AVB_ENABLE := false

# Hack: prevent anti rollback
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := 2099-12-31
PLATFORM_VERSION := 16.1.0
BOARD_HAS_NO_SELECT_BUTTON := true

# TWRP Configuration
# Dalle MIPI 720x1280 (fb0 portrait) montee en paysage : rotation 90 (persist.twrp.rotation, voir init.recovery.ac8257.rc)
TW_THEME := landscape_hdpi
TARGET_SCREEN_WIDTH := 1280
TARGET_SCREEN_HEIGHT := 720
TW_EXTRA_LANGUAGES := true
TW_DEFAULT_LANGUAGE := en
# JAMAIS de FBIOBLANK : apres une extinction, le kthread Jancar "set lcd power off" coupe la dalle
# juste apres le rallumage (ecran noir). TW_SCREEN_BLANK_ON_BOOT est donc interdit ; l'appel
# FBIOBLANK de l'init fbdev de minui est neutralise par tools/ujc201_postprocess.py.
TW_NO_SCREEN_BLANK := true
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_USE_TOOLBOX := true
# Luminosite : pilote Jancar inverse (0 = max, 179 = min). TWRP ecrit dans /tmp/twbl, touchfix convertit.
TW_BRIGHTNESS_PATH := "/tmp/twbl"
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 180
TW_FRAMERATE := 60
TW_NO_BATT_PERCENT := true
TW_NO_SCREEN_TIMEOUT := true
# Barre d'etat : fichier ecrit par touchfix (temperature mtktscpu + tension d'entree)
TW_CUSTOM_CPU_TEMP_PATH := "/tmp/twcpu"

TW_HAS_MTP := true
RECOVERY_SDCARD_ON_DATA := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_FUSE_EXFAT := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP := true
TW_EXCLUDE_TWRPAPP := true
TW_EXCLUDE_APEX := true
TW_BACKUP_EXCLUSIONS := /data/fonts
TW_DEVICE_VERSION := UJC201-AC8257
