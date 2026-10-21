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

if __name__ == '__main__':
    main()
