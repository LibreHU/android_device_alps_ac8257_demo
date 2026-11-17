#!/usr/bin/env python3
# Copyright (C) 2026 LibreHU
# SPDX-License-Identifier: GPL-2.0
"""SP Flash Tool scatters of the Jancar UJC201 (AutoChips AC8257, platform MT6761) for every eMMC size and both boot
layouts, from one scatter of the unit (WwR MTK 2.50, 44 entries, CRLF):

    python3 scatter/make_scatters.py <scatter of a UJC201> [<output folder, default: scatter>]

Only two things differ between the files:
- boot layout: boot 10 MiB (stock table) or 32 MiB (table of librehu_boot32_twrp.zip: dtbo 1 MiB, tee1 / tee2 moved,
  vendor 2033 MiB, same end);
- eMMC size: the size of userdata, the last partition (it ends where otp, flashinfo and the backup GPT start:
  0x3B04200 bytes before the end of the disk). otp, flashinfo and sgpt keep their symbolic addresses 0xFFFF....
Every other line of the input is kept byte for byte. Checks: user partitions contiguous, sizes as below.
"""
import os
import re
import sys

M = 1 << 20
USERDATA_START = 0x1A0000000
TAIL = 0x2B00000 + 0x1000000 + 0x4200          # otp + flashinfo + sgpt, at the end of the disk

# eMMC size in bytes and where it comes from (README.md)
DISKS = {
    16: (int(16e9 * 0.95) // (4 * M) * (4 * M), "estimated"),
    32: (int(32e9 * 0.95) // (4 * M) * (4 * M), "estimated"),
    64: (0xE67800000, "derived"),               # Junsun V1 Pro AC8259 4/64 (WwR scatter, project ac8257_demo)
    128: (0x1D1E000000, "exact"),               # UJC201 6/128, eMMC manfid 0xdf 128SV8 (244252672 sectors)
    256: (int(256e9 * 0.95) // (4 * M) * (4 * M), "estimated"),
}
LAYOUTS = {
    10: {"boot": (0x1F200000, 0xA00000), "dtbo": (0x1FC00000, 0x800000), "tee1": (0x20400000, 0x500000),
         "tee2": (0x20900000, 0x700000), "vendor": (0x21000000, 0x80000000)},
    32: {"boot": (498 * M, 32 * M), "dtbo": (530 * M, 1 * M), "tee1": (531 * M, 5 * M),
         "tee2": (536 * M, 7 * M), "vendor": (543 * M, 2033 * M)},
}
NOTE = "# LibreHU:"


def entries(text):
    return re.split(r"(?=- partition_index: )", text)


def field(block, key):
    m = re.search(key + r": (\S+)\r\n", block)
    return m.group(1) if m else None


def setval(block, key, value):
    hits = list(re.finditer(re.escape(key) + r": (0x[0-9A-Fa-f]+)\r\n", block))
    if len(hits) != 1:
        sys.exit(f"{field(block, 'partition_name')}: {key} not found once")
    return block[:hits[0].start(1)] + "0x" + format(value, "X") + block[hits[0].end(1):]


def check(text, label, disk):
    parts = []
    for b in entries(text)[1:]:
        if field(b, "region") != "EMMC_USER":
            continue
        a = int(field(b, "linear_start_addr"), 16)
        if 0xFFFF0000 <= a <= 0xFFFFFFFF:          # symbolic: resolved from the end of the disk
            continue
        if field(b, "linear_start_addr") != field(b, "physical_start_addr"):
            sys.exit(f"{label}: linear != physical for {field(b, 'partition_name')}")
        parts.append((a, int(field(b, "partition_size"), 16), field(b, "partition_name")))
    parts.sort()
    for (a, z, n), (a2, _, n2) in zip(parts, parts[1:]):
        if a + z != a2:
            sys.exit(f"{label}: {n} ends at {a + z:#x}, {n2} starts at {a2:#x}")
    a, z, n = parts[-1]
    if n != "userdata" or a + z + TAIL != disk:
        sys.exit(f"{label}: userdata does not end {TAIL:#x} bytes before the end of the disk")


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    out_dir = sys.argv[2] if len(sys.argv) == 3 else "scatter"
    text = open(sys.argv[1], "rb").read().decode("ascii")
    if "\r\n" not in text or "platform: MT6761" not in text or "project: ac8257_demo" not in text:
        sys.exit("not a CRLF scatter of an ac8257_demo (MT6761)")
    text = "".join(l for l in text.splitlines(True) if not l.startswith(NOTE))   # a generated file as input
    if len(entries(text)) != 45:
        sys.exit("expected 44 partition entries")
    for gb, (disk, how) in DISKS.items():
        for boot, layout in LAYOUTS.items():
            out = []
            for b in entries(text):
                name = field(b, "partition_name")
                if name in layout:
                    start, size = layout[name]
                    b = setval(setval(setval(b, "linear_start_addr", start), "physical_start_addr", start),
                               "partition_size", size)
                elif name == "userdata":
                    if field(b, "linear_start_addr") != hex(USERDATA_START).upper().replace("X", "x"):
                        sys.exit("userdata does not start at 0x1A0000000")
                    b = setval(b, "partition_size", disk - TAIL - USERDATA_START)
                out.append(b)
            res = "".join(out)
            check(res, f"{gb} GB boot {boot} MiB", disk)
            head = (f"{NOTE} Jancar UJC201 (AutoChips AC8257, platform MT6761), eMMC {gb} GB, boot partition {boot} MiB"
                    f"{' (table of librehu_boot32_twrp.zip)' if boot == 32 else ' (stock table)'}.\r\n"
                    f"{NOTE} userdata size {how} for a disk of {disk:#x} bytes ({disk // 512} sectors): see"
                    f" scatter/README.md. Generated by scatter/make_scatters.py.\r\n")
            name = os.path.join(out_dir, f"AC8257_{gb}GB_boot{boot}MiB_Android_scatter.txt")
            open(name, "wb").write((head + res).encode("ascii"))
            print(f"{name}: userdata {disk - TAIL - USERDATA_START:#x} ({how})")


if __name__ == "__main__":
    main()
