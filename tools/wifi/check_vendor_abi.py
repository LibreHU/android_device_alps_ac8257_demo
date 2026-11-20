#!/usr/bin/env python3
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Can a vendor binary built in this Android 10 tree run on the stock Android 9 vendor of the UJC201 (VNDK 28)?

    tools/wifi/check_vendor_abi.py <tree> <out> <elf> [<elf>...]

For each ELF (wpa_supplicant, the vendor copy of android.hardware.wifi.supplicant@1.2.so...): every NEEDED library is
looked up, in the order the vendor linker namespace of the unit would see it, among the other ELFs given (shipped
with them in /vendor/lib64), the VNDK 28 snapshot (prebuilts/vndk/v28: vndk-core, vndk-sp) and the LLNDK of the
system (libc, libm, libdl, liblog...: <out>/system/lib64 after a full build, else the LLNDK stubs this tree built for
the vendor variant, <out dir>/soong/.intermediates/.../<lib>.llndk: only `m wpa_supplicant` ran). Any other library is
a vendor library that must already be on the unit: listed ("not in VNDK 28 nor LLNDK"), checked again by the installer
(ls /vendor/lib64); its symbols are taken from this tree's own vendor copy (<out>/vendor/lib64, built as a dependency:
libkeystore-wifi-hidl, libkeystore-engine-wifi-hidl), same sources as the unit's. Then every undefined, non-weak
dynamic symbol must be exported by one of the libraries found: a symbol missing means the binary needs a newer
library than the unit has, and would not start. Exit 1 if a symbol is missing, or if a library cannot be looked at.
LLNDK libraries are never listed as needed in /vendor: the system provides them.
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


def llndk_stubs(out):
    """LLNDK library name -> stub of the vendor arm64 variant (<lib>.llndk modules of the tree)"""
    soong = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(out)))), "soong",
                         ".intermediates")
    found = {}
    for root, dirs, _ in os.walk(soong):
        for d in list(dirs):
            if d.endswith(".llndk") and d[:-6] + ".so" in LLNDK:
                lib = d[:-6] + ".so"
                for r2, _, files in os.walk(os.path.join(root, d)):
                    if lib in files and "arm64" in r2 and "unstripped" not in r2:
                        cand = os.path.join(r2, lib)
                        if lib not in found or len(cand) < len(found[lib]):
                            found[lib] = cand
                dirs.remove(d)
    return found


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    tree, out, elfs = sys.argv[1], sys.argv[2], sys.argv[3:]
    v28 = os.path.join(tree, "prebuilts/vndk/v28/arm64/arch-arm64-armv8-a/shared")
    dirs = [("shipped", os.path.dirname(e)) for e in elfs] + \
           [("vndk-28", os.path.join(v28, "vndk-core")), ("vndk-sp-28", os.path.join(v28, "vndk-sp"))]
    llndk_dir = os.path.join(out, "system/lib64")
    stubs = None
    tree_vendor = os.path.join(out, "vendor/lib64")
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
            elif lib in LLNDK:
                if stubs is None:
                    stubs = llndk_stubs(out)
                if lib not in stubs:
                    print(f"   NEEDED {lib}: LLNDK, but no stub of it in this tree: cannot check its symbols")
                    bad = 1
                    continue
                where = ("llndk stub", stubs[lib])
            else:
                for kind, d in dirs[len(elfs):]:
                    if os.path.exists(os.path.join(d, lib)):
                        where = (kind, os.path.join(d, lib))
                        break
            if where is None:
                copy = os.path.join(tree_vendor, lib)
                if not os.path.exists(copy):
                    print(f"   NEEDED {lib}: not in VNDK 28 nor LLNDK -> must be in /vendor/lib64 of the unit, "
                          f"and no copy in {tree_vendor} to check its symbols")
                    bad = 1
                    continue
                print(f"   NEEDED {lib}: not in VNDK 28 nor LLNDK -> must be in /vendor/lib64 of the unit "
                      f"(symbols: this tree's copy)")
                exports |= dynsyms(copy)[0]
                continue
            print(f"   NEEDED {lib}: {where[0]}")
            exports |= dynsyms(where[1])[0]
        missing = sorted(dynsyms(elf)[1] - exports)
        if missing:
            print(f"   MISSING {len(missing)} symbol(s): not exported by the libraries above")
            bad = 1
        for s in missing[:60]:
            print(f"     {s}")
    sys.exit(bad)


if __name__ == "__main__":
    main()
