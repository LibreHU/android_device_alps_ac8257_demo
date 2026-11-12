#!/usr/bin/env python3
"""TWRP zip of a LineageOS build for the UJC201, installed by tools/flashable/update-binary.sh.

LineageOS 16.0's own zip (`mka bacon`, ota_from_target_files.py) cannot be made for this tree: no recovery
(TARGET_NO_RECOVERY: "target build has specified no recovery") and no kernel built (TARGET_NO_KERNEL). This one holds:
- system.img as a raw image cut in pieces of --chunk-mib MiB (each under 2 GiB: no zip64, which TWRP's unzip may not
  read), written to the partition at their offsets and checked against the SHA-256 of the whole image;
- boot.img / boot-bootmenu.img: prebuilt/boot-librehu*.img (tools/fetch_kernel.sh: LibreHU kernel, stock AVB footer,
  androidboot.selinux=permissive);
- modules/: the connectivity modules of that kernel (prebuilt/modules), for /vendor/lib/modules.

    tools/make_flashable_zip.py <system.img (sparse or raw)> <prebuilt dir> <out.zip> [--build NAME] [--chunk-mib N]
"""
import argparse
import hashlib
import os
import struct
import zipfile

SPARSE_MAGIC = 0xED26FF3A
HERE = os.path.dirname(os.path.abspath(__file__))


def raw_blocks(path):
    """The raw image's bytes, in pieces: a sparse image (Android sparse format, libsparse) expanded, a raw one read."""
    with open(path, "rb") as f:
        head = f.read(28)
        if len(head) < 28 or struct.unpack_from("<I", head)[0] != SPARSE_MAGIC:
            f.seek(0)
            while True:
                b = f.read(1 << 20)
                if not b:
                    return
                yield b
        _, major, _, file_hdr, chunk_hdr, blk, total_blks, total_chunks, _ = struct.unpack("<IHHHHIIII", head)
        if major != 1:
            raise SystemExit(f"{path}: sparse version {major}")
        f.seek(file_hdr)
        zero = bytes(1 << 20)
        for _ in range(total_chunks):
            ctype, _, csz, tsz = struct.unpack("<HHII", f.read(12))
            f.seek(chunk_hdr - 12, 1)
            n = csz * blk
            if ctype == 0xCAC1:  # raw
                while n:
                    b = f.read(min(n, 1 << 20))
                    if not b:
                        raise SystemExit(f"{path}: truncated")
                    n -= len(b)
                    yield b
            elif ctype == 0xCAC2:  # fill
                fill = f.read(4) * (1 << 18)
                while n:
                    k = min(n, len(fill))
                    n -= k
                    yield fill[:k]
            elif ctype == 0xCAC3:  # don't care: zeros in a raw image
                while n:
                    k = min(n, len(zero))
                    n -= k
                    yield zero[:k]
            elif ctype == 0xCAC4:  # crc32
                f.read(4)
            else:
                raise SystemExit(f"{path}: unknown chunk 0x{ctype:x}")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("system")
    ap.add_argument("prebuilt")
    ap.add_argument("out")
    ap.add_argument("--build", default="")
    ap.add_argument("--chunk-mib", type=int, default=1024)
    a = ap.parse_args()
    chunk = a.chunk_mib << 20
    boots = {"boot.img": "boot-librehu.img", "boot-bootmenu.img": "boot-librehu-bootmenu.img"}
    mods = os.path.join(a.prebuilt, "modules")
    for p in [os.path.join(a.prebuilt, v) for v in boots.values()] + [os.path.join(mods, n) for n in ("SHA256SUMS", "kernel_version")]:
        if not os.path.isfile(p):
            raise SystemExit(f"{p} missing: run tools/fetch_kernel.sh first")

    with zipfile.ZipFile(a.out, "w", zipfile.ZIP_DEFLATED, allowZip64=False) as z:
        def add_bytes(name, data, mode=0o644):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.external_attr = mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)

        add_bytes("META-INF/com/google/android/update-binary", open(os.path.join(HERE, "flashable", "update-binary.sh"), "rb").read(), 0o755)
        add_bytes("META-INF/com/google/android/updater-script", b"# LibreHU: the installer is update-binary (tools/flashable/update-binary.sh)\n")

        # system: raw pieces of `chunk` bytes, the hash of the whole image
        whole = hashlib.sha256()
        names, size, part, out = [], 0, None, None

        def next_part():
            nonlocal part, out
            if out:
                out.close()
            part = f"system.img.{len(names):03d}"
            names.append(part)
            info = zipfile.ZipInfo(part, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            out = z.open(info, "w", force_zip64=False)

        in_part = 0
        for b in raw_blocks(a.system):
            whole.update(b)
            while b:
                if out is None or in_part == chunk:
                    next_part()
                    in_part = 0
                k = min(len(b), chunk - in_part)
                out.write(b[:k])
                in_part += k
                size += k
                b = b[k:]
        if out:
            out.close()

        boot_sums = []
        for name, src in boots.items():
            p = os.path.join(a.prebuilt, src)
            z.write(p, name)
            boot_sums.append(f"{sha256(p)}  {name}")
        for n in sorted(os.listdir(mods)):
            if n.endswith(".ko") or n in ("SHA256SUMS", "kernel_version", "release.txt"):
                z.write(os.path.join(mods, n), f"modules/{n}")

        add_bytes("info/build", (a.build or "unknown") + "\n")
        add_bytes("info/system.size", f"{size}\n")
        add_bytes("info/system.chunk_mib", f"{a.chunk_mib}\n")
        add_bytes("info/system.chunks", " ".join(names) + "\n")
        add_bytes("info/system.sha256", whole.hexdigest() + "\n")
        add_bytes("info/SHA256SUMS", "\n".join(boot_sums) + "\n")
    print(f"{a.out}: system {size} bytes in {len(names)} pieces, sha256 {whole.hexdigest()}, {os.path.getsize(a.out)} bytes")


if __name__ == "__main__":
    main()
