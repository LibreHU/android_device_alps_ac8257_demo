/* ---- UJC201-keynav : TWRP pilote aux touches (touches au volant via touchfix, clavier USB) ----
 * Un cadre montre l'element actif ; il apparait a la premiere touche de navigation et disparait au premier toucher
 * de l'ecran.
 *   haut / bas / gauche / droite : element voisin dans cette direction (a defaut, le suivant / precedent)
 *   VOL- / VOL+ (et Tab)         : element suivant / precedent dans l'ordre de lecture (gauche -> droite, haut -> bas)
 *   OK (Enter)                   : appui sur l'element ; glissiere de confirmation : OK deux fois (4 s)
 *   dans une liste               : haut / bas / VOL changent de ligne (on en sort aux extremites),
 *                                  gauche / droite d'une page ; texte et console : defilement
 *   curseur (luminosite...)      : gauche / droite
 *   clavier a l'ecran            : chaque touche est un element ; OK la tape
 * L'element actif de chaque page est retenu (retour a la page = meme element).
 * Les elements sont repertories au chargement de la page (Page::mNav) : le binaire est compile sans RTTI.
 * Les appuis sont simules en appelant NotifyTouch() de l'element lui-meme (meme chemin qu'un vrai toucher).
 */
#include <climits>
#include <linux/input.h>
#include <map>

enum {
	NAV_BUTTON = 1, NAV_CHECKBOX, NAV_INPUT, NAV_SLIDER, NAV_SLIDERVALUE, NAV_KEYBOARD,
	NAV_LISTBOX, NAV_FILESELECTOR, NAV_PARTITIONLIST, NAV_TEXTBOX, NAV_CONSOLE
};

static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUIButton* e) { v.push_back(UJC201NavItem{NAV_BUTTON, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUICheckbox* e) { v.push_back(UJC201NavItem{NAV_CHECKBOX, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUIInput* e) { v.push_back(UJC201NavItem{NAV_INPUT, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUISlider* e) { v.push_back(UJC201NavItem{NAV_SLIDER, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUISliderValue* e) { v.push_back(UJC201NavItem{NAV_SLIDERVALUE, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUIKeyboard* e) { v.push_back(UJC201NavItem{NAV_KEYBOARD, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUIListBox* e) { v.push_back(UJC201NavItem{NAV_LISTBOX, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUIFileSelector* e) { v.push_back(UJC201NavItem{NAV_FILESELECTOR, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUIPartitionList* e) { v.push_back(UJC201NavItem{NAV_PARTITIONLIST, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUITextBox* e) { v.push_back(UJC201NavItem{NAV_TEXTBOX, e}); }
static void ujc201_nav_add(std::vector<UJC201NavItem>& v, GUIConsole* e) { v.push_back(UJC201NavItem{NAV_CONSOLE, e}); }
/* les autres elements (texte, image, terminal, mot de passe schema...) ne sont pas des cibles */
template <class T> static void ujc201_nav_add(std::vector<UJC201NavItem>&, T*) {}

class KeyNav
{
public:
	static int Key(PageSet* s, int key, bool down);
	static int Char(PageSet* s, int ch);
	static void Touch(void) { if (visible) { visible = false; armedP = NULL; gui_forceRender(); } }
	static void Render(PageSet* s);
	static int Update(PageSet* s, int ret);
	static bool visible;
	static bool synth;

private:
	struct Target {
		int kind;
		void* p;
		int sub;            /* touche du clavier : rang * 32 + colonne ; -1 sinon */
		int x, y, w, h;
	};
	static Page* ActivePage(PageSet* s) { return !s->mOverlays.empty() ? s->mOverlays.back() : s->mCurrentPage; }
	static GUIObject* Obj(int kind, void* p);
	static ActionObject* Act(int kind, void* p);
	static GUIScrollList* List(int kind, void* p);
	static bool IsList(int k) { return k == NAV_LISTBOX || k == NAV_FILESELECTOR || k == NAV_PARTITIONLIST; }
	static bool IsScroll(int k) { return k == NAV_TEXTBOX || k == NAV_CONSOLE; }
	static void Collect(Page* pg, std::vector<Target>& t);
	static int Sync(Page* pg, const std::vector<Target>& t);
	static void Select(const Target& t);
	static std::vector<int> Order(const std::vector<Target>& t);
	static int Linear(const std::vector<Target>& t, int i, int dir, bool wrap);
	static int Spatial(const std::vector<Target>& t, int i, int dx, int dy);
	static bool Inner(const Target& c, int dir, bool pageStep);
	static void EnterList(const Target& c, int dir);
	static int& Row(GUIScrollList* l);
	static void Activate(const Target& c);
	static void Adjust(const Target& c, int dir);
	static void Frame(const Target& c, int& x, int& y, int& w, int& h);
	static long long Now(void);

	static Page* curPage;
	static void* curP;
	static int curSub;
	static bool haveLast;
	static int lastX, lastY;
	static void* armedP;
	static long long armedUntil;
	static bool actHeld;
	static std::map<Page*, std::pair<void*, int> > remembered;
	static std::map<GUIScrollList*, int> rows;
};

bool KeyNav::visible = false;
bool KeyNav::synth = false;
Page* KeyNav::curPage = NULL;
void* KeyNav::curP = NULL;
int KeyNav::curSub = -1;
bool KeyNav::haveLast = false;
int KeyNav::lastX = 0;
int KeyNav::lastY = 0;
void* KeyNav::armedP = NULL;
long long KeyNav::armedUntil = 0;
bool KeyNav::actHeld = false;
std::map<Page*, std::pair<void*, int> > KeyNav::remembered;
std::map<GUIScrollList*, int> KeyNav::rows;

long long KeyNav::Now(void)
{
	timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

GUIObject* KeyNav::Obj(int kind, void* p)
{
	switch (kind) {
	case NAV_BUTTON: return (GUIButton*)p;
	case NAV_CHECKBOX: return (GUICheckbox*)p;
	case NAV_INPUT: return (GUIInput*)p;
	case NAV_SLIDER: return (GUISlider*)p;
	case NAV_SLIDERVALUE: return (GUISliderValue*)p;
	case NAV_KEYBOARD: return (GUIKeyboard*)p;
	case NAV_LISTBOX: return (GUIListBox*)p;
	case NAV_FILESELECTOR: return (GUIFileSelector*)p;
	case NAV_PARTITIONLIST: return (GUIPartitionList*)p;
	case NAV_TEXTBOX: return (GUITextBox*)p;
	case NAV_CONSOLE: return (GUIConsole*)p;
	}
	return NULL;
}

ActionObject* KeyNav::Act(int kind, void* p)
{
	switch (kind) {
	case NAV_BUTTON: return (GUIButton*)p;
	case NAV_CHECKBOX: return (GUICheckbox*)p;
	case NAV_INPUT: return (GUIInput*)p;
	case NAV_SLIDER: return (GUISlider*)p;
	case NAV_SLIDERVALUE: return (GUISliderValue*)p;
	case NAV_KEYBOARD: return (GUIKeyboard*)p;
	case NAV_LISTBOX: return (GUIListBox*)p;
	case NAV_FILESELECTOR: return (GUIFileSelector*)p;
	case NAV_PARTITIONLIST: return (GUIPartitionList*)p;
	case NAV_TEXTBOX: return (GUITextBox*)p;
	case NAV_CONSOLE: return (GUIConsole*)p;
	}
	return NULL;
}

GUIScrollList* KeyNav::List(int kind, void* p)
{
	switch (kind) {
	case NAV_LISTBOX: return (GUIListBox*)p;
	case NAV_FILESELECTOR: return (GUIFileSelector*)p;
	case NAV_PARTITIONLIST: return (GUIPartitionList*)p;
	case NAV_TEXTBOX: return (GUITextBox*)p;
	case NAV_CONSOLE: return (GUIConsole*)p;
	}
	return NULL;
}

/* Cibles visibles de la page, dans l'ordre du theme */
void KeyNav::Collect(Page* pg, std::vector<Target>& t)
{
	t.clear();
	if (!pg)
		return;
	long long screen = (long long)gr_fb_width() * gr_fb_height();
	for (size_t i = 0; i < pg->mNav.size(); i++) {
		const UJC201NavItem& n = pg->mNav[i];
		GUIObject* g = Obj(n.kind, n.p);
		if (!g || !g->isConditionTrue())
			continue;
		Target c;
		c.kind = n.kind;
		c.p = n.p;
		c.sub = -1;
		Act(n.kind, n.p)->GetActionPos(c.x, c.y, c.w, c.h);
		if (n.kind == NAV_BUTTON) {
			GUIButton* b = (GUIButton*)n.p;
			if (!b->mAction)
				continue;                       /* bouton sans action : decor */
			b->GetRenderPos(c.x, c.y, c.w, c.h);
			if ((long long)c.w * c.h > screen / 2)
				continue;                       /* zone de toucher plein ecran */
		} else if (n.kind == NAV_KEYBOARD) {
			GUIKeyboard* k = (GUIKeyboard*)n.p;
			if (k->currentLayout < 1 || k->currentLayout > GUIKeyboard::MAX_KEYBOARD_LAYOUTS)
				continue;
			int kx, ky, kw, kh;
			k->GetRenderPos(kx, ky, kw, kh);
			GUIKeyboard::Layout& lay = k->layouts[k->currentLayout - 1];
			int y1 = 0;
			for (int row = 0; row < GUIKeyboard::MAX_KEYBOARD_ROWS; ++row) {
				int rowY = ky + y1, rowH = lay.row_end_y[row] - y1;
				y1 = lay.row_end_y[row];
				if (rowH <= 0)
					continue;
				int x1 = 0;
				for (int col = 0; col < GUIKeyboard::MAX_KEYBOARD_KEYS; ++col) {
					GUIKeyboard::Key& key = lay.keys[row][col];
					int keyX = kx + x1, keyW = key.end_x - x1;
					x1 = key.end_x;
					if (keyW <= 0 || (key.key == 0 && key.layout == 0))
						continue;
					Target kt = c;
					kt.sub = row * 32 + col;
					kt.x = keyX; kt.y = rowY; kt.w = keyW; kt.h = rowH;
					t.push_back(kt);
				}
			}
			continue;
		} else if (n.kind == NAV_CONSOLE) {
			GUIConsole* cs = (GUIConsole*)n.p;
			if (cs->actualItemHeight <= 0)
				continue;
			if (cs->mSlideout && cs->mSlideoutState != GUIConsole::visible)
				continue;                       /* console repliee : son bouton est ailleurs */
			if (cs->GetItemCount() <= (size_t)cs->GetDisplayItemCount())
				continue;
			cs->GetRenderPos(c.x, c.y, c.w, c.h);
		} else if (IsList(n.kind) || n.kind == NAV_TEXTBOX) {
			GUIScrollList* l = List(n.kind, n.p);
			if (l->actualItemHeight <= 0 || l->GetItemCount() == 0)
				continue;                       /* pas encore mise en page, ou vide */
			if (n.kind == NAV_TEXTBOX && l->GetItemCount() <= (size_t)l->GetDisplayItemCount())
				continue;                       /* texte court : rien a faire defiler */
			l->GetRenderPos(c.x, c.y, c.w, c.h);
		}
		if (c.w <= 0 || c.h <= 0)
			continue;
		t.push_back(c);
	}
}

void KeyNav::Select(const Target& t)
{
	curP = t.p;
	curSub = t.sub;
	lastX = t.x + t.w / 2;
	lastY = t.y + t.h / 2;
	haveLast = true;
}

/* Index de l'element actif (change de page : celui retenu pour la page, sinon le premier) */
int KeyNav::Sync(Page* pg, const std::vector<Target>& t)
{
	if (pg != curPage) {
		if (curPage)
			remembered[curPage] = std::make_pair(curP, curSub);
		curPage = pg;
		armedP = NULL;
		haveLast = false;
		std::map<Page*, std::pair<void*, int> >::iterator it = remembered.find(pg);
		curP = it != remembered.end() ? it->second.first : NULL;
		curSub = it != remembered.end() ? it->second.second : -1;
	}
	if (t.empty())
		return -1;
	for (size_t i = 0; i < t.size(); i++) {
		if (t[i].p == curP && t[i].sub == curSub) {
			Select(t[i]);
			return i;
		}
	}
	int best = Order(t)[0];
	if (haveLast) {                             /* element disparu : le plus proche */
		long long bd = LLONG_MAX;
		for (size_t i = 0; i < t.size(); i++) {
			long long dx = t[i].x + t[i].w / 2 - lastX, dy = t[i].y + t[i].h / 2 - lastY;
			if (dx * dx + dy * dy < bd) {
				bd = dx * dx + dy * dy;
				best = i;
			}
		}
	}
	Select(t[best]);
	return best;
}

/* Ordre de lecture : bandes horizontales de 24 px, puis de gauche a droite */
std::vector<int> KeyNav::Order(const std::vector<Target>& t)
{
	std::vector<int> o(t.size());
	for (size_t i = 0; i < t.size(); i++)
		o[i] = i;
	std::stable_sort(o.begin(), o.end(), [&t](int a, int b) {
		int ba = (t[a].y + t[a].h / 2) / 24, bb = (t[b].y + t[b].h / 2) / 24;
		if (ba != bb)
			return ba < bb;
		return t[a].x < t[b].x;
	});
	return o;
}

int KeyNav::Linear(const std::vector<Target>& t, int i, int dir, bool wrap)
{
	std::vector<int> o = Order(t);
	int n = o.size(), pos = 0;
	for (int k = 0; k < n; k++)
		if (o[k] == i)
			pos = k;
	int np = pos + dir;
	if (np < 0 || np >= n) {
		if (!wrap)
			return -1;
		np = (np + n) % n;
	}
	return o[np];
}

/* Voisin le plus proche dans la direction (dx, dy) : ecart sur l'axe de deplacement, puis decalage sur l'autre */
int KeyNav::Spatial(const std::vector<Target>& t, int i, int dx, int dy)
{
	const Target& c = t[i];
	int ccx = c.x + c.w / 2, ccy = c.y + c.h / 2;
	long long best = LLONG_MAX;
	int bi = -1;
	for (size_t k = 0; k < t.size(); k++) {
		if ((int)k == i)
			continue;
		const Target& o = t[k];
		int ocx = o.x + o.w / 2, ocy = o.y + o.h / 2;
		int gap, side, off;
		if (dy) {
			if ((dy > 0 && ocy <= ccy) || (dy < 0 && ocy >= ccy))
				continue;
			gap = dy > 0 ? o.y - (c.y + c.h) : c.y - (o.y + o.h);
			side = std::max(c.x, o.x) - std::min(c.x + c.w, o.x + o.w);   /* > 0 : pas de recouvrement */
			off = abs(ocx - ccx);
		} else {
			if ((dx > 0 && ocx <= ccx) || (dx < 0 && ocx >= ccx))
				continue;
			gap = dx > 0 ? o.x - (c.x + c.w) : c.x - (o.x + o.w);
			side = std::max(c.y, o.y) - std::min(c.y + c.h, o.y + o.h);
			off = abs(ocy - ccy);
		}
		if (gap < 0)
			gap = 0;
		if (side < 0)
			side = 0;
		long long score = (long long)gap * 2 + (long long)side * 8 + off;
		if (score < best) {
			best = score;
			bi = k;
		}
	}
	return bi;
}

int& KeyNav::Row(GUIScrollList* l)
{
	std::map<GUIScrollList*, int>::iterator it = rows.find(l);
	if (it == rows.end())
		it = rows.insert(std::make_pair(l, l->firstDisplayedItem)).first;
	return it->second;
}

/* Arrivee dans une liste : premiere ligne visible en descendant, derniere en remontant */
void KeyNav::EnterList(const Target& c, int dir)
{
	if (!IsList(c.kind))
		return;
	GUIScrollList* l = List(c.kind, c.p);
	int n = l->GetItemCount();
	if (n <= 0)
		return;
	int first = l->firstDisplayedItem + (l->y_offset < 0 ? 1 : 0);
	int last = l->firstDisplayedItem + l->GetDisplayItemCount() - 1;
	int r = dir < 0 ? last : first;
	if (r >= n)
		r = n - 1;
	if (r < 0)
		r = 0;
	Row(l) = r;
	l->SetVisibleListLocation(r);
}

/* Deplacement dans l'element (lignes d'une liste, defilement d'un texte) ; false = on en sort */
bool KeyNav::Inner(const Target& c, int dir, bool pageStep)
{
	if (IsList(c.kind)) {
		GUIScrollList* l = List(c.kind, c.p);
		int n = l->GetItemCount();
		if (n <= 0)
			return false;
		int& row = Row(l);
		if (row < 0 || row >= n)
			row = std::min(std::max(l->firstDisplayedItem, 0), n - 1);
		int step = pageStep ? std::max(1, l->GetDisplayItemCount() - 1) : 1;
		int nr = row + dir * step;
		if (pageStep)
			nr = std::min(std::max(nr, 0), n - 1);
		else if (nr < 0 || nr >= n)
			return false;
		row = nr;
		l->SetVisibleListLocation(row);
		return true;
	}
	if (IsScroll(c.kind)) {
		GUIScrollList* l = List(c.kind, c.p);
		int n = l->GetItemCount(), disp = l->GetDisplayItemCount();
		int maxFirst = std::max(0, n - disp);
		int step = pageStep ? std::max(1, disp - 1) : 1;
		int nf = l->firstDisplayedItem + dir * step;
		if (!pageStep && (nf < 0 || nf > maxFirst))
			return false;
		nf = std::min(std::max(nf, 0), maxFirst);
		l->firstDisplayedItem = nf;
		l->y_offset = 0;
		l->scrollingSpeed = 0;
		l->mUpdate = 1;
		if (c.kind == NAV_CONSOLE)
			((GUIConsole*)c.p)->scrollToEnd = nf >= maxFirst;
		return true;
	}
	return false;
}

/* Curseur (slidervalue) : un vingtieme de la plage, au moins 1 */
void KeyNav::Adjust(const Target& c, int dir)
{
	GUISliderValue* s = (GUISliderValue*)c.p;
	if (s->mMax <= s->mMin || s->mLineW <= s->mSliderW)
		return;
	int step = std::max(1, (s->mMax - s->mMin) / 20);
	int v = std::min(std::max(s->mValue + dir * step, s->mMin), s->mMax);
	int x = s->mLineX + s->mSliderW / 2 + (int)((long long)(v - s->mMin) * (s->mLineW - s->mSliderW) / (s->mMax - s->mMin));
	int rx, ry, rw, rh;
	s->GetRenderPos(rx, ry, rw, rh);
	synth = true;
	s->NotifyTouch(TOUCH_START, x, ry + rh / 2);
	s->NotifyTouch(TOUCH_RELEASE, x, ry + rh / 2);
	synth = false;
}

void KeyNav::Activate(const Target& c)
{
	ActionObject* a = Act(c.kind, c.p);
	synth = true;
	if (IsList(c.kind)) {
		GUIScrollList* l = List(c.kind, c.p);
		int n = l->GetItemCount();
		int& row = Row(l);
		if (row >= 0 && row < n) {
			l->SetVisibleListLocation(row);
			l->NotifySelect(row);
			l->mUpdate = 1;
		}
	} else if (c.kind == NAV_SLIDER) {
		GUISlider* s = (GUISlider*)c.p;
		if (armedP == c.p && Now() < armedUntil) {
			int rx, ry, rw, rh;
			s->GetRenderPos(rx, ry, rw, rh);
			int y = ry + rh / 2;
			armedP = NULL;
			s->NotifyTouch(TOUCH_START, rx + s->sTouchW / 2, y);
			s->NotifyTouch(TOUCH_DRAG, rx + rw / 2, y);
			s->NotifyTouch(TOUCH_DRAG, rx + rw - s->sTouchW / 2, y);
			s->NotifyTouch(TOUCH_RELEASE, rx + rw - s->sTouchW / 2, y);
		} else {
			armedP = c.p;                       /* action irreversible (wipe, flash...) : OK une 2e fois */
			armedUntil = Now() + 4000;
		}
	} else if (c.kind == NAV_BUTTON || c.kind == NAV_CHECKBOX || c.kind == NAV_INPUT || c.kind == NAV_KEYBOARD) {
		int x = c.x + c.w / 2, y = c.y + c.h / 2;
		a->NotifyTouch(TOUCH_START, x, y);
		a->NotifyTouch(TOUCH_RELEASE, x, y);
	}
	synth = false;
	gui_forceRender();
}

int KeyNav::Key(PageSet* s, int key, bool down)
{
	int dx = 0, dy = 0, lin = 0, act = 0, pg = 0;
	switch (key) {
	case KEY_UP: dy = -1; break;
	case KEY_DOWN: dy = 1; break;
	case KEY_LEFT: dx = -1; break;
	case KEY_RIGHT: dx = 1; break;
	case KEY_VOLUMEUP: case KEY_PREVIOUSSONG: lin = -1; break;
	case KEY_VOLUMEDOWN: case KEY_NEXTSONG: lin = 1; break;
	case KEY_PAGEUP: pg = -1; break;
	case KEY_PAGEDOWN: pg = 1; break;
	case KEY_OK: case KEY_SELECT: act = 1; break;
	case KEY_ENTER:
		if (!down)
			actHeld = false;                    /* Enter arrive en caractere (Char) ; ici son relachement */
		return 1;
	default:
		return 1;
	}
	if (!down) {
		if (act)
			actHeld = false;
		return 0;
	}
	Page* page = ActivePage(s);
	std::vector<Target> t;
	Collect(page, t);
	int i = Sync(page, t);
	if (i < 0)
		return 1;
	if (!visible) {                             /* premier appui : montre l'element actif */
		visible = true;
		gui_forceRender();
		return 0;
	}
	const Target& c = t[i];
	if (act) {
		if (!actHeld) {
			actHeld = true;
			Activate(c);
		}
		return 0;
	}
	armedP = NULL;
	if (pg) {
		Inner(c, pg, true);
	} else if (dx && (IsList(c.kind) || IsScroll(c.kind))) {
		Inner(c, dx, true);
	} else if (dx && c.kind == NAV_SLIDERVALUE) {
		Adjust(c, dx);
	} else if ((lin || dy) && Inner(c, lin ? lin : dy, false)) {
		/* ligne suivante / defilement dans l'element */
	} else {
		int ni = lin ? Linear(t, i, lin, true) : Spatial(t, i, dx, dy);
		if (ni < 0 && dy)
			ni = Linear(t, i, dy, false);
		if (ni >= 0 && ni != i) {
			Select(t[ni]);
			EnterList(t[ni], lin ? lin : (dy ? dy : 1));   /* de cote : premiere ligne visible */
		}
	}
	gui_forceRender();
	return 0;
}

int KeyNav::Char(PageSet* s, int ch)
{
	if (synth)
		return 1;                               /* caractere d'une touche du clavier simulee : au champ */
	if (ch != KEYBOARD_ACTION && ch != '\n' && ch != KEYBOARD_TAB)
		return 1;
	Page* page = ActivePage(s);
	std::vector<Target> t;
	Collect(page, t);
	int i = Sync(page, t);
	if (i < 0)
		return 1;
	bool hasInput = false;
	for (size_t k = 0; k < t.size(); k++)
		if (t[k].kind == NAV_INPUT)
			hasInput = true;
	if (!visible) {
		if (hasInput)
			return 1;                           /* Enter / Tab d'un clavier : au champ de saisie */
		visible = true;
		gui_forceRender();
		return 0;
	}
	if (ch == KEYBOARD_TAB) {
		int ni = Linear(t, i, 1, true);
		if (ni >= 0) {
			Select(t[ni]);
			EnterList(t[ni], 1);
		}
		armedP = NULL;
		gui_forceRender();
		return 0;
	}
	if (t[i].kind == NAV_INPUT)
		return 1;                               /* Enter sur le champ : le valider */
	if (!actHeld) {
		actHeld = true;
		Activate(t[i]);
	}
	return 0;
}

/* Rectangle du cadre : la ligne active d'une liste, sinon l'element */
void KeyNav::Frame(const Target& c, int& x, int& y, int& w, int& h)
{
	x = c.x; y = c.y; w = c.w; h = c.h;
	if (IsList(c.kind)) {
		GUIScrollList* l = List(c.kind, c.p);
		int n = l->GetItemCount(), row = Row(l);
		if (row < 0 || row >= n)
			return;
		int top = c.y + l->mHeaderH;
		int ry = top + l->y_offset + (row - l->firstDisplayedItem) * l->actualItemHeight;
		int rh = l->actualItemHeight;
		if (ry < top) { rh -= top - ry; ry = top; }
		if (ry + rh > c.y + c.h)
			rh = c.y + c.h - ry;
		if (rh > 0) {
			y = ry;
			h = rh;
			w = c.w - (l->hasScroll ? l->mFastScrollW : 0);
		}
	}
}

void KeyNav::Render(PageSet* s)
{
	if (!visible)
		return;
	Page* page = ActivePage(s);
	std::vector<Target> t;
	Collect(page, t);
	int i = Sync(page, t);
	if (i < 0)
		return;
	int x, y, w, h;
	Frame(t[i], x, y, w, h);
	bool armed = armedP == t[i].p && Now() < armedUntil;
	int th = armed ? 6 : 4, W = gr_fb_width(), H = gr_fb_height();
	x -= th / 2; y -= th / 2; w += th; h += th;
	if (x < 0) { w += x; x = 0; }
	if (y < 0) { h += y; y = 0; }
	if (x + w > W) w = W - x;
	if (y + h > H) h = H - y;
	if (w <= 2 * th || h <= 2 * th)
		return;
	if (armed)
		gr_color(0xFF, 0x57, 0x22, 255);
	else
		gr_color(0xFF, 0xC1, 0x07, 255);
	gr_fill(x, y, w, th);
	gr_fill(x, y + h - th, w, th);
	gr_fill(x, y, th, h);
	gr_fill(x + w - th, y, th, h);
	if (armed) {
		const ResourceManager* rm = PageManager::GetResources();
		FontResource* f = rm ? rm->FindFont("font_m") : NULL;
		if (f && f->GetResource()) {
			int fh = f->GetHeight();
			int ty = y + h + fh / 3;
			if (ty + fh > H)
				ty = y - fh - fh / 3;
			gr_color(0, 0, 0, 200);
			gr_fill(x, ty - fh / 6, w, fh + fh / 3);
			gr_color(0xFF, 0x57, 0x22, 255);
			gr_textEx_scaleW(x + w / 2, ty, "Press OK again to confirm", f->GetResource(), w, CENTER_X_ONLY, 1);
		}
	}
}

int KeyNav::Update(PageSet* s __unused, int ret)
{
	if (!visible || ret < 0)
		return ret;
	if (armedP && Now() >= armedUntil) {
		armedP = NULL;
		return 2;
	}
	return ret == 1 ? 2 : ret;                  /* rendu partiel : il effacerait le cadre */
}
/* ---- fin UJC201-keynav ---- */
