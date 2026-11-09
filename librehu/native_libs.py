#!/usr/bin/env python3
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
"""Native libraries of the LibreHU APKs of this folder, for librehu/Android.mk and device.mk. Run by fetch_apks.sh.

Android 9 never extracts the native libraries of a system app that was not updated (PackageManagerService
derivePackageAbi: "We shouldn't attempt to extract libs from system app when it was not updated"): a priv-app
loads them from <app>/lib/<isa>/, or straight from the APK when they are stored uncompressed and 4 KiB aligned.
And the build of LineageOS 16.0 rewrites a PRESIGNED prebuilt APK whose libraries are compressed
(core/prebuilt_internal.mk, uncompress-shared-libs: zip -d + zip -0), which strips its APK Signature Scheme v2
block: PackageManager then refuses the app ("Signature stripped?").

So, for each APK:
  - ABI: arm64-v8a if the APK has libraries for it, else armeabi-v7a (32-bit app: LOCAL_MULTILIB := 32);
  - libraries of that ABI all stored and aligned: nothing to do (normal prebuilt app, the build leaves it as is);
  - otherwise "raw" install: <App>.raw is written (the ABI) and the libraries are extracted to <App>-lib/<isa>/;
    Android.mk installs the APK untouched in /system/priv-app/<App>/ and device.mk copies <App>-lib/<isa>/*.so to
    /system/priv-app/<App>/lib/<isa>/ (no dexpreopt for such an app: Android compiles it at first boot).
<App>.abi32 marks a 32-bit-only app. Files of an earlier run are replaced.

  native_libs.py <folder>
"""
import shutil
import struct
import sys
import zipfile
from pathlib import Path

ISA = {"arm64-v8a": "arm64", "armeabi-v7a": "arm"}


def data_offset(f, info):
    f.seek(info.header_offset)
    h = f.read(30)
    name_len, extra_len = struct.unpack("<HH", h[26:30])
    return info.header_offset + 30 + name_len + extra_len


def main(folder):
    folder = Path(folder)
    for apk in sorted(folder.glob("*.apk")):
        app = apk.stem
        raw, abi32, libdir = folder / f"{app}.raw", folder / f"{app}.abi32", folder / f"{app}-lib"
        for p in (raw, abi32):
            p.unlink(missing_ok=True)
        shutil.rmtree(libdir, ignore_errors=True)
        z = zipfile.ZipFile(apk)
        libs = {}
        for i in z.infolist():
            parts = i.filename.split("/")
            if len(parts) == 3 and parts[0] == "lib" and parts[2].endswith(".so") and parts[1] in ISA:
                libs.setdefault(parts[1], []).append(i)
        abi = "arm64-v8a" if "arm64-v8a" in libs else ("armeabi-v7a" if "armeabi-v7a" in libs else None)
        if abi is None:
            print(f"{app}: no native library")
            continue
        if abi == "armeabi-v7a":
            abi32.write_text("armeabi-v7a\n")
        with open(apk, "rb") as f:
            bad = [i.filename for i in libs[abi] if i.compress_type != zipfile.ZIP_STORED or data_offset(f, i) % 4096]
        if not bad:
            print(f"{app}: {abi}, {len(libs[abi])} libraries loadable from the APK")
            continue
        out = libdir / ISA[abi]
        out.mkdir(parents=True)
        for i in libs[abi]:
            (out / i.filename.split("/")[2]).write_bytes(z.read(i))
        raw.write_text(abi + "\n")
        print(f"{app}: {abi}, {len(bad)} of {len(libs[abi])} libraries compressed or unaligned: raw install, "
              f"libraries extracted to {out.relative_to(folder)}/")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
