#!/usr/bin/env python3
"""
apply_twrp_patches.py - patchs source TWRP (bootable/recovery, branche android-12.1) pour le Jancar UJC201

  1. data.cpp : tw_cpu_temp affiche tel quel le texte de TW_CUSTOM_CPU_TEMP_PATH s'il contient "CPU"
     (barre d'etat ecrite par touchfix : temperature + tension d'entree). Sinon comportement d'origine.
  2. Theme landscape_hdpi/ui.xml : en-tete "%tw_cpu_temp%" au lieu de "CPU: %tw_cpu_temp% °C".
  3. Theme (tools/ujc201_theme.py) : entrees Advanced (sortie des scripts dans la console), page graphique
     "Vehicle / MCU dashboard" et zone droite de la barre d'etat, via %property.ujc201.<nom>% (proprietes posees
     par touchfix ; aucun patch du binaire necessaire, applique aussi par ujc201_postprocess.py).
  4. gui/pages.cpp : fenetres "snackbar" dessinees par-dessus toutes les pages (texte /tmp/twpopup ecrit par
     touchfix : feux allumes, touche au volant, invite de wheelkeys) + reglage de l'horloge sur l'heure du MCU
     (/tmp/mcu_time, heure locale -> mktime() dans le fuseau TWRP).
  5. gui/ (objects.hpp, pages.hpp, pages.cpp) : navigation aux touches (touches au volant de touchfix, clavier USB),
     code dans tools/keynav/keynav.inc : cadre sur l'element actif, fleches / VOL+ VOL- / OK, listes, clavier a
     l'ecran, glissiere de confirmation (OK deux fois). Les elements sont repertories au chargement de la page.
  6. partition.cpp : restauration et Install Image d'une image brute d'une autre taille que la partition (boot
     10 <-> 32 Mio, dtbo 8 <-> 1 Mio du zip boot32) : pied AVB recopie a la fin de la partition, surplus de zeros
     laisse de cote, refus avant toute ecriture sinon (essais sur PC : tools/test_adaptive_raw.py).

L'ecran (FBIOBLANK) n'a pas besoin de patch source : TW_NO_SCREEN_BLANK + TW_BRIGHTNESS_PATH +
TW_MAX_BRIGHTNESS font ecrire fbdev_blank() dans le fichier de luminosite au lieu de l'ioctl.

Usage : apply_twrp_patches.py <workspace>/bootable/recovery   (idempotent)
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ujc201_theme  # noqa: E402

MARK = 'UJC201-statustext'

DATA_OLD = '''		value = TWFunc::to_string(convert_temp);
		return 0;
	}
	return -1;
}'''
DATA_NEW = '''#ifdef TW_CUSTOM_CPU_TEMP_PATH
		{
			/* UJC201-statustext : ligne de texte prete a afficher (ecrite par touchfix) */
			string txt;
			if (TWFunc::read_file(EXPAND(TW_CUSTOM_CPU_TEMP_PATH), txt) == 0 && txt.find("CPU") != string::npos) {
				while (!txt.empty() && (txt.back() == '\\n' || txt.back() == '\\r'))
					txt.pop_back();
				value = txt;
				return 0;
			}
		}
#endif
		value = TWFunc::to_string(convert_temp);
		return 0;
	}
	return -1;
}'''
DATA_INIT_OLD = '''	if (TWFunc::Path_Exists(cpu_temp_file)) {
		mConst.SetValue("tw_no_cpu_temp", "0");'''
DATA_INIT_NEW = '''	printf("UJC201-statustext\\n");
	if (TWFunc::Path_Exists(cpu_temp_file)) {
		mConst.SetValue("tw_no_cpu_temp", "0");'''

UI_OLD = '<text>{@cpu_temp=CPU: %tw_cpu_temp% °C}</text>'
UI_NEW = '<text>%tw_cpu_temp%</text>'

MISC_OLD = '''  if (!ReadDefaultFstab(&fstab)) {
    *err = "failed to read default fstab";
    return "";
  }
  for (const auto& entry : fstab) {
    if (entry.mount_point == "/misc") {
      return entry.blk_device;
    }
  }

  *err = "failed to find /misc partition";
  return "";'''

MISC_NEW = '''  if (ReadDefaultFstab(&fstab)) {
    for (const auto& entry : fstab) {
      if (entry.mount_point == "/misc") {
        return entry.blk_device;
      }
    }
  }

  // UJC201-misc-para-fallback: on AC8257, the bootloader message (BCB) is stored in "para".
  // TWRP's generated /etc/fstab does not expose this partition as /misc.
  const std::string ujc201_para = "/dev/block/platform/bootdevice/by-name/para";
  struct stat st;
  if (stat(ujc201_para.c_str(), &st) == 0) {
    return ujc201_para;
  }

  *err = "failed to read default fstab or find /misc/UJC201 para device";
  return "";'''


PAGES_RENDER_OLD = """int PageManager::Render(void)
{
	if (blankTimer.isScreenOff())
		return 0;

	int res = (mCurrentSet ? mCurrentSet->Render() : -1);
	if (mMouseCursor)"""
PAGES_RENDER_NEW = """/* ---- UJC201-popup : fenetres vehicule par-dessus toutes les pages + horloge MCU ----
 * /tmp/twpopup (ecrit par touchfix) : une ligne par fenetre "<W|K|I>\\t<titre>\\t<texte>" ; vide = aucune.
 *   W = avertissement (feux allumes), K = touche au volant, I = invite (wheelkeys learn).
 * /tmp/mcu_time (touchfix, trame MCU 0x09) : "AAAA-MM-JJ hh:mm:ss <ms monotone>" en heure LOCALE ;
 *   convertie avec mktime() dans le fuseau TWRP (variable TZ), refaite si le fuseau change. */
#include <errno.h>
#include <math.h>
static std::string ujc201_popup_txt, ujc201_clock_raw, ujc201_clock_tz;

static long long ujc201_mono_ms(void)
{
	timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static void ujc201_clock_sync(void)
{
	std::string s;
	if (TWFunc::read_file("/tmp/mcu_time", s) != 0)
		return;
	const char* tz = getenv("TZ");
	std::string tzs = tz ? tz : "";
	if (s == ujc201_clock_raw && tzs == ujc201_clock_tz)
		return;
	ujc201_clock_raw = s;
	ujc201_clock_tz = tzs;
	int Y, M, D, h, m, sec;
	long long mono = 0;
	if (sscanf(s.c_str(), "%d-%d-%d %d:%d:%d %lld", &Y, &M, &D, &h, &m, &sec, &mono) < 6 || Y < 2024 || Y > 2099)
		return;
	struct tm tm;
	memset(&tm, 0, sizeof(tm));
	tm.tm_year = Y - 1900; tm.tm_mon = M - 1; tm.tm_mday = D;
	tm.tm_hour = h; tm.tm_min = m; tm.tm_sec = sec; tm.tm_isdst = -1;
	tzset();
	time_t t = mktime(&tm);
	if (t == (time_t)-1)
		return;
	long long el = mono > 0 ? ujc201_mono_ms() - mono : 0;
	if (el < 0 || el > 24LL * 3600 * 1000)
		el = 0;
	t += (time_t)(el / 1000);
	long long diff = (long long)t - (long long)time(NULL);
	if (diff > -3 && diff < 3)
		return;
	struct timeval tv;
	tv.tv_sec = t;
	tv.tv_usec = (suseconds_t)((el % 1000) * 1000);
	if (settimeofday(&tv, NULL) == 0)
		LOGINFO("UJC201-popup: horloge reglee sur le MCU (%04d-%02d-%02d %02d:%02d:%02d, TZ=%s, ecart %lld s)\\n",
			Y, M, D, h, m, sec, tzs.c_str(), diff);
	else
		LOGINFO("UJC201-popup: settimeofday : %s\\n", strerror(errno));
}

static int ujc201_popup_update(void)
{
	static long long last_poll = 0, last_clock = 0;
	long long t = ujc201_mono_ms();
	if (t - last_clock >= 1000) {
		last_clock = t;
		ujc201_clock_sync();
	}
	if (t - last_poll < 120)
		return 0;
	last_poll = t;
	std::string s;
	if (TWFunc::read_file("/tmp/twpopup", s) != 0)
		s.clear();
	if (s == ujc201_popup_txt)
		return 0;
	ujc201_popup_txt = s;
	return 2;
}

static void ujc201_rrect(int x, int y, int w, int h, int r)
{
	if (r * 2 > h) r = h / 2;
	if (r * 2 > w) r = w / 2;
	for (int i = 0; i < r; i++) {
		float yy = r - i - 0.5f;
		int in = r - (int)(sqrtf((float)(r * r) - yy * yy) + 0.5f);
		gr_fill(x + in, y + i, w - 2 * in, 1);
		gr_fill(x + in, y + h - 1 - i, w - 2 * in, 1);
	}
	gr_fill(x, y + r, w, h - 2 * r);
}

static void ujc201_popup_render(void)
{
	if (ujc201_popup_txt.empty())
		return;
	const ResourceManager* rm = PageManager::GetResources();
	FontResource* ft = rm ? rm->FindFont("font_l") : NULL;
	FontResource* fs = rm ? rm->FindFont("font_m") : NULL;
	if (!ft || !fs || !ft->GetResource() || !fs->GetResource())
		return;
	std::vector<std::string> kind, title, text;
	size_t p = 0;
	while (p < ujc201_popup_txt.size() && kind.size() < 4) {
		size_t e = ujc201_popup_txt.find('\\n', p);
		if (e == std::string::npos) e = ujc201_popup_txt.size();
		std::string l = ujc201_popup_txt.substr(p, e - p);
		p = e + 1;
		size_t a = l.find('\\t');
		if (a == std::string::npos) continue;
		size_t b = l.find('\\t', a + 1);
		kind.push_back(l.substr(0, a));
		title.push_back(l.substr(a + 1, b == std::string::npos ? std::string::npos : b - a - 1));
		text.push_back(b == std::string::npos ? "" : l.substr(b + 1));
	}
	int n = kind.size();
	if (!n)
		return;
	static bool said = false;
	if (!said) { LOGINFO("UJC201-popup: fenetres actives\\n"); said = true; }
	int W = gr_fb_width(), H = gr_fb_height();
	int ht = ft->GetHeight(), hs = fs->GetHeight();
	int pad = H / 48, r = H / 90, bar = H / 120 + 2;
	int ch = pad * 2 + ht + hs + pad / 3;
	int cw = W * 56 / 100, x = (W - cw) / 2;
	int bottom = H - H * 8 / 100 - pad;              /* au-dessus de la barre de navigation du theme */
	for (int i = 0; i < n; i++) {
		int y = bottom - (n - i) * (ch + pad) + pad;
		unsigned char ar = 0x00, ag = 0x90, ab = 0xCA;  /* accent TWRP */
		if (kind[i] == "W") { ar = 0xFF; ag = 0xB3; ab = 0x00; }
		else if (kind[i] == "I") { ar = 0x76; ag = 0xFF; ab = 0x03; }
		gr_color(0, 0, 0, 40);  ujc201_rrect(x - 3, y + 1, cw + 6, ch + 6, r + 3);   /* ombre */
		gr_color(0, 0, 0, 60);  ujc201_rrect(x - 1, y + 2, cw + 2, ch + 3, r + 1);
		gr_color(ar, ag, ab, 255); ujc201_rrect(x, y, cw, ch, r);                 /* bande d'accent */
		gr_color(0x32, 0x32, 0x32, 255); ujc201_rrect(x + bar, y, cw - bar, ch, r);
		int is = ch - pad * 2, ix = x + bar + pad, iy = y + pad;                  /* icone */
		gr_color(ar, ag, ab, 255); ujc201_rrect(ix, iy, is, is, is / 2);
		if (kind[i] == "K") {                                                       /* volant */
			int k = is / 7;
			gr_color(0x32, 0x32, 0x32, 255); ujc201_rrect(ix + k, iy + k, is - 2 * k, is - 2 * k, is / 2 - k);
			gr_color(ar, ag, ab, 255);
			gr_fill(ix + k, iy + is / 2 - k / 2, is - 2 * k, k);
			gr_fill(ix + is / 2 - k / 2, iy + is / 2, k, is / 2 - k);
			ujc201_rrect(ix + is / 2 - k, iy + is / 2 - k, 2 * k, 2 * k, k);
		} else {
			gr_color(0x32, 0x32, 0x32, 255);
			gr_textEx_scaleW(ix + is / 2, iy + is / 2, kind[i] == "W" ? "!" : "i", ft->GetResource(), is, CENTER, 0);
		}
		int tx = ix + is + pad, tw = x + cw - pad - tx;
		if (kind[i] == "W") gr_color(ar, ag, ab, 255); else gr_color(0xEE, 0xEE, 0xEE, 255);
		gr_textEx_scaleW(tx, y + pad, title[i].c_str(), ft->GetResource(), tw, TOP_LEFT, 1);
		gr_color(0xBD, 0xBD, 0xBD, 255);
		gr_textEx_scaleW(tx, y + pad + ht + pad / 3, text[i].c_str(), fs->GetResource(), tw, TOP_LEFT, 1);
	}
}

int PageManager::Render(void)
{
	if (blankTimer.isScreenOff())
		return 0;

	int res = (mCurrentSet ? mCurrentSet->Render() : -1);
	if (res >= 0)
		ujc201_popup_render();
	if (mMouseCursor)"""
PAGES_UPDATE_OLD = """	int res = (mCurrentSet ? mCurrentSet->Update() : -1);

	if (mMouseCursor)
	{
		int c_res = mMouseCursor->Update();"""
PAGES_UPDATE_NEW = """	int res = (mCurrentSet ? mCurrentSet->Update() : -1);

	if (mCurrentSet && res >= 0) {
		/* UJC201 : fenetre apparue / changee -> rendu complet ; visible -> pas de rendu partiel par-dessus */
		int pr = ujc201_popup_update();
		if (pr > res)
			res = pr;
		if (res == 1 && !ujc201_popup_txt.empty())
			res = 2;
	}

	if (mMouseCursor)
	{
		int c_res = mMouseCursor->Update();"""

# 6. partition.cpp : image brute d'une autre taille que la partition (restauration et Install Image).
# Code C++ insere avant TWPartition::Raw_Read_Write ; aussi compile et essaye sur PC par tools/test_adaptive_raw.py.
ADAPT_ANCHOR = 'bool TWPartition::Raw_Read_Write(PartitionSettings *part_settings) {'
ADAPT_CODE = r'''/* ---- UJC201-adaptive-raw : image brute d'une autre taille que la partition ----
 * Apres le zip boot32 de LibreHU (boot 10 -> 32 Mio, dtbo 8 -> 1 Mio) ou son zip de retour, les sauvegardes TWRP et les
 * images d'avant n'ont plus la taille de la partition. Restauration (Restore_Image) et Install Image (Flash_Image) :
 * - image avec pied AVB ("AVBf" version 1 dans ses 64 derniers octets, blob "AVB0" a vbmeta_offset ; libavb
 *   avb_footer.h) : le contenu [0, vbmeta_offset + vbmeta_size) est ecrit, puis des zeros, puis le pied dans les
 *   64 derniers octets de la partition (le LK lit le pied a la fin de la partition) ; refus si le contenu ne tient pas ;
 * - image plus grande sans pied : ecrite a la taille de la partition seulement si tout ce qui depasse est a zero ;
 * - meme taille, ou image plus petite sans pied : comportement d'origine de TWRP.
 * Tout est decide AVANT la premiere ecriture : un refus laisse la partition intacte. */
#define UJC201_RAW_CHUNK 1048576ULL

static unsigned long long ujc201_be(const unsigned char *p, int n)
{
	unsigned long long v = 0;
	for (int i = 0; i < n; i++)
		v = (v << 8) | p[i];
	return v;
}

static bool ujc201_pread(int fd, void *buf, unsigned long long len, unsigned long long off)
{
	unsigned long long done = 0;
	while (done < len) {
		ssize_t r = pread64(fd, (char *)buf + done, (size_t)(len - done), (off64_t)(off + done));
		if (r <= 0)
			return false;
		done += (unsigned long long)r;
	}
	return true;
}

static bool ujc201_pwrite(int fd, const void *buf, unsigned long long len, unsigned long long off)
{
	unsigned long long done = 0;
	while (done < len) {
		ssize_t r = pwrite64(fd, (const char *)buf + done, (size_t)(len - done), (off64_t)(off + done));
		if (r <= 0)
			return false;
		done += (unsigned long long)r;
	}
	return true;
}

/* mode : 0 = TWRP d'origine, 1 = tronquee a la partition (surplus a zero), 2 = pied AVB deplace, -1 = refus (why) */
struct ujc201_raw_plan {
	int mode;
	unsigned long long content_end;
	unsigned char footer[64];
	char why[192];
};

static void ujc201_raw_plan_for(int src_fd, unsigned long long fsz, unsigned long long psz, struct ujc201_raw_plan *p)
{
	unsigned char magic[4];

	memset(p, 0, sizeof(*p));
	if (psz == 0 || fsz == psz)
		return;
	if (fsz >= 128 && ujc201_pread(src_fd, p->footer, 64, fsz - 64) && memcmp(p->footer, "AVBf", 4) == 0) {
		unsigned long long major = ujc201_be(p->footer + 4, 4);
		unsigned long long img = ujc201_be(p->footer + 12, 8);
		unsigned long long voff = ujc201_be(p->footer + 20, 8);
		unsigned long long vsz = ujc201_be(p->footer + 28, 8);
		if (major == 1 && vsz > 0 && voff >= img && voff <= fsz - 64 && vsz <= fsz - 64 - voff &&
				ujc201_pread(src_fd, magic, 4, voff) && memcmp(magic, "AVB0", 4) == 0) {
			p->content_end = voff + vsz;
			if (psz < 128 || p->content_end > psz - 64) {
				p->mode = -1;
				snprintf(p->why, sizeof(p->why), "the AVB image content (%llu bytes) does not fit in the "
						"partition (%llu bytes)", p->content_end, psz);
			} else
				p->mode = 2;
			return;
		}
	}
	if (fsz < psz)
		return;
	unsigned char *buf = (unsigned char *)malloc(UJC201_RAW_CHUNK);
	if (!buf) {
		p->mode = -1;
		snprintf(p->why, sizeof(p->why), "out of memory");
		return;
	}
	p->mode = 1;
	for (unsigned long long off = psz; off < fsz && p->mode == 1; ) {
		unsigned long long n = fsz - off < UJC201_RAW_CHUNK ? fsz - off : UJC201_RAW_CHUNK;
		if (!ujc201_pread(src_fd, buf, n, off)) {
			p->mode = -1;
			snprintf(p->why, sizeof(p->why), "cannot read the image (%s)", strerror(errno));
			break;
		}
		for (unsigned long long i = 0; i < n; i++) {
			if (buf[i]) {
				p->mode = -1;
				snprintf(p->why, sizeof(p->why), "the image (%llu bytes) is larger than the partition (%llu bytes) "
						"and its extra bytes are not all zeros (byte %llu)", fsz, psz, off + i);
				break;
			}
		}
		off += n;
	}
	free(buf);
}

/* Ecrit l'image selon le plan (mode 1 ou 2) ; progression ramenee a la taille du fichier */
static bool ujc201_raw_write(int src_fd, int dst_fd, unsigned long long fsz, unsigned long long psz,
		const struct ujc201_raw_plan *p, ProgressTracking *progress)
{
	unsigned long long body = p->mode == 2 ? psz - 64 : psz;
	unsigned long long from_file = body;
	if (p->mode == 2 && fsz - 64 < body)
		from_file = fsz - 64;
	unsigned char *buf = (unsigned char *)malloc(UJC201_RAW_CHUNK);
	if (!buf)
		return false;
	bool ok = true;
	for (unsigned long long off = 0; ok && off < body; ) {
		unsigned long long n = body - off < UJC201_RAW_CHUNK ? body - off : UJC201_RAW_CHUNK;
		unsigned long long f = 0;
		if (off < from_file)
			f = from_file - off < n ? from_file - off : n;
		if (f && !ujc201_pread(src_fd, buf, f, off))
			ok = false;
		if (ok) {
			memset(buf + f, 0, (size_t)(n - f));
			ok = ujc201_pwrite(dst_fd, buf, n, off);
		}
		off += n;
		if (progress)
			progress->UpdateSize((unsigned long long)((double)off * (double)fsz / (double)psz));
		if (ok && PartitionManager.Check_Backup_Cancel() != 0)
			ok = false;
	}
	free(buf);
	if (ok && p->mode == 2)
		ok = ujc201_pwrite(dst_fd, p->footer, 64, psz - 64);
	if (ok)
		ok = fsync(dst_fd) == 0;
	if (ok && progress)
		progress->UpdateSize(fsz);
	return ok;
}

/* Restauration / Install Image : 0 = cas ordinaire (code d'origine), 1 = ecrit, -1 = refus (rien ecrit) ou erreur */
static int ujc201_adaptive_restore(const string &srcfn, const string &dstfn, ProgressTracking *progress)
{
	struct stat64 st;
	struct ujc201_raw_plan p;
	int src_fd = open(srcfn.c_str(), O_RDONLY | O_LARGEFILE);
	if (src_fd < 0)
		return 0;
	unsigned long long fsz = fstat64(src_fd, &st) == 0 ? (unsigned long long)st.st_size : 0;
	unsigned long long psz = TWFunc::IOCTL_Get_Block_Size(dstfn.c_str());
	ujc201_raw_plan_for(src_fd, fsz, psz, &p);
	if (p.mode == 0) {
		close(src_fd);
		return 0;
	}
	if (p.mode < 0) {
		gui_print_color("error", "%s: %s. Nothing was written.\n", srcfn.c_str(), p.why);
		close(src_fd);
		return -1;
	}
	int dst_fd = open(dstfn.c_str(), O_WRONLY | O_LARGEFILE);
	if (dst_fd < 0) {
		gui_print_color("error", "Error opening: '%s' (%s)\n", dstfn.c_str(), strerror(errno));
		close(src_fd);
		return -1;
	}
	if (p.mode == 2)
		gui_print("Image %llu bytes, partition %llu bytes: AVB footer moved to the end of the partition\n", fsz, psz);
	else
		gui_print("Image %llu bytes, partition %llu bytes: the extra zeros are left out\n", fsz, psz);
	LOGINFO("UJC201-adaptive-raw: '%s' -> '%s', mode %d, content %llu\n", srcfn.c_str(), dstfn.c_str(), p.mode,
			p.content_end);
	if (progress)
		progress->SetPartitionSize(fsz);
	bool ok = ujc201_raw_write(src_fd, dst_fd, fsz, psz, &p, progress);
	int err = errno;
	close(src_fd);
	close(dst_fd);
	if (!ok) {
		gui_print_color("error", "Error writing '%s' (%s)\n", dstfn.c_str(), strerror(err));
		return -1;
	}
	if (progress)
		progress->UpdateDisplayDetails(true);
	return 1;
}

/* Install Image : une image plus grande que la partition passe si le plan sait l'ecrire */
static bool ujc201_raw_fits(const string &fn, unsigned long long psz)
{
	struct stat64 st;
	struct ujc201_raw_plan p;
	int fd = open(fn.c_str(), O_RDONLY | O_LARGEFILE);
	if (fd < 0)
		return false;
	memset(&p, 0, sizeof(p));
	p.mode = -1;
	if (fstat64(fd, &st) == 0)
		ujc201_raw_plan_for(fd, (unsigned long long)st.st_size, psz, &p);
	close(fd);
	if (p.mode < 0 && p.why[0])
		gui_print_color("error", "%s: %s\n", fn.c_str(), p.why);
	return p.mode > 0;
}

'''
RRW_OLD = '''	else {
#ifdef TW_ENABLE_BLKDISCARD
		BlkDiscard();
#endif
		destfn = Actual_Block_Device;
		if (part_settings->adbbackup) {'''
RRW_NEW = '''	else {
		/* UJC201 : image d'une autre taille que la partition, decide avant toute ecriture (patch 6) */
		if (!part_settings->adbbackup) {
			int ujc201 = ujc201_adaptive_restore(part_settings->Backup_Folder + "/" + Backup_FileName,
					Actual_Block_Device, part_settings->progress);
			if (ujc201 != 0)
				return ujc201 > 0;
		}
#ifdef TW_ENABLE_BLKDISCARD
		BlkDiscard();
#endif
		destfn = Actual_Block_Device;
		if (part_settings->adbbackup) {'''
FLASH_OLD = '''		unsigned long long image_size = TWFunc::Get_File_Size(full_filename);
		if (image_size > Size) {'''
FLASH_NEW = '''		unsigned long long image_size = TWFunc::Get_File_Size(full_filename);
		if (image_size > Size && !ujc201_raw_fits(full_filename, Size)) {'''

def patch(path, old, new, done_marker, count=1):
    s = open(path, encoding='utf-8').read()
    if done_marker in s:
        print('deja applique :', path); return
    n = s.count(old)
    if n < count:
        sys.exit('ERREUR : motif introuvable dans %s (%d/%d)' % (path, n, count))
    s = s.replace(old, new)
    open(path, 'w', encoding='utf-8').write(s)
    print('patche :', path, '(%d)' % n)

KEYNAV_MARK = 'UJC201-keynav'
KEYNAV_FRIEND = '\tfriend class KeyNav; /* UJC201-keynav */\n'
# classes dont KeyNav lit l'etat interne (liste, clavier, glissieres, action d'un bouton)
KEYNAV_CLASSES = [
    'class GUIButton : public GUIObject, public RenderObject, public ActionObject\n{\n',
    'class GUIScrollList : public GUIObject, public RenderObject, public ActionObject\n{\n',
    'class GUIConsole : public GUIScrollList\n{\n',
    'class GUISlider : public GUIObject, public RenderObject, public ActionObject\n{\n',
    'class GUIKeyboard : public GUIObject, public RenderObject, public ActionObject\n{\n',
    'class GUISliderValue: public GUIObject, public RenderObject, public ActionObject\n{\n',
]
KEYNAV_HPP = [
    ('class Page\n{\n', '/* UJC201-keynav : element navigable aux touches (type, pointeur de l\'objet) */\n'
     'struct UJC201NavItem { int kind; void* p; };\n\nclass Page\n{\n' + KEYNAV_FRIEND),
    ('\tstd::vector<InputObject*> mInputs;\n',
     '\tstd::vector<InputObject*> mInputs;\n\tstd::vector<UJC201NavItem> mNav; /* UJC201-keynav */\n'),
    ('class PageSet\n{\n', 'class PageSet\n{\n' + KEYNAV_FRIEND),
]
KEYNAV_CPP = [
    ('#include "../variables.h"\n', None),   # + code de tools/keynav/keynav.inc
    ("""int PageSet::NotifyTouch(TOUCH_STATE state, int x, int y)
{
""", """int PageSet::NotifyTouch(TOUCH_STATE state, int x, int y)
{
	if (state == TOUCH_START && !KeyNav::synth)
		KeyNav::Touch();  /* UJC201-keynav : vrai toucher -> cadre cache */
"""),
    ("""int PageSet::NotifyKey(int key, bool down)
{
	if (!mOverlays.empty())
		return mOverlays.back()->NotifyKey(key, down);

	return (mCurrentPage ? mCurrentPage->NotifyKey(key, down) : -1);
}""", """int PageSet::NotifyKey(int key, bool down)
{
	/* UJC201-keynav : cadre affiche -> les touches de navigation d'abord ; sinon apres la page (curseur d'un champ,
	 * historique du terminal, touches du theme) */
	if (KeyNav::visible && KeyNav::Key(this, key, down) == 0)
		return 0;
	int ret;
	if (!mOverlays.empty())
		ret = mOverlays.back()->NotifyKey(key, down);
	else
		ret = (mCurrentPage ? mCurrentPage->NotifyKey(key, down) : -1);
	if (ret != 0 && !KeyNav::visible && KeyNav::Key(this, key, down) == 0)
		return 0;
	return ret;
}"""),
    ("""int PageSet::NotifyCharInput(int ch)
{
""", """int PageSet::NotifyCharInput(int ch)
{
	if (KeyNav::Char(this, ch) == 0)
		return 0;  /* UJC201-keynav : Enter = appui sur l'element actif, Tab = suivant */
"""),
    ("""		ret = ((*iter) ? (*iter)->Render() : -1);
		if (ret < 0)
			return ret;
	}
	return ret;
}""", """		ret = ((*iter) ? (*iter)->Render() : -1);
		if (ret < 0)
			return ret;
	}
	KeyNav::Render(this);  /* UJC201-keynav : cadre de l'element actif */
	return ret;
}"""),
    ("""		ret = ((*iter) ? (*iter)->Update() : -1);
		if (ret < 0)
			return ret;
	}
	return ret;
}""", """		ret = ((*iter) ? (*iter)->Update() : -1);
		if (ret < 0)
			return ret;
	}
	return KeyNav::Update(this, ret);  /* UJC201-keynav */
}"""),
]

def keynav(root):
    """Navigation aux touches : amis de KeyNav, liste des elements par page, crochets de PageSet, code KeyNav."""
    import re
    j = lambda p: os.path.join(root, p)
    f = j('gui/objects.hpp')
    s = open(f, encoding='utf-8').read()
    if KEYNAV_MARK not in s:
        for c in KEYNAV_CLASSES:
            if s.count(c) != 1:
                sys.exit('ERREUR : %r introuvable dans objects.hpp' % c.split('\n')[0])
            s = s.replace(c, c + KEYNAV_FRIEND)
        open(f, 'w', encoding='utf-8').write(s)
        print('patche :', f, '(keynav, %d classes)' % len(KEYNAV_CLASSES))
    else:
        print('deja applique :', f)
    f = j('gui/pages.hpp')
    s = open(f, encoding='utf-8').read()
    if KEYNAV_MARK not in s:
        for old, new in KEYNAV_HPP:
            if s.count(old) != 1:
                sys.exit('ERREUR : %r introuvable dans pages.hpp' % old)
            s = s.replace(old, new)
        open(f, 'w', encoding='utf-8').write(s)
        print('patche :', f, '(keynav)')
    else:
        print('deja applique :', f)
    f = j('gui/pages.cpp')
    s = open(f, encoding='utf-8').read()
    if KEYNAV_MARK in s:
        print('deja applique :', f); return
    code = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'keynav', 'keynav.inc'), encoding='utf-8').read()
    for old, new in KEYNAV_CPP:
        if s.count(old) != 1:
            sys.exit('ERREUR : %r introuvable dans pages.cpp' % old.split('\n')[0])
        s = s.replace(old, old + '\n' + code if new is None else new)
    # chaque element cree par Page::ProcessNode : ujc201_nav_add(mNav, element) (sans effet pour les non navigables)
    s, n = re.subn(r'(\t+)(GUI\w+) ?\* ?element = new \2\(child\);\n\1mObjects\.push_back\(element\);\n',
                   lambda m: m.group(0) + m.group(1) + 'ujc201_nav_add(mNav, element);\n', s)
    if n < 15:
        sys.exit('ERREUR : %d elements de ProcessNode seulement (attendu >= 15)' % n)
    open(f, 'w', encoding='utf-8').write(s)
    print('patche :', f, '(keynav, %d types d\'elements)' % n)

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'bootable/recovery'
    j = lambda p: os.path.join(root, p)
    patch(j('bootloader_message/bootloader_message.cpp'), MISC_OLD, MISC_NEW, 'UJC201-misc-para-fallback')
    patch(j('data.cpp'), DATA_OLD, DATA_NEW, 'UJC201-statustext : ligne')
    patch(j('data.cpp'), DATA_INIT_OLD, DATA_INIT_NEW, 'printf("UJC201-statustext')
    patch(j('gui/theme/landscape_hdpi/ui.xml'), UI_OLD, UI_NEW, UI_NEW, count=1)
    la, ui = j('gui/theme/common/landscape.xml'), j('gui/theme/landscape_hdpi/ui.xml')
    l2, u2, msg = ujc201_theme.apply(open(la, encoding='utf-8').read(), open(ui, encoding='utf-8').read(), dash=True)
    open(la, 'w', encoding='utf-8').write(l2); open(ui, 'w', encoding='utf-8').write(u2)
    print('theme :', ', '.join(msg))
    # Render d'abord (le marqueur UJC201-popup est dans le bloc insere avant Render), puis Update
    patch(j('gui/pages.cpp'), PAGES_RENDER_OLD, PAGES_RENDER_NEW, 'UJC201-popup')
    patch(j('gui/pages.cpp'), PAGES_UPDATE_OLD, PAGES_UPDATE_NEW, 'UJC201 : fenetre apparue')
    keynav(root)
    # 6 : fonctions d'abord (leur marqueur est dans le bloc insere), puis les deux appels
    patch(j('partition.cpp'), ADAPT_ANCHOR, ADAPT_CODE + ADAPT_ANCHOR, 'UJC201-adaptive-raw : image brute')
    patch(j('partition.cpp'), RRW_OLD, RRW_NEW, 'int ujc201 = ujc201_adaptive_restore(')
    patch(j('partition.cpp'), FLASH_OLD, FLASH_NEW, 'image_size > Size && !ujc201_raw_fits(')

if __name__ == '__main__':
    main()
