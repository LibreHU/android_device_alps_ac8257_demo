#
# Copyright (C) 2026 The LineageOS Project
# Copyright (C) 2026 LibreHU
#
# SPDX-License-Identifier: Apache-2.0
#
# LineageOS 21.0 (Android 14) pour l'UJC201 (Jancar, Autochips AC8257), branche lineage-21.0 (portage depuis
# lineage-17.1, 19/11/2026 ; jamais essaye sur l'unite).
# Systeme LineageOS 17.1 + partition vendor stock (Android 9, VNDK 28, Treble) + noyau LibreHU (image de boot de sa
# CI). Un system Android 10 sur un vendor Android 9 : bibliotheques VNDK 28 (PRODUCT_EXTRA_VNDK_VERSIONS, device.mk),
# politique SELinux du vendor compilee avec le mapping 28.0 du system, matrice de compatibilite FCM 3.
#

DEVICE_PATH := device/alps/ac8257_demo

# Architecture (Cortex-A53 x 8)
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53

TARGET_2ND_ARCH := arm
# armv8-a : le build l'impose de toute facon pour un Cortex-A53 (core/combo/TARGET_linux-arm.mk, « cortex-a53 is
# armv8-a » / « armv7-a-neon, ignored! Use armv8-a instead »).
TARGET_2ND_ARCH_VARIANT := armv8-a
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

# Kernel : noyau LibreHU (android_kernel_autochips_ac8257_4.9, branche rc-4.19.325, variante a10 depuis le
# 18/11/2026 : Linux 4.19.325, KernelSU Next ; la 16.0 garde stable-4.9.337) : image de boot de sa CI
# (BOARD_PREBUILT_BOOTIMAGE ci-dessous), avec ses modules Wi-Fi / BT / GPS / FM a mettre dans l'image vendor
# (tools/vendor_add_conn_modules.sh : il refuse ceux du stock). Voir prebuilt/README.md.
BOARD_BOOTIMG_HEADER_VERSION := 1
BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 buildvariant=user
# Mise au point : SELinux permissif comme le stock (getenforce : Permissive), a retirer ensuite. ATTENTION : cette
# ligne ne sert pas avec l'image de boot prebuilt ci-dessous ; c'est tools/fetch_kernel.sh qui ajoute
# androidboot.selinux=permissive a la ligne de commande de son en-tete (sans quoi l'init de LineageOS passe en
# enforcing). Gardee pour un boot.img construit par LineageOS.
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11a88000
BOARD_KERNEL_TAGS_OFFSET := 0x07808000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
# Image de boot : celle de la CI du noyau LibreHU, telechargee par tools/fetch_kernel.sh (en-tete, ligne de commande
# et pied AVB du boot stock, comme les zips kernel-stable). LineageOS n'en construit pas : sans le pied AVB du boot
# stock (« AVBf » a la fin de la partition, BOARD_AVB_ENABLE est a false ici), le LK refuse l'image et l'unite
# redemarre au logo sans journal du noyau (tools/ac8257/repack_boot.py du depot du noyau). Par defaut l'image avec le
# menu de demarrage (TWRP / Android / Fastboot, Android au bout de 3 s) ; LIBREHU_BOOT_IMAGE=plain pour l'autre.
# Les adresses et la ligne de commande ci-dessus sont celles de cette image (et du boot stock) ; elles ne servent
# plus a construire boot.img.
TARGET_NO_KERNEL := true
LIBREHU_BOOT_IMAGE ?= bootmenu
BOARD_PREBUILT_BOOTIMAGE := $(DEVICE_PATH)/prebuilt/boot-librehu$(if $(filter plain,$(LIBREHU_BOOT_IMAGE)),,-bootmenu).img
ifeq ($(wildcard $(BOARD_PREBUILT_BOOTIMAGE)),)
$(warning $(BOARD_PREBUILT_BOOTIMAGE) absent : lancer tools/fetch_kernel.sh avant le build)
endif
# La partition dtbo stock est gardee : pas de dtbo.img construit.

# Partitions (table eMMC du noyau stock #72)
BOARD_FLASH_BLOCK_SIZE := 131072 # (BOARD_KERNEL_PAGESIZE * 64)
# boot : 32 Mio depuis le 19/11/2026 (noyau 4.19 a10-lto32 ; la partition d'origine de 10 Mio est agrandie par
# librehu_boot32_twrp.zip, que le zip de la ROM lance lui-meme)
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432          # boot   0x02000000
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
# Android 14 : BOARD_BUILD_SYSTEM_ROOT_IMAGE est obsolete (erreur du build, run 44481815797) ; plus d'image system-as-root,
# le premier etage de l'init vient du ramdisk de l'image de boot (a revoir avec l'image de boot LibreHU).
# Points de montage de la racine du stock absents de LineageOS : /jancar (partition jancar, fstab du vendor) et /avm.
# La racine est en lecture seule : fs_mgr ne peut pas les creer (mkdir avant le montage), le montage de /jancar
# echoue, mount_all renvoie FS_MGR_MNTALL_FAIL et init ne declenche pas « nonencrypted », qui lance la classe main
# (zygote...) : Android ne demarre pas (AOSP pie, fs_mgr.cpp et init/builtins.cpp, queue_fs_event). Reperes par
# Reo Au In (reparation du build du 07/11/2026). /vendor est cree par le build (BOARD_PREBUILT_VENDORIMAGE).
# Droits du stock : config.fs ; labels : sepolicy/private/file_contexts.
BOARD_ROOT_EXTRA_FOLDERS := avm jancar
TARGET_FS_CONFIG_GEN := $(DEVICE_PATH)/config.fs

# Vendor stock (Android 9, PPR1.180610.011) : image lue sur l'unite par tools/get_vendor_img.sh,
# jamais publiee dans ce depot. Ne pas definir BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE : sous Android 9 le build
# reconstruirait une vendor depuis les sources et ignorerait celle-ci (build/core/Makefile) ; sous Android 10
# BOARD_PREBUILT_VENDORIMAGE suffit a l'en empecher (core/board_config.mk, BUILDING_VENDOR_IMAGE), mais LineageOS ne
# met TARGET_USES_PREBUILT_VENDOR_SEPOLICY a true que sans BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE
# (device/lineage/sepolicy/common/sepolicy.mk), et le reglage fuseblk ci-dessous en depend.
BOARD_PREBUILT_VENDORIMAGE := vendor/jancar/ac8257_demo/vendor.img

# autochips.jar dans PRODUCT_BOOT_JARS (device.mk) : check-boot-jars (droidcore, donc `m` par defaut) le refuserait
# (paquets com.autochips.* / vendor.autochips.* absents de build/make/core/tasks/check_boot_jars/package_whitelist.txt,
# et un jar prebuilt n'a pas le classes.jar que lit la verification : core/tasks/boot_jars_package_check.mk)
SKIP_BOOT_JARS_CHECK := true

# Politique audio : audio_policy_configuration.xml du vendor, comme le stock (son logcat : APM::Serializer,
# APM::VolumeCurve). Android 10 ne lit plus que ce format mais exige toujours le drapeau : sans lui,
# AudioPolicyManager.cpp s'arrete sur « #error Audio policy no longer supports legacy .conf configuration format »
# (frameworks/av/services/audiopolicy/managerdefault/Android.mk et AudioPolicyManager.cpp, lineage-17.1 : « TODO:
# after Q release, remove this check » ; build CI du 15/11/2026).
USE_XML_AUDIO_POLICY_CONF := 1

# Bluetooth d'autoradio : bluetooth/bdroid_buildcfg.h (classe d'appareil « Car audio », A2DP sink compile) ; profils
# voiture dans overlay/packages/apps/Bluetooth.
BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR := $(DEVICE_PATH)/bluetooth

# Treble / VNDK (ro.vndk.version=28) : le system Android 10 garde aussi les bibliotheques VNDK 28 du vendor stock
# (PRODUCT_EXTRA_VNDK_VERSIONS := 28 dans device.mk, prebuilts/vndk/v28).
BOARD_VNDK_VERSION := current

# APEX aplatis (dossiers dans /system/apex, sans image ni dm-verity par APEX au demarrage) : valeur par defaut
# d'Android 10 pour un appareil qui n'herite pas de updatable_apex.mk (core/board_config.mk), donnee ici
# explicitement. Un appareil lance avec Android 9, noyau 4.19 (a10) de LibreHU.
# Android 14 n'a plus d'APEX aplatis (TARGET_FLATTEN_APEX retire) : APEX en images.

# Recovery : on garde TWRP (branche twrp) ; LineageOS ne construit ni n'installe de recovery (et ne fait donc pas de
# zip : images flashees par fastboot, voir docs/BUILD.md).
TARGET_NO_RECOVERY := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/etc/fstab.ac8257
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888

# Verified Boot : rien n'est signe ni desactive automatiquement. vbmeta se passe a la main, avec les DEUX options :
#   fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img   (vbmeta stock)
# Le vbmeta stock chaine la partition system (descripteur « chain system », cle Jancar) : le LK et l'init (montage de
# vendor, drapeau avb du fstab du DT) lisent alors le vbmeta du pied AVB de system. Le system.img de LineageOS n'en a
# pas (BOARD_AVB_ENABLE := false) : libavb rend ERROR_INVALID_METADATA, fatal meme deverrouille
# (external/avb/libavb/avb_slot_verify.c, result_should_continue ; system/core/fs_mgr/fs_mgr_avb.cpp). Avec
# --disable-verification, la chaine n'est plus lue (drapeau VERIFICATION_DISABLED). --disable-verity seul ne suffit
# que pour le system stock.
BOARD_AVB_ENABLE := false

# SELinux : la politique vendor est dans la partition vendor stock (Treble, mapping 28.0) ; cote system, le domaine
# de mcu_ready (sans domaine, l'init d'Android 9 et 10 refuse de lancer le service, meme en permissif).
# Android 11+ : BOARD_PLAT_PRIVATE_SEPOLICY_DIR est remplace par SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS (build/make/Changes.md).
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/private

# LineageOS etiquette fuseblk en vfat (device/lineage/sepolicy/common/private/genfs_contexts), le vendor Jancar en
# sdcardfs : au demarrage, secilc refuse ces deux genfscon et l'init, sans politique, redemarre en bootloader (premier
# essai du build de la CI sous LineageOS 16.0, 12/11/2026). LineageOS 17.1 retire sa ligne avec ce reglage
# (device/lineage/sepolicy/common/sepolicy.mk : board_excludes_fuseblk_sepolicy, avec
# TARGET_USES_PREBUILT_VENDOR_SEPOLICY, vrai ici) ; la CI verifie plat_sepolicy.cil apres le build.
TARGET_HAS_FUSEBLK_SEPOLICY_ON_VENDOR := true
ifeq ($(shell grep -s -c 'board_excludes_fuseblk_sepolicy' device/lineage/sepolicy/common/private/genfs_contexts),0)
$(warning PORT lineage-21.0 : genfscon fuseblk de LineageOS sans la condition board_excludes_fuseblk_sepolicy (sources changees ?) : conflit avec le vendor Jancar)
endif
# Le LK de Jancar annonce androidboot.verifiedbootstate=green meme deverrouille (et, vbmeta en VERIFICATION_DISABLED,
# aucun androidboot.vbmeta.*) : fs_mgr de LineageOS croit alors l'unite verrouillee, refuse le vbmeta modifie par
# fastboot, vendor ne se monte pas et l'init redemarre en bootloader avant meme SELinux (essais du 12/11/2026,
# console-ramoops : "ERROR_VERIFICATION isn't allowed when the device is LOCKED"). tools/patch_lineage_sources.sh :
# unite deverrouillee sauf vbmeta.device_state=locked explicite, dans les deux copies du test d'Android 10 (fs_mgr.cpp
# et libfs_avb/util.cpp).
ifeq ($(shell grep -s -c 'librehu_vbmeta_state' system/core/fs_mgr/fs_mgr.cpp),0)
$(warning PORT lineage-21.0 : fs_mgr de LineageOS non corrige (LK Jancar : verifiedbootstate=green) : lancer device/alps/ac8257_demo/tools/patch_lineage_sources.sh depuis la racine des sources)
endif
ifeq ($(shell grep -s -c 'librehu_vbmeta_state' system/core/fs_mgr/libfs_avb/util.cpp),0)
$(warning PORT lineage-21.0 : libfs_avb de LineageOS non corrige (LK Jancar : verifiedbootstate=green) : lancer device/alps/ac8257_demo/tools/patch_lineage_sources.sh depuis la racine des sources)
endif
# Dalle en portrait montee en paysage et retroeclairage inverse (tools/lineage-patches, appliques par le meme script) :
# sans eux, image et tactile en portrait (premier demarrage du 12/11/2026) et luminosite a l'envers.
ifeq ($(shell grep -s -c 'librehuDisplayRotation' frameworks/native/services/inputflinger/InputReader.cpp),0)
$(warning PORT lineage-21.0 : frameworks/native sans la rotation de la dalle : lancer device/alps/ac8257_demo/tools/patch_lineage_sources.sh depuis la racine des sources)
endif
ifeq ($(shell grep -s -c 'librehu.backlight_inverted' frameworks/base/services/core/java/com/android/server/lights/LightsService.java),0)
$(warning PORT lineage-21.0 : frameworks/base sans le retroeclairage inverse : lancer device/alps/ac8257_demo/tools/patch_lineage_sources.sh depuis la racine des sources)
endif
# autochips.jar (PRODUCT_BOOT_JARS) en module Soong : Android 10 construit l'image de demarrage dans Soong, le module
# Make du depot vendor donnerait « failed to find dex jar path for module "autochips" » (meme script).
ifneq ($(shell grep -qs 'name: "autochips"' vendor/jancar/ac8257_demo/Android.bp && echo yes),yes)
$(warning PORT lineage-21.0 : autochips.jar sans module Soong (vendor/jancar/ac8257_demo/Android.bp) : lancer device/alps/ac8257_demo/tools/patch_lineage_sources.sh depuis la racine des sources)
endif

# Wi-Fi : wpa_supplicant de LineageOS 17.1 avec le HAL android.hardware.wifi.supplicant@1.2 (WPA3 / SAE et OWE : Android 10+
# ne les active qu'avec le 1.2, source.android.com wifi-wpa3-owe ; celui du vendor Android 9 a le 1.1) et la bibliotheque
# privee MediaTek (wifi/lib_driver_cmd_mt66xx). Construit a part par .github/workflows/wifi-wpa3.yml (m wpa_supplicant),
# installe dans /vendor par les zips, jamais dans une image vendor (BOARD_PREBUILT_VENDORIMAGE) ; wpa_supplicant n'est
# pas dans PRODUCT_PACKAGES : la build de la ROM ne le compile pas.
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_mt66xx
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_mt66xx

# Security patch (vendor stock)
VENDOR_SECURITY_PATCH := 2021-10-05

# Proprietaires (cote system, voir proprietary-files.txt)
-include vendor/jancar/ac8257_demo/BoardConfigVendor.mk

# Portage Android 14 : regles du build d'Android 11+ assouplies pour les fichiers du vendor stock (Android 9) et
# l'arbre commun (build/make/Changes.md) ; a resserrer une fois le portage demarre.
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_PREBUILT_ELF_FILES := true
BUILD_BROKEN_MISSING_REQUIRED_MODULES := true
BUILD_BROKEN_VENDOR_PROPERTY_NAMESPACE := true
BUILD_BROKEN_ENFORCE_SYSPROP_OWNER := true
BUILD_BROKEN_USES_BUILD_COPY_HEADERS := true
BUILD_BROKEN_VINTF_PRODUCT_COPY_FILES := true
BUILD_BROKEN_INCORRECT_PARTITION_IMAGES := true

# CI : precompilation (dexpreopt) de l'image de demarrage et de system_server seulement : build bien plus court (les
# builds depassaient la limite de 6 h des runners GitHub, 19/11/2026) ; les applis sont compilees sur l'unite.
WITH_DEXPREOPT_BOOT_IMG_AND_SYSTEM_SERVER_ONLY := true
