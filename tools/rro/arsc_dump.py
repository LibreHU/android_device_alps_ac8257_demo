#!/usr/bin/env python3
"""Dump the entries of a compiled resources.arsc (type/name = value, config qualifiers). Static parse only.

Usage: python3 -I arsc_dump.py resources.arsc
"""
import struct
import sys


def strpool(d, o):
    _, hsz, size, n, nstyle, flags, sstart, _ = struct.unpack_from("<HHIIIIII", d, o)
    utf8 = flags & 0x100
    offs = struct.unpack_from(f"<{n}I", d, o + hsz)
    out = []
    for so in offs:
        p = o + sstart + so
        if utf8:
            ln = d[p]; p += 2 if ln & 0x80 else 1
            bl = d[p]
            if bl & 0x80:
                bl = ((bl & 0x7F) << 8) | d[p + 1]; p += 2
            else:
                p += 1
            out.append(d[p:p + bl].decode("utf-8", "replace"))
        else:
            ln = struct.unpack_from("<H", d, p)[0]; p += 2
            if ln & 0x8000:
                ln = ((ln & 0x7FFF) << 16) | struct.unpack_from("<H", d, p)[0]; p += 2
            out.append(d[p:p + 2 * ln].decode("utf-16-le", "replace"))
    return out, o + size


def val(dt, data, gs):
    if dt == 0x03:
        return repr(gs[data])
    if dt == 0x12:
        return "true" if data else "false"
    if dt == 0x10:
        return str(struct.unpack("<i", struct.pack("<I", data))[0])
    if dt == 0x11:
        return hex(data)
    if dt == 0x01:
        return f"@0x{data:08x}"
    if dt == 0x02:
        return f"?0x{data:08x}"
    if dt == 0x04:
        return str(struct.unpack("<f", struct.pack("<I", data))[0])
    if dt == 0x05:
        units = ["px", "dp", "sp", "pt", "in", "mm"]
        mant = (data >> 8) * [1 / 256, 1 / 32768, 1 / 8388608, 1 / 2147483648][(data >> 4) & 3]
        return f"{mant:g}{units[data & 0xF] if (data & 0xF) < 6 else '?'}"
    if dt == 0x06:
        mant = (data >> 8) * [1 / 256, 1 / 32768, 1 / 8388608, 1 / 2147483648][(data >> 4) & 3]
        return f"{mant * 100:g}%{'p' if data & 0xF else ''}"
    if 0x1C <= dt <= 0x1F:
        return f"#{data:08x}"
    return f"(type 0x{dt:x}) 0x{data:x}"


def config(d, o):
    size = struct.unpack_from("<I", d, o)[0]
    c = d[o:o + size]
    q = []
    mcc, mnc = struct.unpack_from("<HH", c, 4)
    if mcc: q.append(f"mcc{mcc}")
    if mnc: q.append(f"mnc{mnc}")
    lang, ctry = c[8:10], c[10:12]
    if any(lang): q.append(lang.decode("latin1"))
    if any(ctry): q.append("r" + ctry.decode("latin1"))
    orient, touch, dens = c[12], c[13], struct.unpack_from("<H", c, 14)[0]
    if orient: q.append({1: "port", 2: "land"}.get(orient, f"orient{orient}"))
    if dens: q.append(f"{dens}dpi")
    if size >= 28:
        sw, sh, sdk = struct.unpack_from("<HHH", c, 20)
        if sw or sh: q.append(f"{sw}x{sh}")
        if sdk: q.append(f"v{sdk}")
    if size >= 32:
        layout, uimode, swdp = c[28], c[29], struct.unpack_from("<H", c, 30)[0]
        if uimode & 0xF: q.append({3: "car", 4: "television", 2: "desk"}.get(uimode & 0xF, f"ui{uimode & 0xF}"))
        if uimode & 0x30: q.append({0x10: "notnight", 0x20: "night"}.get(uimode & 0x30, ""))
        if swdp: q.append(f"sw{swdp}dp")
    if size >= 36:
        wdp, hdp = struct.unpack_from("<HH", c, 32)
        if wdp: q.append(f"w{wdp}dp")
        if hdp: q.append(f"h{hdp}dp")
    return "-".join(q) or "default"


def main():
    d = open(sys.argv[1], "rb").read()
    _, hsz, size, npkg = struct.unpack_from("<HHII", d, 0)
    o = hsz
    gs, o = strpool(d, o)
    while o < len(d):
        ctype, chsz, csz = struct.unpack_from("<HHI", d, o)
        if ctype != 0x0200:
            o += csz; continue
        pid = struct.unpack_from("<I", d, o + 8)[0]
        name = d[o + 12:o + 12 + 256].decode("utf-16-le").split("\0")[0]
        tstr_off, _, kstr_off, _ = struct.unpack_from("<IIII", d, o + 268)
        types, _ = strpool(d, o + tstr_off)
        keys, _ = strpool(d, o + kstr_off)
        print(f"# package 0x{pid:02x} {name}")
        p = o + chsz
        end = o + csz
        while p < end:
            t, th, ts = struct.unpack_from("<HHI", d, p)
            if t == 0x0201:
                tid = d[p + 8]
                ecount, estart = struct.unpack_from("<II", d, p + 12)
                cfg = config(d, p + 20)
                offs = struct.unpack_from(f"<{ecount}I", d, p + th)
                for i, eo in enumerate(offs):
                    if eo == 0xFFFFFFFF:
                        continue
                    e = p + estart + eo
                    esz, flags, key = struct.unpack_from("<HHI", d, e)
                    rname = f"{types[tid - 1]}/{keys[key]}"
                    if flags & 1:
                        parent, cnt = struct.unpack_from("<II", d, e + 8)
                        items = []
                        q = e + 16
                        for _ in range(cnt):
                            nm, vs, _, dt, data = struct.unpack_from("<IHBBI", d, q)
                            items.append(val(dt, data, gs)); q += 12
                        print(f"{rname} [{cfg}] = [{', '.join(items)}]")
                    else:
                        _, _, dt, data = struct.unpack_from("<HBBI", d, e + 8)
                        print(f"{rname} [{cfg}] = {val(dt, data, gs)}")
            p += ts
        o += csz


if __name__ == "__main__":
    main()
