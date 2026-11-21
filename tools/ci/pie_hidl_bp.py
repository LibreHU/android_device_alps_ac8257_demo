#!/usr/bin/env python3
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Rewrite the Android.bp of a HIDL package of Android 10 / 11 in the form of Pie's hidl-gen.

    tools/ci/pie_hidl_bp.py <folder of the .hal files and their Android.bp>

The WPA3 CI builds vendor HALs of newer Android in the LineageOS 16.0 tree (VNDK 28: Pie's hidl-gen, libhidl and
BoringSSL are the unit's). Pie's hidl_interface lists the user-defined types of types.hal ("types", one Java class
each) and its Java generation predates the newer layout: only the vendor C++ library is used, so Java is off. The
name, root, sources and imported interfaces stay those of the original file; typedefs are not types.
"""
import os
import re
import sys


def block(text, key):
    m = re.search(r"\b" + key + r"\s*:\s*\[(.*?)\]", text, re.S)
    return re.findall(r'"([^"]+)"', m.group(1)) if m else []


def field(text, key):
    m = re.search(r"\b" + key + r'\s*:\s*"([^"]+)"', text)
    if not m:
        sys.exit(f"Android.bp: no {key}")
    return m.group(1)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    d = sys.argv[1]
    bp = os.path.join(d, "Android.bp")
    text = open(bp).read()
    name, root = field(text, "name"), field(text, "root")
    srcs = block(text, "srcs")
    interfaces = block(text, "interfaces")
    for s in srcs:
        if not os.path.isfile(os.path.join(d, s)):
            sys.exit(f"{s} listed in Android.bp is missing")
    types = []
    th = os.path.join(d, "types.hal")
    if "types.hal" in srcs and os.path.isfile(th):
        types = re.findall(r"^(?:enum|struct|union)\s+([A-Za-z0-9_]+)", open(th).read(), re.M)
    out = ["// Pie form (LibreHU tools/ci/pie_hidl_bp.py) of the hidl-gen file of a newer Android.", "",
           "hidl_interface {", f'    name: "{name}",', f'    root: "{root}",', "    vndk: {", "        enabled: true,",
           "    },", "    srcs: ["] + [f'        "{s}",' for s in srcs] + ["    ],", "    interfaces: ["] + \
          [f'        "{i}",' for i in interfaces] + ["    ],"]
    if types:
        out += ["    types: ["] + [f'        "{t}",' for t in types] + ["    ],"]
    out += ["    gen_java: false,", "}", ""]
    open(bp, "w").write("\n".join(out))
    print(f"{bp}: {name}, {len(srcs)} sources, {len(interfaces)} interfaces, types {types}")


if __name__ == "__main__":
    main()
