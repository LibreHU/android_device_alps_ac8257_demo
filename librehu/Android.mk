#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: Apache-2.0
#
# Applis LibreHU integrees a /system/app (APK telecharges par fetch_apks.sh, signature d'origine gardee).
# Un APK absent est simplement ignore : la ROM se construit sans lui.
# Precompiles a la construction (dexpreopt, filtre speed via PRODUCT_DEXPREOPT_SPEED_APPS de device.mk) sans retirer
# le dex de l'APK (nostripping) : la signature d'origine reste valable et une mise a jour dans /data s'installe.
#

LOCAL_PATH := $(call my-dir)

ifneq ($(wildcard $(LOCAL_PATH)/LibreHUService.apk),)
include $(CLEAR_VARS)
LOCAL_MODULE := LibreHUService
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := LibreHUService.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := nostripping
include $(BUILD_PREBUILT)
endif

ifneq ($(wildcard $(LOCAL_PATH)/LibreHULauncher.apk),)
include $(CLEAR_VARS)
LOCAL_MODULE := LibreHULauncher
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := LibreHULauncher.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := nostripping
# Seul ecran d'accueil de la ROM
LOCAL_OVERRIDES_PACKAGES := Launcher3 Launcher3QuickStep TrebuchetQuickStep
include $(BUILD_PREBUILT)
endif

# ViPER4Android LibreHU (2.1.1, edition librehu-service) : priv-app, MODIFY_AUDIO_ROUTING est privilegiee
# (liste blanche privapp-permissions-com.llsl.viper4android.xml, LineageOS impose ro.control_privapp_permissions=enforce).
# Le pilote ViPERFX_RE de la meme version va dans l'image vendor : tools/vendor_add_viper.sh.
ifneq ($(wildcard $(LOCAL_PATH)/LibreHUViPER.apk),)
include $(CLEAR_VARS)
LOCAL_MODULE := LibreHUViPER
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := LibreHUViPER.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := nostripping
LOCAL_PRIVILEGED_MODULE := true
LOCAL_REQUIRED_MODULES := privapp-permissions-com.llsl.viper4android.xml
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE := privapp-permissions-com.llsl.viper4android.xml
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_RELATIVE_PATH := permissions
LOCAL_SRC_FILES := privapp-permissions-com.llsl.viper4android.xml
include $(BUILD_PREBUILT)
endif

ifneq ($(wildcard $(LOCAL_PATH)/LibreHUOTA.apk),)
include $(CLEAR_VARS)
LOCAL_MODULE := LibreHUOTA
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := LibreHUOTA.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := nostripping
include $(BUILD_PREBUILT)
endif

# Les autres applis LibreHU, toutes dans /system/app comme le service (mises a jour ensuite par l'appli OTA) :
# telephone, radio FM, widgets, touches au volant, sources, CD / DVD, outils MCU, Android Auto, CarPlay.
LIBREHU_SYSTEM_APPS := LibreHUDialer LibreHUFM LibreHUWidgets LibreHUBtnRemap LibreHUEasySource LibreHUDisc \
    LibreHUMcuTools LibreHUAndroidAuto LibreHUCarPlay

define librehu-system-app
ifneq ($$(wildcard $$(LOCAL_PATH)/$(1).apk),)
include $$(CLEAR_VARS)
LOCAL_MODULE := $(1)
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $$(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := $(1).apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := nostripping
include $$(BUILD_PREBUILT)
endif
endef

$(foreach app,$(LIBREHU_SYSTEM_APPS),$(eval $(call librehu-system-app,$(app))))
