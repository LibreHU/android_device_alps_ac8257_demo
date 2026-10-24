#!/usr/bin/env python3
"""
ujc201_postprocess.py - finalise l'image TWRP pour le Jancar UJC201 (AC8257)

Ce que le build TWRP ne sait pas faire seul (constate sur l'unite, firmware 250718) :
  1. libminuitwrp.so : l'init fbdev fait FBIOBLANK (eteindre) puis FBIOBLANK (rallumer).
     Sur cette carte, l'extinction declenche le kthread Jancar "set lcd power off" qui coupe
     la dalle juste APRES le rallumage -> ecran noir. On remplace chaque `bl ioctl` precede de
     `mov w1, #0x4611` (FBIOBLANK) par `mov w0, #0`.
  2. recovery : la barre du haut affiche %tw_cpu_temp% (entier). Si le source n'a pas ete patche par
     tools/apply_twrp_patches.py (chaine "UJC201-statustext" absente), on patche la lecture pour afficher
     le contenu texte de TW_CUSTOM_CPU_TEMP_PATH (/tmp/twcpu, ecrit par touchfix) :
     temperature + tension d'entree. Patch par motifs ; si le code ne correspond pas, il est
     simplement saute (touchfix ecrit alors un nombre, affichage "CPU: xx C" classique).
  3. Theme : en-tete sans le "CPU: ... C" fige, entrees "Power info" / "USB: Host mode" / "USB: PC mode"
     dans Advanced.
  4. Signature AVB : on retire tout footer et on pose le vbmeta du recovery STOCK (cle Jancar chainee
     dans le vbmeta). Seul le hash differe -> erreur de verification toleree (device_state=unlocked).
     Une cle de test provoquerait "avb_slot_verify result 5" dans le fs_mgr d'Android -> bootloop.

Usage :
  ujc201_postprocess.py IN.img OUT.img --avb prebuilt/avb/recovery_stock_vbmeta_250718.bin
        [--kernel prebuilt/kernel] [--dtbo prebuilt/dtbo.img] [--overlay recovery/root]
"""
import argparse, gzip, hashlib, os, stat, struct, subprocess, sys, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ujc201_theme  # noqa: E402

PART_SIZE = 0x2000000  # partition recovery : 32 Mo

def log(*a): print('[ujc201]', *a)

# ---------------------------------------------------------------- boot image v1
def unpack(img):
    assert img[:8] == b'ANDROID!', 'pas une image boot Android'
    ks, ka, rs, ra, ss, sa, ta, ps, hv, osv = struct.unpack_from('<10I', img, 8)
    assert hv == 1, 'header v1 attendu (%d)' % hv
    off = 48 + 16 + 512 + 32 + 1024
    rds, rdo, hs = struct.unpack_from('<IQI', img, off)
    pad = lambda n: (n + ps - 1) // ps * ps
    k = img[ps:ps + ks]
    r = img[ps + pad(ks):ps + pad(ks) + rs]
    s = img[ps + pad(ks) + pad(rs):ps + pad(ks) + pad(rs) + ss]
    d = img[rdo:rdo + rds] if rds else b''
    return dict(hdr=bytearray(img[:ps]), ps=ps, off=off, hs=hs, kernel=k, ramdisk=r, second=s, rdtbo=d)

def repack(p):
    ps, h = p['ps'], p['hdr']
    pad = lambda n: (n + ps - 1) // ps * ps
    struct.pack_into('<I', h, 8, len(p['kernel']))
    struct.pack_into('<I', h, 16, len(p['ramdisk']))
    struct.pack_into('<I', h, 24, len(p['second']))
    dofs = ps + pad(len(p['kernel'])) + pad(len(p['ramdisk'])) + pad(len(p['second']))
    struct.pack_into('<IQI', h, p['off'], len(p['rdtbo']), dofs if p['rdtbo'] else 0, p['hs'])
    sha = hashlib.sha1()
    for b in (p['kernel'], p['ramdisk'], p['second']):
        sha.update(b); sha.update(struct.pack('<I', len(b)))
    if p['rdtbo']:
        sha.update(p['rdtbo']); sha.update(struct.pack('<I', len(p['rdtbo'])))
    h[576:608] = sha.digest().ljust(32, b'\0')
    out = bytes(h)
    for b in (p['kernel'], p['ramdisk'], p['second'], p['rdtbo']):
        if b: out += b + b'\0' * (pad(len(b)) - len(b))
    return out

# ---------------------------------------------------------------- ramdisk (cpio newc)
def rd_decompress(r):
    if r[:2] == b'\x1f\x8b': return gzip.decompress(r), 'gzip'
    if r[:4] == b'\x02\x21\x4c\x18':
        return subprocess.run(['lz4', '-dc'], input=r, stdout=subprocess.PIPE, check=True).stdout, 'lz4'
    raise SystemExit('compression du ramdisk inconnue')

def rd_compress(c, kind):
    if kind == 'gzip': return gzip.compress(c, 9, mtime=0)
    return subprocess.run(['lz4', '-l', '-12', '--favor-decSpeed'], input=c, stdout=subprocess.PIPE, check=True).stdout

def cpio_parse(c):
    ents, p = [], 0
    a4 = lambda n: (n + 3) & ~3
    while True:
        h = c[p:p + 110]; assert h[:6] == b'070701', 'cpio newc attendu'
        f = [int(h[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        nm = c[p + 110:p + 110 + f[11] - 1]
        dp = a4(p + 110 + f[11]); data = c[dp:dp + f[6]]
        ents.append([f, nm, bytearray(data)]); p = a4(dp + f[6])
        if nm == b'TRAILER!!!': return ents

def cpio_build(ents):
    a4 = lambda n: (n + 3) & ~3
    out = bytearray()
    for f, nm, data in ents:
        f = list(f); f[6] = len(data); f[11] = len(nm) + 1
        b = b'070701' + b''.join(b'%08X' % x for x in f) + nm + b'\0'
        b += b'\0' * (a4(len(b)) - len(b)); b += bytes(data); b += b'\0' * (a4(len(b)) - len(b))
        out += b
    return bytes(out)

def find(ents, name):
    for e in ents:
        if e[1] == name: return e
    return None

def put(ents, name, data, mode=0o100644):
    e = find(ents, name)
    if e:  # fichier existant : on garde son mode, on ajoute seulement le bit x si besoin
        e[2] = bytearray(data)
        if mode & 0o111: e[0][1] |= 0o755
        return
    ref = find(ents, b'init') or ents[0]
    tmpl = list(ref[0])
    tmpl[0] = 900000 + len(ents); tmpl[1] = mode; tmpl[4] = 1
    ents.insert(len(ents) - 1, [tmpl, name, bytearray(data)])

# ---------------------------------------------------------------- ELF / arm64
def elf_segments(b):
    phoff, = struct.unpack_from('<Q', b, 0x20); phentsize, phnum = struct.unpack_from('<HH', b, 0x36)
    segs = []
    for i in range(phnum):
        t, fl, off, va, pa, fsz, msz, al = struct.unpack_from('<IIQQQQQQ', b, phoff + i * phentsize)
        if t == 1: segs.append((off, va, fsz, fl))
    return segs

def va2off(segs, va):
    for off, v, sz, fl in segs:
        if v <= va < v + sz: return off + va - v
    return None

def off2va(segs, o):
    for off, v, sz, fl in segs:
        if off <= o < off + sz: return v + o - off
    return None

def text_ranges(segs):
    return [(off, off + sz) for off, v, sz, fl in segs if fl & 1]

W = lambda b, o: struct.unpack_from('<I', b, o)[0]
def is_bl(w): return (w & 0xFC000000) == 0x94000000
def bl_target(va, w):
    imm = w & 0x3FFFFFF
    if imm & 0x2000000: imm -= 0x4000000
    return va + imm * 4
def enc_bl(va, target): return 0x94000000 | (((target - va) // 4) & 0x3FFFFFF)
def is_adrp(w): return (w & 0x9F000000) == 0x90000000
def adrp_val(va, w):
    imm = (((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3)
    if imm & 0x100000: imm -= 0x200000
    return (va & ~0xFFF) + (imm << 12)
def is_addimm64(w): return (w & 0xFF800000) == 0x91000000
def add_imm(w): return (w >> 10) & 0xFFF
def enc_add_sp(rd, imm): return 0x91000000 | (imm << 10) | (31 << 5) | rd
NOP = 0xD503201F
MOV_W0_0 = 0x52800000
MOV_W1_FBIOBLANK = 0x5288C221  # mov w1, #0x4611

def patch_fbioblank(lib):
    b = bytearray(lib); n = 0
    for s, e in text_ranges(elf_segments(b)):
        for o in range(s, e - 16, 4):
            if W(b, o) == MOV_W1_FBIOBLANK:
                for k in range(1, 4):
                    if is_bl(W(b, o + 4 * k)):
                        struct.pack_into('<I', b, o + 4 * k, MOV_W0_0); n += 1; break
    return bytes(b), n

def replace_cstr(b, old, new):
    i = b.find(old + b'\0')
    if i < 0: return False
    assert len(new) <= len(old)
    b[i:i + len(old)] = new + b'\0' * (len(old) - len(new)); return True

def patch_cputemp_text(rec):
    """tw_cpu_temp : afficher le texte lu au lieu de to_string(entier) et relire a chaque rendu."""
    b = bytearray(rec); segs = elf_segments(b)
    si = b.find(b'/tmp/twcpu\0')
    if si < 0: return rec, False
    sva = off2va(segs, si)
    for s, e in text_ranges(segs):
        for o in range(s, e - 8, 4):
            w = W(b, o)
            if not is_adrp(w): continue
            va = off2va(segs, o); rd = w & 31
            w2 = W(b, o + 4)
            if not (is_addimm64(w2) and ((w2 >> 5) & 31) == rd and adrp_val(va, w) + add_imm(w2) == sva): continue
            # b.le (cache 5 s) juste avant
            ble = None
            for k in range(1, 8):
                x = W(b, o - 4 * k)
                if (x & 0xFF000010) == 0x54000000 and (x & 0xF) == 0xD: ble = o - 4 * k; break
            # bl assign, bl copy-ctor, bl getline (precede de add x1, sp, #J)
            bls = []; j = o + 8
            while len(bls) < 3 and j < o + 4 * 24:
                if is_bl(W(b, j)): bls.append(j)
                j += 4
            if ble is None or len(bls) < 3: continue
            copy_t = bl_target(off2va(segs, bls[1]), W(b, bls[1]))
            prev = W(b, bls[2] - 4)
            if not (is_addimm64(prev) and ((prev >> 5) & 31) == 31 and (prev & 31) == 1): continue
            J = add_imm(prev)
            # site to_string : add x8, sp, #K ; bl  precede de "add xN, xM, #5 ; str x, [..]" (prochaine lecture +5 s)
            for q in range(bls[2], bls[2] + 4 * 120, 4):
                x = W(b, q)
                if is_addimm64(x) and ((x >> 5) & 31) == 31 and (x & 31) == 8 and is_bl(W(b, q + 4)):
                    p2, p1 = W(b, q - 8), W(b, q - 4)
                    if is_addimm64(p2) and add_imm(p2) == 5 and (p1 & 0xFFC00000) == 0xF9000000:
                        K = add_imm(x)
                        struct.pack_into('<I', b, ble, NOP)
                        struct.pack_into('<I', b, q - 8, enc_add_sp(0, K))
                        struct.pack_into('<I', b, q - 4, enc_add_sp(1, J))
                        struct.pack_into('<I', b, q, NOP)
                        struct.pack_into('<I', b, q + 4, enc_bl(off2va(segs, q + 4), copy_t))
                        return bytes(b), True
                    break
    return rec, False

# ---------------------------------------------------------------- theme
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inp'); ap.add_argument('out')
    ap.add_argument('--avb', required=True, help='vbmeta du recovery stock (footer AVB)')
    ap.add_argument('--kernel'); ap.add_argument('--dtbo'); ap.add_argument('--overlay')
    ap.add_argument('--version', help='build tag written as ro.librehu.twrp in prop.default')
    a = ap.parse_args()

    img = open(a.inp, 'rb').read()
    p = unpack(img)
    if a.kernel: p['kernel'] = open(a.kernel, 'rb').read(); log('noyau remplace :', a.kernel)
    if a.dtbo: p['rdtbo'] = open(a.dtbo, 'rb').read(); log('recovery_dtbo remplace :', a.dtbo)
    kimg = zlib.decompressobj(31).decompress(p['kernel']) if p['kernel'][:2] == b'\x1f\x8b' else p['kernel']
    if b'want_initramfs' not in kimg:
        log('ATTENTION : noyau sans patch want_initramfs')

    c, kind = rd_decompress(p['ramdisk']); ents = cpio_parse(c)

    if a.overlay:
        for root, dirs, files in os.walk(a.overlay):
            for fn in files:
                path = os.path.join(root, fn); rel = os.path.relpath(path, a.overlay).encode()
                mode = 0o100755 if os.stat(path).st_mode & stat.S_IXUSR else 0o100644
                put(ents, rel, open(path, 'rb').read(), mode); log('overlay :', rel.decode())

    e = find(ents, b'system/lib64/libminuitwrp.so')
    lib, n = patch_fbioblank(e[2]); e[2] = bytearray(lib)
    log('FBIOBLANK neutralises :', n, '(0 = deja absent : build avec TW_NO_SCREEN_BLANK + TW_BRIGHTNESS_PATH)')

    e = find(ents, b'system/bin/recovery'); rec = bytearray(e[2])
    if replace_cstr(rec, b'/sys/class/leds/lcd-backlight/brightness', b'/tmp/twbl'): log('chemin luminosite -> /tmp/twbl')
    for z in (b'/sys/class/thermal/thermal_zone0/temp', b'/sys/class/thermal/thermal_zone1/temp'):
        if replace_cstr(rec, z, b'/tmp/twcpu'): log('chemin temperature -> /tmp/twcpu')
    if b'UJC201-statustext' in rec:
        ok, src = True, True
        log('barre d\'etat texte : deja geree par le source (tools/apply_twrp_patches.py)')
    else:
        src = False
        rec, ok = patch_cputemp_text(bytes(rec)); e[2] = bytearray(rec)
        log('barre d\'etat texte :', 'OK (patch binaire)' if ok else 'motif introuvable (affichage numerique conserve)')

    # fenetres + horloge MCU (gui/pages.cpp patche) : sinon touchfix met le titre en tete de ligne et regle l'horloge
    pop = find(ents, b'system/etc/ujc201_popup')
    if b'UJC201-popup' in rec:
        if not pop: put(ents, b'system/etc/ujc201_popup', b'1\n')
        log('fenetres : dessinees par TWRP (source patche)')
    else:
        if pop: ents.remove(pop)
        log('fenetres : bandeau du theme sur la barre de navigation (binaire sans patch pages.cpp)')

    ui = find(ents, b'twres/ui.xml')
    if not ok:
        m = find(ents, b'system/etc/ujc201_statustext')
        if m: ents.remove(m)
    if ok and not src:
        put(ents, b'system/etc/ujc201_statustext', b'1\n')
        s = bytes(ui[2]).decode()
        s = s.replace('<text>{@cpu_temp=CPU: %tw_cpu_temp% °C}</text>', '<text>%tw_cpu_temp%</text>')
        ui[2] = bytearray(s.encode())
    # theme : entrees Advanced (sortie console), tableau de bord, zone droite de la barre d'etat
    # (%property.ujc201.*% : proprietes posees par touchfix, sans patch du binaire)
    la = find(ents, b'twres/landscape.xml')
    l2, u2, msg = ujc201_theme.apply(bytes(la[2]).decode(), bytes(ui[2]).decode(),
                                     banner_on=b'UJC201-popup' not in rec)
    la[2] = bytearray(l2.encode()); ui[2] = bytearray(u2.encode())
    log('theme :', ', '.join(msg))
    # marqueur pour touchfix : zone droite presente -> pas d'etat vehicule a la suite de la ligne CPU / Vin
    car = find(ents, b'system/etc/ujc201_carstatus')
    if '%property.ujc201.car%' in u2:
        if not car: put(ents, b'system/etc/ujc201_carstatus', b'1\n')
    elif car:
        ents.remove(car)
    ban = find(ents, b'system/etc/ujc201_banner')     # touchfix : pas de titre de fenetre dans la ligne CPU
    if 'UJC201 banner begin' in u2:
        if not ban: put(ents, b'system/etc/ujc201_banner', b'1\n')
    elif ban:
        ents.remove(ban)

    pd = find(ents, b'prop.default')
    if pd and b'persist.twrp.rotation' not in pd[2]:
        pd[2] += b'\n# UJC201 : dalle 720x1280 montee en paysage\npersist.twrp.rotation=90\n'
    if pd and a.version:
        # Build checkable on the unit (getprop ro.librehu.twrp)
        pd[2] = b'\n'.join(l for l in pd[2].split(b'\n') if not l.startswith(b'ro.librehu.twrp='))
        pd[2] += b'\nro.librehu.twrp=' + a.version.encode() + b'\n'
        log('version :', a.version)

    p['ramdisk'] = rd_compress(cpio_build(ents), kind)
    cmd = bytes(p['hdr'][64:576]).rstrip(b'\0')
    if b'androidboot.selinux=permissive' not in cmd: cmd += b' androidboot.selinux=permissive'
    p['hdr'][64:576] = cmd.ljust(512, b'\0')
    out = repack(p)

    vb = open(a.avb, 'rb').read()
    assert vb[:4] == b'AVB0', 'vbmeta AVB invalide'
    voff = (len(out) + 4095) // 4096 * 4096
    assert voff + len(vb) < PART_SIZE - 64, 'image trop grande pour la partition recovery'
    o = bytearray(PART_SIZE); o[:len(out)] = out; o[voff:voff + len(vb)] = vb
    o[-64:] = b'AVBf' + struct.pack('>IIQQQ', 1, 0, len(out), voff, len(vb)) + b'\0' * 28
    open(a.out, 'wb').write(o)
    log('ecrit :', a.out, '(%d octets utiles, footer AVB stock)' % len(out))
    log('sha256 :', hashlib.sha256(o).hexdigest())

if __name__ == '__main__':
    main()
