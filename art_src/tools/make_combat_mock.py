#!/usr/bin/env python3
"""make_combat_mock.py: in-combat comparison mock at game scale (1920x1080, hero = 135 px), built only from the cut
assets: floor1_v2 tiles + edge overlays + props, the rig previews (hero s v2.2, sprout_boar s v2.2, slime v1.1),
and hud_v2 (9-slice pieces stretched to the HUD layout of ui_style_v1 定稿 v2). Text = engine stand-in (Noto Sans).
Output: mock 1080p + side-by-side with combat_baseline_v2 (upscaled to 1080p).
usage: make_combat_mock.py out_side_by_side.png out_mock_1080p.png"""
import sys, json, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(__file__))
from make_ui_v2 import nine

T = 'art_src/terrain/floor1_v2/'; U = 'art_src/ui/hud_v2/'; R = 'art_src/rigs/'
FONT = '/usr/share/fonts/truetype/sand-box/google/Noto Sans/NotoSans-VariableFont_wdth,wght.ttf'
def L(p): return Image.open(p).convert('RGBA')
def font(sz): return ImageFont.truetype(FONT, sz)
W, H = 1920, 1080; CELL = 512; OX, OY = -64, -200
mat = [['autumn', 'moss', 'moss', 'moss'], ['moss', 'moss', 'stone', 'moss'], ['moss', 'moss', 'stone', 'moss']]
tile = {m: L(f'{T}tiles/s01_ground_{m}.png') for m in ('moss', 'autumn', 'stone')}
cv = Image.new('RGBA', (W, H))
for r, row in enumerate(mat):
    for c, m in enumerate(row): cv.alpha_composite(tile[m], (OX + c * CELL, OY + r * CELL))
def cell(c, r): return OX + c * CELL, OY + r * CELL
ms = L(T + 'edges/s02_edge_moss_stone.png'); am = L(T + 'edges/s02_edge_autumn_moss.png')
def strip_h(s, x, y, flip=False):   # top material above y (or below if flip)
    s2 = s.transpose(Image.FLIP_TOP_BOTTOM) if flip else s; cv.alpha_composite(s2, (x, y - (88 if not flip else 40)))
def strip_v(s, x, y, a_left=True):
    s2 = s.transpose(Image.ROTATE_90) if a_left else s.transpose(Image.ROTATE_270)
    cv.alpha_composite(s2, (x - 88 if a_left else x - 40, y))
# stone column c2 rows 1..2: moss above, left, right
x2, y1 = cell(2, 1)
strip_h(ms, x2, y1); strip_v(ms, x2, y1, True); strip_v(ms, x2, y1 + CELL, True); strip_v(ms, x2 + CELL, y1, False); strip_v(ms, x2 + CELL, y1 + CELL, False)
ci = L(T + 'edges/s02_edge_moss_stone_corner_inner.png')
cv.alpha_composite(ci, (x2 - 64, y1 - 64)); cv.alpha_composite(ci.transpose(Image.FLIP_LEFT_RIGHT), (x2 + CELL - 64, y1 - 64))
# autumn cell c0 r0: autumn above moss (bottom edge) and left of moss (right edge), outer corner
x0, y0 = cell(0, 0)
strip_h(am, x0, y0 + CELL); strip_v(am, x0 + CELL, y0, True)
cv.alpha_composite(L(T + 'edges/s02_edge_autumn_moss_corner_outer.png'), (x0 + CELL - 64, y0 + CELL - 64))
# decals, leaf light, shadows, props (y-sorted with the characters)
for n, x, y in [('s07_moss_decal_a', 300, 640), ('s07_moss_decal_c', 1350, 300), ('s07_moss_decal_d', 60, 860)]:
    d = L(f'{T}props_bushes_decals/{n}.png'); d.putalpha(d.getchannel('A').point(lambda v: int(v * 0.55))); cv.alpha_composite(d, (x, y))
sh = {k: L(f'art_src/terrain/floor1_v1/shadows/s08_contact_shadow_{k}.png') for k in 'sml'}
objs = []   # (foot_y, image, x, y, shadow)
def obj(img, cx, foot, shadow=None, sw=None):
    objs.append((foot, img, cx - img.width // 2, foot - img.height, shadow, sw, cx))
PR = T + 'props_rocks_ruins/'; PB = T + 'props_bushes_decals/'
obj(L(PR + 's06_ruin_pillar.png').resize((150, 260)), 1290, 470, 'm', 170)
obj(L(PR + 's06_ruin_wall.png'), 230, 700, 'l', 260)
obj(L(PR + 's06_ruin_blocks.png').resize((250, 214)), 1700, 760, 'l', 240)
obj(L(PR + 's05_rock_large.png').resize((180, 152)), 560, 980, 'm', 170)
obj(L(PR + 's05_rock_medium.png').resize((110, 100)), 1520, 1020, 'm', 110)
obj(L(PR + 's05_rock_small.png'), 1120, 330, 's', 80)
obj(L(PR + 's05_pebbles.png'), 780, 470)
obj(L(PB + 's04_bush_round.png').resize((170, 160)), 90, 470, 'm', 160)
obj(L(PB + 's04_bush_wide.png').resize((200, 140)), 1840, 640, 'm', 190)
obj(L(PB + 's04_bush_flowers.png').resize((150, 140)), 980, 1060, 'm', 140)
ring = L(PB + 's18_glow_mushroom_ring.png').resize((170, 148)); obj(ring, 330, 1000)
tb = L(T + 'trees/s03_tree_autumn_base.png'); tc = L(T + 'trees/s03_tree_autumn_crown.png')
tg = L(T + 'trees/s03_tree_green_base.png'); tgc = L(T + 'trees/s03_tree_green_crown.png')
objs.append((390, tb, 330 - 256, 390 - 722, 'l', 260, 330)); objs.append((420, tg, 1660 - 256, 420 - 720, 'l', 240, 1660))
# characters at game scale: hero 135 px
def rig(p, flip=False):
    im = L(p); im = im.crop(im.getbbox()); return im.transpose(Image.FLIP_LEFT_RIGHT) if flip else im
hero = rig(R + 'hero/hero_parts_s_v2_2_preview.png'); k = 135 / hero.height
def sc(im, f=1.0): return im.resize((round(im.width * k * f), round(im.height * k * f)), Image.LANCZOS)
obj(sc(hero), 900, 700, 's', 90)
obj(sc(rig(R + 'sprout_boar/sprout_boar_parts_s_v2_2_preview.png', flip=True)), 1180, 690, 'm', 130)
sl = rig(R + 'slime/slime_parts_v1_1_preview.png')
for x, y, f in [(640, 560, False), (700, 860, True), (1180, 900, False), (1430, 600, True)]: obj(sc(sl.transpose(Image.FLIP_LEFT_RIGHT) if f else sl), x, y, 's', 80)
for foot, img, x, y, s, sw, cx in sorted(objs, key=lambda o: o[0]):
    if s:
        shd = sh[s].resize((sw, max(8, sw // 3))); cv.alpha_composite(shd, (cx - sw // 2, foot - shd.height // 2 - 4))
    cv.alpha_composite(img, (x, y))
cv.alpha_composite(tc, (330 - 256, 390 - 722)); cv.alpha_composite(tgc, (1660 - 256, 420 - 720))
lt = L(T + 'light/s09_leaf_light_a.png'); lt.putalpha(lt.getchannel('A').point(lambda v: int(v * 0.22)))
base = np.asarray(cv).astype(float); add = np.zeros_like(base); X, Y = 760, 420
a = np.asarray(lt).astype(float); add[Y:Y + a.shape[0], X:X + a.shape[1], :3] = a[..., :3] * a[..., 3:4] / 255
cv = Image.fromarray(np.clip(base + add, 0, 255).astype(np.uint8), 'RGBA')
# HUD (ui_style_v1 定稿 v2 layout)
man = json.load(open(U + 'manifest_v2.json'))
def P(group, n): return np.asarray(L(f'{U}{group}/{n}.png')).astype(float)
def N(group, n, w, h, mkey=None):
    o, _ = nine(P(group, n), w, h, man[mkey or n]['nine'], None); return Image.fromarray(np.clip(o, 0, 255).astype(np.uint8), 'RGBA')
def put(img, x, y): cv.alpha_composite(img, (x, y))
def text(s, x, y, sz, col=(236, 230, 214), anchor='la'):
    ImageDraw.Draw(cv).text((x, y), s, font=font(sz), fill=col, anchor=anchor)
# portrait + level + bars
por = L(U + 'hud/u01_portrait_ring.png').resize((132, 132)); face = L(R + 'hero/parts_v2_2/head_f.png'); face = face.crop(face.getbbox()); face.thumbnail((104, 104))
disc = Image.new('RGBA', (132, 132)); ImageDraw.Draw(disc).ellipse([8, 8, 124, 124], fill=(40, 42, 46, 200)); disc.alpha_composite(face, (66 - face.width // 2, 70 - face.height // 2))
m = Image.new('L', (132, 132)); ImageDraw.Draw(m).ellipse([9, 9, 123, 123], fill=255); disc.putalpha(Image.fromarray(np.minimum(np.asarray(disc.getchannel('A')), np.asarray(m))))
put(disc, 24, 20); put(por, 24, 20)
put(L(U + 'frames/u03_level_badge.png').resize((52, 52)), 120, 104); text('18', 146, 130, 22, anchor='mm')
for i, (fn, frac, lab) in enumerate([('u02_fill_hp', 1.0, 'HP'), ('u02_fill_mp', 0.7, 'MP'), ('u02_fill_sp', 0.85, 'SP')]):
    x, y, w, h = 168, 34 + i * 34, 400, 26
    put(N('bars', 'u02_bar_frame', w, h), x, y)
    f = L(f'{U}bars/{fn}.png').resize((round((w - 8) * frac), h - 8)); put(f, x + 4, y + 4)
    text(lab, x + 12, y + h // 2, 15, anchor='lm')
    if i == 0: text('1240 / 1240', x + w - 12, y + h // 2, 15, anchor='rm')
# top right: bag/shard plate, floor plate, pause, minimap
put(N('panels', 'ui_header_plate', 120, 54), 1776, 20); text('1F', 1836, 47, 26, anchor='mm')
put(N('panels', 'ui_button', 250, 54), 1500, 84); put(L(U + 'hud/u08_backpack.png').resize((34, 38)), 1516, 92); text('7/12', 1560, 111, 22, anchor='lm')
put(L(U + 'hud/u08_shard.png').resize((24, 38)), 1640, 92); text('32', 1676, 111, 22, anchor='lm')
put(N('panels', 'ui_button', 66, 54), 1830, 84); put(L(U + 'hud/u08_pause.png').resize((26, 32)), 1850, 95)
mm = Image.new('RGBA', (240, 240)); mini = cv.crop((0, 0, 1920, 1080)).resize((240, 135)).filter(ImageFilter.GaussianBlur(1.2))
mm.alpha_composite(mini, (0, 52)); mk = Image.new('L', (240, 240)); ImageDraw.Draw(mk).ellipse([14, 14, 226, 226], fill=210)
mm.putalpha(mk); put(mm, 1660, 150); put(L(U + 'hud/u04_minimap_ring.png').resize((240, 240)), 1660, 150)
# bottom right: attack + 4 skills on an arc; bottom left: consumable slot
put(L(U + 'hud/u05_attack.png').resize((200, 200)), 1690, 850)
for n, (x, y) in zip(['u06_heavy', 'u06_dash', 'u06_skill1', 'u06_skill2'], [(1540, 960), (1530, 800), (1630, 690), (1790, 680)]):
    put(L(f'{U}hud/{n}.png').resize((112, 112)), x, y)
put(N('frames', 'u07_slot', 120, 120), 30, 930); pot = L(U + 'icons_u16/u16_heal_potion.png'); pot.thumbnail((84, 84)); put(pot, 90 - pot.width // 2, 990 - pot.height // 2); text('3', 136, 1034, 22, anchor='rm')
mock = cv.convert('RGB'); mock.save(sys.argv[2])
# side by side with the baseline
bl = Image.open('art_src/ref/combat_baseline_v2.jpg').convert('RGB').resize((W, H), Image.LANCZOS)
out = Image.new('RGB', (W * 2 + 40, H + 70), (24, 24, 26)); out.paste(mock, (0, 70)); out.paste(bl, (W + 40, 70))
d = ImageDraw.Draw(out)
d.text((10, 20), 'NEW 2026-10-21d: floor1_v2 terrain + hud_v2 + hero s v2.2 / sprout_boar s v2.2 / slime v1.1, 1080p game scale (hero 135 px). Built only from cut assets.', font=font(24), fill=(236, 230, 214))
d.text((W + 50, 20), 'REFERENCE: combat_baseline_v2 (1280x720 upscaled to 1080p)', font=font(24), fill=(236, 230, 214))
out.save(sys.argv[1]); print(sys.argv[1], out.size)
