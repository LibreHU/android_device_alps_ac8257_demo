#!/usr/bin/env python3
"""
test_adaptive_raw.py - essai sur PC du patch 6 de apply_twrp_patches.py (UJC201-adaptive-raw)

  1. Avec un chemin vers partition.cpp de TWRP (android-12.1) : applique les trois patchs a une copie, verifie que
     chaque motif est trouve une seule fois et qu'une 2e application ne change rien.
  2. Compile le code insere (ADAPT_CODE) avec des bouchons (TWFunc, ProgressTracking, PartitionManager, gui_print)
     et joue les cas sur des fichiers (la "partition" est un fichier rempli de 0xEE) :
     boot 10 -> 32 Mio et 32 -> 10 Mio avec pied AVB, contenu AVB trop grand, dtbo 8 -> 1 Mio (zeros, octet non nul,
     avec pied), 1 -> 8 Mio avec pied, meme taille, plus petite sans pied, faux pied, Install Image (ujc201_raw_fits).

Usage : test_adaptive_raw.py [bootable/recovery/partition.cpp]
"""
import os, random, shutil, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import apply_twrp_patches as atp  # noqa: E402

MiB = 1048576
STUBS = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <string>
using namespace std;
#ifndef O_LARGEFILE
#define O_LARGEFILE 0
#endif
struct TWFunc {
	static unsigned long long IOCTL_Get_Block_Size(const char *p) {
		struct stat st;
		return stat(p, &st) == 0 ? (unsigned long long)st.st_size : 0;
	}
};
struct ProgressTracking {
	unsigned long long part = 0, last = 0;
	int sets = 0;
	void SetPartitionSize(unsigned long long s) { part = s; sets++; }
	void UpdateSize(unsigned long long s) {
		if (s > part || s < last) { fprintf(stderr, "bad progress %llu / %llu\n", s, part); exit(3); }
		last = s;
	}
	void UpdateDisplayDetails(bool) {}
};
struct PartitionManagerStub { int Check_Backup_Cancel() { return 0; } } PartitionManager;
static void gui_print(const char *fmt, ...) { va_list a; va_start(a, fmt); vprintf(fmt, a); va_end(a); }
static void gui_print_color(const char *c, const char *fmt, ...)
{
	va_list a;
	printf("[%s] ", c);
	va_start(a, fmt); vprintf(fmt, a); va_end(a);
}
#define LOGINFO(...) printf("I:" __VA_ARGS__)
'''
MAIN = r'''
int main(int argc, char **argv)
{
	if (argc == 4 && !strcmp(argv[1], "restore")) {
		ProgressTracking pr;
		int r = ujc201_adaptive_restore(argv[2], argv[3], &pr);
		if (r > 0 && (pr.sets != 1 || pr.last != pr.part)) { fprintf(stderr, "progress not complete\n"); return 3; }
		printf("RESULT %d\n", r);
		return 0;
	}
	if (argc == 4 && !strcmp(argv[1], "fits")) {
		printf("FITS %d\n", ujc201_raw_fits(argv[2], strtoull(argv[3], NULL, 10)) ? 1 : 0);
		return 0;
	}
	return 2;
}
'''


def check_patches(src):
    """Les trois patchs sur une copie de partition.cpp : un motif chacun, idempotents."""
    s = open(src, encoding='utf-8').read()
    for old in (atp.ADAPT_ANCHOR, atp.RRW_OLD, atp.FLASH_OLD):
        n = s.count(old)
        assert n == 1, 'motif trouve %d fois : %r' % (n, old[:60])
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'partition.cpp')
        shutil.copy(src, p)
        for _ in range(2):
            atp.patch(p, atp.ADAPT_ANCHOR, atp.ADAPT_CODE + atp.ADAPT_ANCHOR, 'UJC201-adaptive-raw : image brute')
            atp.patch(p, atp.RRW_OLD, atp.RRW_NEW, 'int ujc201 = ujc201_adaptive_restore(')
            atp.patch(p, atp.FLASH_OLD, atp.FLASH_NEW, 'image_size > Size && !ujc201_raw_fits(')
        t = open(p, encoding='utf-8').read()
        for new in (atp.ADAPT_CODE, atp.RRW_NEW, atp.FLASH_NEW):
            assert t.count(new) == 1, 'patch present %d fois' % t.count(new)
        # fonctions definies avant leurs appels
        assert t.index('static int ujc201_adaptive_restore(') < t.index('int ujc201 = ujc201_adaptive_restore(')
        assert t.index('static bool ujc201_raw_fits(') < t.index('!ujc201_raw_fits(full_filename')
    print('patchs : un motif chacun, idempotents : OK')


def avb_image(total, img_size, vb_size=1600, stale=False, rnd=random.Random(1)):
    """Image de `total` octets : contenu, blob AVB0 a l'arrondi 4096 superieur, pied AVBf dans les 64 derniers."""
    voff = (img_size + 4095) // 4096 * 4096
    body = bytearray(rnd.getrandbits(8) | 1 for _ in range(img_size))
    blob = b'AVB0' + bytes(rnd.getrandbits(8) for _ in range(vb_size - 4))
    out = bytearray(total)
    out[:img_size] = body
    out[voff:voff + vb_size] = blob
    if stale:  # restes d'un noyau plus gros apres le contenu (un dd de partition les garde)
        out[voff + vb_size:voff + vb_size + 300000] = b'\x5a' * 300000
    out[total - 64:] = b'AVBf' + struct.pack('>IIQQQ', 1, 0, img_size, voff, vb_size) + bytes(28)
    return bytes(out), voff + vb_size


def main():
    if len(sys.argv) > 1:
        check_patches(sys.argv[1])
    cxx = shutil.which('g++') or shutil.which('clang++') or sys.exit('g++ / clang++ introuvable')
    with tempfile.TemporaryDirectory() as d:
        c = os.path.join(d, 't.cpp')
        open(c, 'w').write(STUBS + atp.ADAPT_CODE + MAIN)
        exe = os.path.join(d, 't')
        subprocess.check_call([cxx, '-std=c++17', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-O1',
                               '-o', exe, c])

        def run(*args):
            r = subprocess.run([exe] + list(args), capture_output=True, text=True)
            assert r.returncode == 0, r.stderr + r.stdout
            return r.stdout

        def restore(name, data, psize):
            src, dst = os.path.join(d, name + '.img'), os.path.join(d, name + '.part')
            open(src, 'wb').write(data)
            open(dst, 'wb').write(b'\xee' * psize)
            out = run('restore', src, dst)
            res = int(out.split('RESULT ')[1].split()[0])
            return res, open(dst, 'rb').read(), out

        fails = 0

        def case(name, ok, detail=''):
            nonlocal fails
            print('%-58s %s' % (name, 'OK' if ok else 'ECHEC ' + detail))
            fails += 0 if ok else 1

        # boot 10 -> 32 Mio : contenu, zeros jusqu'au pied, pied a la fin
        data, end = avb_image(10 * MiB, 7 * MiB)
        r, part, out = restore('boot10to32', data, 32 * MiB)
        case('boot 10 -> 32 MiB, AVB footer moved', r == 1 and part[:10 * MiB - 64] == data[:10 * MiB - 64]
             and part[10 * MiB - 64:32 * MiB - 64] == bytes(22 * MiB) and part[-64:] == data[-64:]
             and len(part) == 32 * MiB and 'AVB footer moved' in out, out)
        # boot 32 -> 10 Mio : contenu de 8 Mio + restes d'un noyau plus gros apres le contenu
        data, end = avb_image(32 * MiB, 8 * MiB, stale=True)
        r, part, out = restore('boot32to10', data, 10 * MiB)
        case('boot 32 -> 10 MiB, content 8 MiB, AVB footer moved', r == 1 and part[:end] == data[:end]
             and part[:10 * MiB - 64] == data[:10 * MiB - 64] and part[-64:] == data[-64:], out)
        # contenu de 12 Mio : refus, partition intacte
        data, end = avb_image(32 * MiB, 12 * MiB)
        r, part, out = restore('boot32big', data, 10 * MiB)
        case('boot 32 -> 10 MiB, content 12 MiB: refused, untouched', r == -1 and part == b'\xee' * (10 * MiB)
             and 'does not fit' in out and 'Nothing was written' in out, out)
        # dtbo 8 -> 1 Mio sans pied, surplus a zero
        data = bytearray(8 * MiB); data[:4] = bytes.fromhex('d7b7ab1e'); data[4:52599] = b'\x11' * (52599 - 4)
        r, part, out = restore('dtbo8to1', bytes(data), MiB)
        case('dtbo 8 -> 1 MiB, extra zeros left out', r == 1 and part == bytes(data[:MiB]) and 'extra zeros' in out, out)
        # dtbo 8 -> 1 Mio, un octet non nul a 5 Mio : refus
        data[5 * MiB] = 1
        r, part, out = restore('dtbo8nz', bytes(data), MiB)
        case('dtbo 8 -> 1 MiB, non-zero byte at 5 MiB: refused', r == -1 and part == b'\xee' * MiB
             and 'byte %d' % (5 * MiB) in out, out)
        # dtbo 8 -> 1 Mio avec pied AVB
        data, end = avb_image(8 * MiB, 52599)
        r, part, out = restore('dtbo8avb', data, MiB)
        case('dtbo 8 -> 1 MiB with AVB footer', r == 1 and part[:end] == data[:end]
             and part[MiB - 64:] == data[-64:] and part[end:MiB - 64] == data[end:MiB - 64], out)
        # dtbo 1 -> 8 Mio avec pied AVB : pied a la fin des 8 Mio
        data, end = avb_image(MiB, 52599)
        r, part, out = restore('dtbo1avb', data, 8 * MiB)
        case('dtbo 1 -> 8 MiB with AVB footer', r == 1 and part[:MiB - 64] == data[:MiB - 64]
             and part[MiB - 64:8 * MiB - 64] == bytes(7 * MiB) and part[-64:] == data[-64:], out)
        # meme taille, plus petite sans pied : code d'origine de TWRP (rien d'ecrit ici)
        data, end = avb_image(10 * MiB, 7 * MiB)
        r, part, out = restore('same', data, 10 * MiB)
        case('same size: TWRP original path', r == 0 and part == b'\xee' * (10 * MiB), out)
        r, part, out = restore('smaller', bytes(MiB), 8 * MiB)
        case('smaller without footer: TWRP original path', r == 0 and part == b'\xee' * (8 * MiB), out)
        # faux pied (pas de AVB0 a vbmeta_offset) : traite comme sans pied
        fake = bytearray(avb_image(8 * MiB, 52599)[0]); fake[53248:53252] = b'XXXX'
        r, part, out = restore('fake', bytes(fake), MiB)
        case('fake footer (no AVB0): non-zero tail refused', r == -1 and part == b'\xee' * MiB, out)
        r, part, out = restore('fakesmall', bytes(fake), 16 * MiB)
        case('fake footer, smaller image: TWRP original path', r == 0, out)
        # Install Image : test de taille de Flash_Image
        for name, data, psize, want in (
                ('boot 32 MiB (content 8) into 10 MiB', avb_image(32 * MiB, 8 * MiB)[0], 10 * MiB, 1),
                ('boot 32 MiB (content 12) into 10 MiB', avb_image(32 * MiB, 12 * MiB)[0], 10 * MiB, 0),
                ('dtbo 8 MiB (zeros) into 1 MiB', bytes(MiB) + bytes(7 * MiB), MiB, 1),
                ('dtbo 8 MiB (non-zero tail) into 1 MiB', bytes(MiB) + b'\x01' + bytes(7 * MiB - 1), MiB, 0)):
            f = os.path.join(d, 'fits.img')
            open(f, 'wb').write(data)
            out = run('fits', f, str(psize))
            case('Install Image: ' + name, ('FITS %d' % want) in out, out)
    print('patch 6 : %s' % ('tous les cas OK' if not fails else '%d ECHEC(S)' % fails))
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
