#!/usr/bin/env python3
"""
ujc201_theme.py - ajouts au theme TWRP (landscape) pour le Jancar UJC201, partages par
apply_twrp_patches.py (source) et ujc201_postprocess.py (image deja compilee).

  - Advanced : entrees Power info / USB / MCU info / touches au volant, et partition boot 32 Mio (zips LibreHU
    embarques dans /system/etc/librehu, flashes par la page de confirmation de TWRP). Elles passent par action_page +
    terminalcommand : la sortie du script s'affiche dans la console (l'action "cmd" n'affiche rien).
  - Page graphique "ujc201_vehicle" (tableau de bord : tension, CPU, ACC / frein / feux, MCU, volant) et
    zone droite de la barre d'etat : valeurs = proprietes systeme ujc201.<nom> posees par touchfix, lues par
    le theme avec %property.ujc201.<nom>% (gere par DataManager::GetValue : aucun patch du binaire TWRP).
Idempotent : le bloc Advanced est entre marqueurs et remplace a chaque passage.
"""
import re

ADV_ANCHOR = '''			<listbox style="advanced_listbox">
				<placement x="%center_x%" y="%row2_y%" w="%content_half_width%" h="%fileselector_install_height%"/>
'''
OLD_NAMES = ['Power info (Vin / CPU)', 'USB: Host mode (USB drive)', 'USB: PC mode (ADB / MTP)',
             'MCU info (firmware version)', 'Steering wheel keys: learn', 'Steering wheel keys: show / test']
BEGIN, END = '<!-- UJC201 begin -->', '<!-- UJC201 end -->'

def term_actions(cmd, title, back, ind):
    """sortie du script dans la console : action_page + terminalcommand (sortie ligne par ligne)"""
    t = '\t' * ind
    return ''.join('%s<action function="%s">%s</action>\n' % (t, f, v) for f, v in [
        ('set', 'tw_back=' + back), ('set', 'tw_has_action2=0'), ('set', 'tw_has_cancel=0'),
        ('set', 'tw_action=terminalcommand'), ('set', 'tw_action_param=' + cmd),
        ('set', 'tw_action_text1=' + title), ('set', 'tw_action_text2='),
        ('set', 'tw_complete_text1=' + title), ('page', 'action_page')])

def term_item(name, cmd, title):
    return ('\t\t\t\t<listitem name="%s">\n\t\t\t\t\t<actions>\n%s\t\t\t\t\t</actions>\n\t\t\t\t</listitem>\n'
            % (name, term_actions(cmd, title, 'advanced', 6)))

# Zips TWRP de LibreHU embarques dans l'image (CI : release latest-experimental-4.19.325 du noyau), flashes comme un
# zip choisi dans Install : file d'attente puis page de confirmation (glisser pour flasher) de TWRP
ZIP_DIR = '/system/etc/librehu'

def zip_item(name, zipname):
    return ('\t\t\t\t<listitem name="%s">\n\t\t\t\t\t<actions>\n'
            '\t\t\t\t\t\t<action function="set">tw_filename=%s/%s</action>\n'
            '\t\t\t\t\t\t<action function="queuezip"></action>\n'
            '\t\t\t\t\t\t<action function="page">flash_confirm</action>\n'
            '\t\t\t\t\t</actions>\n\t\t\t\t</listitem>\n' % (name, ZIP_DIR, zipname))

def adv_block(dash):
    s = '\t\t\t\t' + BEGIN + '\n'
    if dash:
        s += ('\t\t\t\t<listitem name="Vehicle / MCU dashboard">\n'
              '\t\t\t\t\t<action function="page">ujc201_vehicle</action>\n\t\t\t\t</listitem>\n')
    s += term_item('Power info (Vin / CPU)', '/system/bin/powerinfo', 'Power info')
    s += term_item('MCU info (firmware version)', '/system/bin/mcuinfo', 'MCU info')
    s += term_item('Steering wheel keys: learn', '/system/bin/wheelkeys learn', 'Steering wheel keys: learn')
    s += term_item('Steering wheel keys: show / test', '/system/bin/wheelkeys show', 'Steering wheel keys')
    s += term_item('USB: Host mode (USB drive)', '/system/bin/usbmode host', 'USB: Host mode')
    s += term_item('USB: PC mode (ADB / MTP)', '/system/bin/usbmode device', 'USB: PC mode')
    s += zip_item('Boot partition: grow to 32 MiB (Android 10+)', 'librehu_boot32_twrp.zip')
    s += zip_item('Boot partition: back to 10 MiB', 'librehu_boot32_restore_twrp.zip')
    return s + '\t\t\t\t' + END + '\n'

# ---------------------------------------------------------------- page graphique (coordonnees du theme 1920x1200)
CARD, TRACK, ACC, GREEN, AMBER, RED, GREY, WHITE = '#262626', '#3A3A3A', '#0090CA', '#4CAF50', '#FFB300', '#F44336', '#9E9E9E', '#EEEEEE'

def fill(x, y, w, h, col, cond=''):
    return '\t\t\t<fill color="%s">%s<placement x="%d" y="%d" w="%d" h="%d"/></fill>\n' % (col, cond, x, y, w, h)

def text(x, y, s, font='font_m', col=WHITE, pl=0):
    return ('\t\t\t<text color="%s"><font resource="%s"/><placement x="%d" y="%d" placement="%d"/><text>%s</text></text>\n'
            % (col, font, x, y, pl, s))

def cond(var, val, op=None):
    return '<condition var1="%s"%s var2="%s"/>' % (var, ' op="%s"' % op if op else '', val)

def gauge(x, y, var, colors, labels):
    """10 segments : le segment k s'allume si property.ujc201.<var> > k (touchfix ecrit 0..10)"""
    s = ''
    for k in range(10):
        sx = x + k * 53
        s += fill(sx, y, 47, 36, TRACK)
        s += fill(sx, y, 47, 36, colors[k], cond('property.ujc201.' + var, k, '&gt;'))
    s += text(x, y + 50, labels[0], 'font_s', GREY)
    s += text(x + 263, y + 50, labels[1], 'font_s', GREY, 5)
    s += text(x + 527, y + 50, labels[2], 'font_s', GREY, 1)
    return s

def pill(x, y, label, var, on_col):
    s = text(x, y + 22, label, 'font_m')
    px = x + 328
    s += fill(px, y + 8, 200, 64, TRACK)
    s += fill(px, y + 8, 200, 64, on_col, cond('property.ujc201.' + var, 'ON'))
    s += text(px + 100, y + 40, '%property.ujc201.' + var + '%', 'font_m', WHITE, 4)
    return s

def button(x, y, w, h, label, cmd, title):
    return ('\t\t\t<button>\n\t\t\t\t<placement x="%d" y="%d" w="%d" h="%d"/>\n\t\t\t\t<fill color="%s"/>\n'
            '\t\t\t\t<highlight color="%%highlight_color%%"/>\n\t\t\t\t<font resource="font_m" color="#FFFFFF"/>\n'
            '\t\t\t\t<text>%s</text>\n\t\t\t\t<actions>\n%s\t\t\t\t</actions>\n\t\t\t</button>\n'
            % (x, y, w, h, ACC, label, term_actions(cmd, title, 'ujc201_vehicle', 5)))

def dash_page():
    p = '\t\t<page name="ujc201_vehicle">\n\t\t\t<template name="page"/>\n'
    p += text(144, 60, 'Vehicle / MCU', 'font_l')
    p += text(144, 126, 'Live data: Jancar MCU (/dev/ttyS1) and SoC ADC', 'font_m')
    Y1, Y2, H = 216, 660, 420
    # tension d'entree
    x = 48
    p += fill(x, Y1, 592, H, CARD)
    p += text(x + 32, Y1 + 26, 'INPUT VOLTAGE', 'font_s', ACC)
    p += text(x + 32, Y1 + 66, '%property.ujc201.vin1% V', 'ujc_xl')
    p += text(x + 32, Y1 + 190, 'PMIC VCDT: %property.ujc201.vin2% V', 'font_m', GREY)
    p += gauge(x + 32, Y1 + 270, 'vinseg', [RED] * 4 + [AMBER] * 2 + [GREEN] * 4, ['9 V', '12 V', '15 V'])
    p += text(x + 32, Y1 + 366, 'Calibrated at 12.02 V (bench)', 'font_s', GREY)
    # CPU
    x = 664
    p += fill(x, Y1, 592, H, CARD)
    p += text(x + 32, Y1 + 26, 'CPU TEMPERATURE', 'font_s', ACC)
    p += text(x + 32, Y1 + 66, '%property.ujc201.cpu% °C', 'ujc_xl')
    p += text(x + 32, Y1 + 190, 'AC8257 · thermal_zone1', 'font_m', GREY)
    p += gauge(x + 32, Y1 + 270, 'cpuseg', [GREEN] * 5 + [AMBER] * 3 + [RED] * 2, ['30', '60', '90 °C'])
    # vehicule
    x = 1280
    p += fill(x, Y1, 592, H, CARD)
    p += text(x + 32, Y1 + 26, 'VEHICLE', 'font_s', ACC)
    p += pill(x + 32, Y1 + 80, 'Ignition (ACC)', 'acc', GREEN)
    p += pill(x + 32, Y1 + 190, 'Handbrake', 'hb', GREEN)
    p += pill(x + 32, Y1 + 300, 'Lights (ILL)', 'ill', AMBER)
    # MCU
    x = 48
    p += fill(x, Y2, 1208, H, CARD)
    p += text(x + 32, Y2 + 26, 'MCU FIRMWARE', 'font_s', ACC)
    p += text(x + 32, Y2 + 70, '%property.ujc201.mcuver%', 'keylabel')
    p += text(x + 32, Y2 + 170, 'MCU clock at boot: %property.ujc201.mcutime%', 'font_m')
    p += text(x + 32, Y2 + 230, 'Frames received: %property.ujc201.frames%', 'font_m')
    p += text(x + 32, Y2 + 310, 'HK32C030 (Cortex-M0) · /dev/ttyS1 115200 8N1 · protocol JAC_V1', 'font_s', GREY)
    p += text(x + 32, Y2 + 356, 'PC_READY (1F 01) sent once at boot · no heartbeat on AC8257', 'font_s', GREY)
    # volant
    x = 1280
    p += fill(x, Y2, 592, H, CARD)
    p += text(x + 32, Y2 + 26, 'STEERING WHEEL', 'font_s', ACC)
    p += text(x + 32, Y2 + 80, 'Last key', 'font_s', GREY)
    p += text(x + 32, Y2 + 118, '%property.ujc201.key%', 'font_l')
    p += text(x + 32, Y2 + 200, '%property.ujc201.keymap% keys mapped', 'font_m', GREY)
    p += button(x + 32, Y2 + 296, 256, 92, 'Learn', '/system/bin/wheelkeys learn', 'Steering wheel keys: learn')
    p += button(x + 304, Y2 + 296, 256, 92, 'Table', '/system/bin/wheelkeys show', 'Steering wheel keys')
    p += ('\t\t\t<action>\n\t\t\t\t<touch key="home"/>\n\t\t\t\t<action function="page">main</action>\n\t\t\t</action>\n'
          '\t\t\t<action>\n\t\t\t\t<touch key="back"/>\n\t\t\t\t<action function="page">advanced</action>\n\t\t\t</action>\n'
          '\t\t</page>\n')
    return p

CAR_ANCHOR = '''				<text>{@battery_pct=Battery: %tw_battery%}</text>
			</text>
'''
CAR_ITEM = '''
			<text color="%text_color%">
				<font resource="font_m"/>
				<placement x="%indent_right%" y="%row1_header_y%" placement="1"/>
				<text>%property.ujc201.car%</text>
			</text>
'''

BANNER_ANCHOR = '''			<action>
				<touch key="power"/>
				<action function="togglebacklight"/>
'''
BB, BE = '<!-- UJC201 banner begin -->', '<!-- UJC201 banner end -->'

def banner():
    """bandeau sur la barre de navigation (fin du template "page" = dessine au-dessus du contenu des pages) :
    propriete ujc201.pop_k = W (avertissement) / K (touche volant) / I (invite), pop_t titre, pop_x detail"""
    s = '\t\t\t' + BB + '\n'
    for k, col in (('W', AMBER), ('K', ACC), ('I', '#2E7D32')):
        s += fill(0, 1104, 1920, 96, col, cond('property.ujc201.pop_k', k))
    for c, op in (('#1A1A1A', None), ('#FFFFFF', '!=')):
        k = cond('property.ujc201.pop_k', 'W', op)
        s += ('\t\t\t<text color="%s">%s<font resource="font_m"/><placement x="48" y="1133"/>'
              '<text>%%property.ujc201.pop_t%%</text></text>\n' % (c, k))
        s += ('\t\t\t<text color="%s">%s<font resource="font_s"/><placement x="1872" y="1136" placement="1"/>'
              '<text>%%property.ujc201.pop_x%%</text></text>\n' % (c, k))
    return s + '\t\t\t' + BE + '\n'

FONT_ANCHOR = '<font name="font_l" filename="RobotoCondensed-Regular.ttf" size="42"/>'
FONT_XL = '\n\t\t<font name="ujc_xl" filename="RobotoCondensed-Regular.ttf" size="88"/>'

def apply(landscape, ui, dash=True, banner_on=False):
    """retourne (landscape, ui, journal) modifies ; banner_on = fenetres par bandeau du theme
    (binaire sans le patch gui/pages.cpp qui dessine les fenetres lui-meme)"""
    out = []
    ui = re.sub(r'[ \t]*' + re.escape(BB) + r'.*?' + re.escape(BE) + r'\n', '', ui, flags=re.S)
    if banner_on and BANNER_ANCHOR in ui:
        ui = ui.replace(BANNER_ANCHOR, banner() + BANNER_ANCHOR, 1)
        out.append('fenetres : bandeau du theme')
    # barre d'etat : zone droite (ACC / frein / feux) ; remplace l'ancienne variable %tw_ujc201_car%
    ui = re.sub(r'\n\t\t\t<text color="%text_color%">\n\t\t\t\t<font resource="font_[ms]"/>\n\t\t\t\t<placement x="%indent_right%" '
                r'y="%row1_header_y%" placement="1"/>\n\t\t\t\t<text>%(tw_ujc201_car|property\.ujc201\.car)%</text>\n\t\t\t</text>\n', '', ui)
    if CAR_ANCHOR in ui:
        ui = ui.replace(CAR_ANCHOR, CAR_ANCHOR + CAR_ITEM, 1)
        out.append("barre d'etat : zone droite")
    else:
        out.append('ATTENTION : ancre batterie introuvable (barre vehicule en mode compact)')
    # bloc Advanced : on retire l'ancien (marqueurs ou anciennes entrees "cmd") puis on remet le bloc
    landscape = re.sub(r'[ \t]*' + re.escape(BEGIN) + r'.*?' + re.escape(END) + r'\n', '', landscape, flags=re.S)
    for n in OLD_NAMES:
        landscape = re.sub(r'[ \t]*<listitem name="%s">.*?</listitem>\n' % re.escape(n), '', landscape, flags=re.S)
    if ADV_ANCHOR in landscape:
        landscape = landscape.replace(ADV_ANCHOR, ADV_ANCHOR + adv_block(dash), 1)
        out.append('Advanced : entrees UJC201 (sortie console)' + (' + tableau de bord' if dash else ''))
    else:
        out.append('ATTENTION : liste Advanced introuvable')
    landscape = re.sub(r'\t\t<page name="ujc201_vehicle">.*?</page>\n', '', landscape, flags=re.S)
    if dash:
        i = landscape.rfind('\t</pages>')
        landscape = landscape[:i] + dash_page() + landscape[i:]
        if 'name="ujc_xl"' not in ui and FONT_ANCHOR in ui:
            ui = ui.replace(FONT_ANCHOR, FONT_ANCHOR + FONT_XL, 1)
        out.append('page ujc201_vehicle')
    return landscape, ui, out
