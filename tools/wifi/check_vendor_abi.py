#!/usr/bin/env python3
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Can a vendor binary built in this Android 10 tree run on the stock Android 9 vendor of the UJC201 (VNDK 28)?

    tools/wifi/check_vendor_abi.py <tree> <out> <elf> [<elf>...]

For each ELF (wpa_supplicant, the vendor copy of android.hardware.wifi.supplicant@1.2.so...): every NEEDED library is
looked up, in the order the vendor linker namespace of the unit would see it, among the other ELFs given (shipped
with them in /vendor/lib64), the VNDK 28 snapshot (prebuilts/vndk/v28: vndk-core, vndk-sp) and the LLNDK of the
system (libc, libm, libdl, liblog...: <out>/system/lib64). A library found nowhere is a vendor library that must
already be on the unit: listed, to check there (ls /vendor/lib64). Then every undefined, non-weak dynamic symbol
must be exported by one of the libraries found: a symbol missing from VNDK 28 means the binary needs a newer library
than the unit has, and would not start. Exit 1 if a symbol is missing.
"""
import os
import re
import subprocess
import sys

LLNDK = {"libc.so", "libm.so", "libdl.so", "liblog.so", "libnativewindow.so", "libsync.so", "libvndksupport.so",
         "libEGL.so", "libGLESv1_CM.so", "libGLESv2.so", "libGLESv3.so", "libandroid_net.so", "libmediandk.so",
         "libvulkan.so", "libclang_rt.asan-aarch64-android.so"}


def readelf(args, path):
    return subprocess.run(["readelf", "-W"] + args + [path], check=True, capture_output=True, text=True).stdout


def needed(path):
    return re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", readelf(["-d"], path))


def dynsyms(path):
    """(defined, undefined strong) dynamic symbol names, version suffixes removed"""
    defined, undef = set(), set()
    for line in readelf(["--dyn-syms"], path).splitlines():
        f = line.split()
        if len(f) < 8 or not f[0].rstrip(":").isdigit():
            continue
        bind, ndx, name = f[4], f[6], f[7].split("@")[0]
        if not name:
            continue
        if ndx == "UND":
            if bind != "WEAK":
                undef.add(name)
        else:
            defined.add(name)
    return defined, undef


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    tree, out, elfs = sys.argv[1], sys.argv[2], sys.argv[3:]
    v28 = os.path.join(tree, "prebuilts/vndk/v28/arm64/arch-arm64-armv8-a/shared")
    dirs = [("shipped", os.path.dirname(e)) for e in elfs] + \
           [("vndk-28", os.path.join(v28, "vndk-core")), ("vndk-sp-28", os.path.join(v28, "vndk-sp"))]
    llndk_dir = os.path.join(out, "system/lib64")
    shipped = {os.path.basename(e): e for e in elfs}
    bad = 0
    for elf in elfs:
        print(f"== {elf}")
        exports = set()
        for lib in needed(elf):
            where = None
            if lib in shipped:
                where = ("shipped", shipped[lib])
            elif lib in LLNDK and os.path.exists(os.path.join(llndk_dir, lib)):
                where = ("llndk", os.path.join(llndk_dir, lib))
            else:
                for kind, d in dirs[len(elfs):]:
                    if os.path.exists(os.path.join(d, lib)):
                        where = (kind, os.path.join(d, lib))
                        break
            if where is None:
                print(f"   NEEDED {lib}: not in VNDK 28 nor LLNDK -> must be in /vendor/lib64 of the unit")
                continue
            print(f"   NEEDED {lib}: {where[0]}")
            exports |= dynsyms(where[1])[0]
        missing = sorted(dynsyms(elf)[1] - exports)
        # symbols of vendor libraries we cannot see here are not counted as missing
        unknown_libs = [lib for lib in needed(elf) if lib not in shipped and lib not in LLNDK and
                        not any(os.path.exists(os.path.join(d, lib)) for _, d in dirs[len(elfs):])]
        if missing and unknown_libs:
            print(f"   {len(missing)} undefined symbol(s) not found in the libraries above (some may come from "
                  f"{', '.join(unknown_libs)}):")
        elif missing:
            print(f"   MISSING {len(missing)} symbol(s): the unit's VNDK 28 does not have them")
            bad = 1
        for s in missing[:60]:
            print(f"     {s}")
    sys.exit(bad)


if __name__ == "__main__":
    main()
