#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: Apache-2.0
#
# Applis LibreHU integrees a /system/app (APK telecharges par fetch_apks.sh, signature d'origine gardee).
# Un APK absent est simplement ignore : la ROM se construit sans lui.
#

LOCAL_PATH := $(call my-dir)

ifneq ($(wildcard $(LOCAL_PATH)/LibreHUService.apk),)
include $(CLEAR_VARS)
LOCAL_MODULE := LibreHUService
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := LibreHUService.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := false
include $(BUILD_PREBUILT)
endif

ifneq ($(wildcard $(LOCAL_PATH)/LibreHULauncher.apk),)
include $(CLEAR_VARS)
LOCAL_MODULE := LibreHULauncher
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := LibreHULauncher.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := false
# Seul ecran d'accueil de la ROM
LOCAL_OVERRIDES_PACKAGES := Launcher3 Launcher3QuickStep TrebuchetQuickStep
include $(BUILD_PREBUILT)
endif

ifneq ($(wildcard $(LOCAL_PATH)/LibreHUOTA.apk),)
include $(CLEAR_VARS)
LOCAL_MODULE := LibreHUOTA
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := LibreHUOTA.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := false
include $(BUILD_PREBUILT)
endif
