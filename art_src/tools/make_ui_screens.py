#!/usr/bin/env python3
"""make_ui_screens.py: U11-U13 full-screen layouts (1920x1080) assembled from the cut v2 pieces (window panel,
header plate, slot, quality frame, button), each stretched as a 9-slice with its measured margins. No text: the
engine draws labels/numbers. Layout follows ui_style_v1 (charcoal translucent panels, thin off-white line).
usage: make_ui_screens.py hud_v2_dir out_dir"""
import json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from make_ui_v2 import nine

D, OUT = sys.argv[1], sys.argv[2]; man = json.load(open(f'{D}/manifest_v2.json'))
def piece(group, n): return np.asarray(Image.open(f'{D}/{group}/{n}.png').convert('RGBA')).astype(float)
P = {'panel': ('panels', 'ui_panel_window'), 'head': ('panels', 'ui_header_plate'), 'btn': ('panels', 'ui_button'),
     'btn_hi': ('panels', 'ui_button_hi'), 'slot': ('frames', 'u07_slot'), 'cell': ('frames', 'u15_quality_frame_grey')}
def put(cv, key, x, y, w, h):
    g, n = P[key]; src = piece(g, n); m = man.get(n, man.get('u15_quality_frame', {})).get('nine')
    o, _ = nine(src, w, h, m, None, tile_center=True)
    cv.alpha_composite(Image.fromarray(np.clip(o, 0, 255).astype(np.uint8), 'RGBA'), (x, y))
def grid(cv, key, x0, y0, cols, rows, s, gap):
    for r in range(rows):
        for c in range(cols): put(cv, key, x0 + c * (s + gap), y0 + r * (s + gap), s, s)
def screen():
    return Image.new('RGBA', (1920, 1080), (16, 16, 18, 150))     # dim the game behind
os.makedirs(OUT, exist_ok=True); layout = {}
# U11 backpack: equipment on the left, 8x5 bag grid on the right, item info under it, 2 buttons
cv = screen(); put(cv, 'head', 660, 40, 600, 84)
put(cv, 'panel', 80, 150, 600, 820); grid(cv, 'slot', 130, 210, 1, 4, 120, 40); grid(cv, 'slot', 510, 210, 1, 4, 120, 40)
put(cv, 'panel', 720, 150, 1120, 620); grid(cv, 'cell', 770, 200, 8, 4, 116, 14)
put(cv, 'panel', 720, 790, 1120, 180); put(cv, 'btn', 1440, 990, 190, 64); put(cv, 'btn_hi', 1650, 990, 190, 64)
cv.save(f'{OUT}/u11_backpack.png'); layout['u11_backpack'] = 'title 660,40 600x84; equipment panel 80,150 600x820 with 8 slots; bag panel 720,150 1120x620 (8x4 cells 116); info panel 720,790 1120x180; buttons 1440/1650,990'
# U12 extraction result: one centred panel, title, 3 stat plates, a loot row, 2 buttons
cv = screen(); put(cv, 'panel', 410, 120, 1100, 840); put(cv, 'head', 610, 80, 700, 90)
for i in range(3): put(cv, 'head', 480, 210 + i * 86, 960, 70)
grid(cv, 'cell', 480, 500, 7, 2, 120, 20); put(cv, 'btn', 700, 860, 240, 70); put(cv, 'btn_hi', 980, 860, 240, 70)
cv.save(f'{OUT}/u12_extract_result.png'); layout['u12_extract_result'] = 'panel 410,120 1100x840; title 610,80; stat plates 480,210/296/382 960x70; loot 7x2 cells 120 from 480,500; buttons 700/980,860'
# U13 village vault / storage: two grids side by side, transfer buttons between them
cv = screen(); put(cv, 'head', 660, 40, 600, 84)
put(cv, 'panel', 60, 150, 830, 860); put(cv, 'head', 100, 175, 750, 64); grid(cv, 'cell', 112, 270, 6, 5, 112, 26)
put(cv, 'panel', 1030, 150, 830, 860); put(cv, 'head', 1070, 175, 750, 64); grid(cv, 'cell', 1082, 270, 6, 5, 112, 26)
put(cv, 'btn', 900, 480, 120, 64); put(cv, 'btn', 900, 570, 120, 64)
cv.save(f'{OUT}/u13_vault_storage.png'); layout['u13_vault_storage'] = 'title 660,40; left panel 60,150 830x860 (6x5 cells 112); right panel 1030,150; transfer buttons 900,480/570 120x64'
json.dump(layout, open(f'{OUT}/layout.json', 'w'), indent=1); print('ok')
