#!/usr/bin/env python3
#
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
#
"""Checks that each APK of this folder (all installed in /system/priv-app) has every Android 9 privileged permission it
asks for in privapp-permissions-librehu.xml. LineageOS sets ro.control_privapp_permissions=enforce, where a
privileged permission of a priv-app missing from the whitelist makes system_server stop at boot (boot loop); this tree
puts it back to "log" like the stock (lineage_ac8257_demo.mk), so a miss is only a logcat warning, but the list is
kept right for a later "enforce". Run by fetch_apks.sh after each download; no dependency (reads the binary
AndroidManifest.xml itself).

  check_privapp.py <folder>     exit 1 and the missing <permission> lines when the whitelist is short
"""
import struct
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ANDROID_NAME = 0x01010003  # android:name


def strings(data, off):
    """String pool chunk at off: list of its strings (UTF-8 or UTF-16)."""
    _, hsize, _, count, _, flags, start, _ = struct.unpack_from("<HHIIIIII", data, off)
    utf8 = bool(flags & 0x100)
    offsets = struct.unpack_from(f"<{count}I", data, off + hsize)
    base = off + start
    out = []
    for o in offsets:
        p = base + o
        if utf8:
            n = data[p]
            p += 2 if n & 0x80 else 1  # length in characters
            n = data[p]
            if n & 0x80:
                n = ((n & 0x7F) << 8) | data[p + 1]
                p += 2
            else:
                p += 1
            out.append(data[p:p + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", data, p)[0]
            p += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, p)[0]
                p += 2
            out.append(data[p:p + 2 * n].decode("utf-16-le", "replace"))
    return out


def manifest(apk):
    """(package, requested permissions) of an APK, from its binary AndroidManifest.xml."""
    data = zipfile.ZipFile(apk).read("AndroidManifest.xml")
    pool, resmap, package, perms = [], [], None, set()
    off = struct.unpack_from("<HHI", data, 0)[1]
    while off < len(data):
        ctype, hsize, size = struct.unpack_from("<HHI", data, off)
        if ctype == 0x0001:
            pool = strings(data, off)
        elif ctype == 0x0180:
            resmap = list(struct.unpack_from(f"<{(size - hsize) // 4}I", data, off + hsize))
        elif ctype == 0x0102:
            _, name, astart, asize, acount = struct.unpack_from("<IIHHH", data, off + 16)
            tag = pool[name]
            attrs = {}
            for i in range(acount):
                a = off + 16 + astart + i * asize
                _, aname, raw, _, _, dtype, value = struct.unpack_from("<IIIHBBI", data, a)
                key = pool[aname] if aname < len(pool) else ""
                if aname < len(resmap) and resmap[aname] == ANDROID_NAME:
                    key = "name"
                if raw != 0xFFFFFFFF:
                    attrs[key] = pool[raw]
                elif dtype == 0x03:
                    attrs[key] = pool[value]
            if tag == "manifest":
                package = attrs.get("package")
            elif tag in ("uses-permission", "uses-permission-sdk-23", "uses-permission-sdk-m") and attrs.get("name"):
                perms.add(attrs["name"])
        off += size
    return package, perms


def main():
    here = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent)
    privileged = {l.strip() for l in (Path(__file__).parent / "privileged-permissions-android9.txt").read_text().splitlines()
                  if l.strip() and not l.startswith("#")}
    wl = {}
    for p in ET.parse(Path(__file__).parent / "privapp-permissions-librehu.xml").getroot().iter("privapp-permissions"):
        wl[p.get("package")] = {e.get("name") for e in p.iter("permission")}
    bad = 0
    for apk in sorted(here.glob("*.apk")):
        package, perms = manifest(apk)
        need = sorted(perms & privileged)
        missing = [p for p in need if p not in wl.get(package, set())]
        print(f"{apk.name}: {package}, privileged: {', '.join(need) or '-'}" + (" -> MISSING" if missing else ""))
        for p in missing:
            print(f'    <privapp-permissions package="{package}">  <permission name="{p}"/>')
            bad += 1
    if bad:
        print("privapp-permissions-librehu.xml is short: add the lines above, or LineageOS stops at boot", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
