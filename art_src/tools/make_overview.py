#!/usr/bin/env python3
"""make_overview.py: level-1 overview sheet (every delivered asset side by side at game scale + combat_baseline_v2 crop).
usage: make_overview.py out.png   (run from the repo root)
Game scale = 1080p: hero 135 px tall (level1-polish-spec §8.1) -> every character preview scaled by 135 / hero height,
so relative sizes are exactly as delivered. Baseline 1280x720 crop shown x1.5 (= 1080p). Tiles at 256 (half of 512),
props/HUD/FX at their 1:1 cut size x0.5 (the AI cut size is not yet the in-game size; noted on the sheet)."""
import sys, glob, json, os
from PIL import Image, ImageDraw
R = 'art_src/rigs/'
def prev(p): im = Image.open(p).convert('RGBA'); return im.crop(im.getbbox())
hero = prev(R + 'hero/hero_parts_s_v2_2_preview.png'); k = 135 / hero.height
chars = [('hero f/s/b v2.2', [R + 'hero/hero_parts_f_v2_2_preview.png', R + 'hero/hero_parts_s_v2_2_preview.png', R + 'hero/hero_parts_b_v2_2_preview.png']),
         ('sprout_boar f v1.1 / s v2.2 / b v1.1', [R + 'sprout_boar/sprout_boar_parts_f_v1_1_preview.png', R + 'sprout_boar/sprout_boar_parts_s_v2_2_preview.png', R + 'sprout_boar/sprout_boar_parts_b_v1_1_preview.png']),
         ('root_spore_mushroom f/s/b v1.1', [R + f'root_spore_mushroom/root_spore_mushroom_parts_{f}_v1_1_preview.png' for f in 'fsb']),
         ('slime v1.1', [R + 'slime/slime_parts_v1_1_preview.png']),
         ('deep_moss_slime v1.1', [R + 'deep_moss_slime/deep_moss_slime_parts_v1_1_preview.png']),
         ('mosscrown_king_boar f/s/b v2.1 (redraw)', [R + f'mosscrown_king_boar/mosscrown_king_boar_parts_{f}_v2_1_preview.png' for f in 'fsb'])]
W = 2600; BG = (226, 222, 212, 255)
sheet = Image.new("RGBA", (W, 4000), BG); d = ImageDraw.Draw(sheet)
d.text((20, 12), 'Stellar Abyss - level 1 art batch ' + (sys.argv[2] if len(sys.argv) > 2 else '2026-10-21d') + ' - overview at game scale (1080p, hero = 135 px). AI output cut by tool, no hand painting.', fill=(20, 20, 20, 255))
# baseline crop
base = Image.open('art_src/ref/combat_baseline_v2.jpg').convert('RGBA').crop((380, 250, 980, 560)); base = base.resize((base.width * 3 // 2, base.height * 3 // 2), Image.LANCZOS)
sheet.alpha_composite(base, (20, 40)); d.text((24, 44 + base.height), 'combat_baseline_v2 crop @1080p (reference)', fill=(20, 20, 20, 255))
# characters on a ground strip
x = base.width + 60; y_ground = 40 + base.height - 20
d.rectangle([x - 20, 40, W - 20, 40 + base.height], fill=(122, 128, 96, 255))
for label, files in chars:
    x0 = x
    for f in files:
        im = prev(f); im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        sheet.alpha_composite(im, (x, y_ground - im.height)); x += im.width + 8
    d.text((x0, y_ground + 6), label, fill=(255, 255, 255, 255)); x += 40
y = 40 + base.height + 40
def row(title, files, scale, maxh=None, ystart=None, cols_w=W - 40):
    global y
    d.text((20, y), title, fill=(20, 20, 20, 255)); y += 16; xx = 20; rh = 0
    for f in files:
        im = Image.open(f).convert('RGBA'); im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
        if maxh and im.height > maxh: im = im.resize((round(im.width * maxh / im.height), maxh), Image.LANCZOS)
        if xx + im.width > cols_w: xx = 20; y += rh + 18; rh = 0
        sheet.alpha_composite(im, (xx, y)); d.text((xx, y + im.height + 2), os.path.basename(f)[:30], fill=(60, 60, 60, 255))
        xx += im.width + 14; rh = max(rh, im.height)
    y += rh + 30
T = 'art_src/terrain/floor1_v2/'
row('Terrain v2 S01 tiles 512 (shown at 1/2): min-cut wrapped, seam test <= 1.15 on every axis', [T + f'tiles/s01_{n}.png' for n in ('ground_moss', 'ground_autumn', 'ground_stone', 'ground_stone_large', 'water')], 0.5)
row('Terrain v2 S02 edge overlays 512x128 + corners 128 (x0.75, on grey)', [T + 'edges/s02_edge_moss_stone.png', T + 'edges/s02_edge_moss_stone_corner_outer.png', T + 'edges/s02_edge_moss_stone_corner_inner.png', T + 'edges/s02_edge_autumn_moss.png', T + 'edges/s02_edge_autumn_moss_corner_outer.png', T + 'edges/s02_edge_autumn_moss_corner_inner.png'], 0.75)
row('Terrain v2 S03 trees (whole / crown / base, 512x768, x0.5), S05 rocks, S06 ruins, S04 bushes, S18, S07 decals, S09 light (1:1 x0.5)',
    [T + f'trees/s03_tree_{t}{p}.png' for t in ('autumn', 'green') for p in ('', '_crown', '_base')] + sorted(glob.glob(T + 'props_rocks_ruins/s0*.png')) + sorted(glob.glob(T + 'props_bushes_decals/s*.png')) + sorted(glob.glob(T + 'light/s09*.png')), 0.5)
U = 'art_src/ui/hud_v2/'
row('HUD v2 thin-border set (9-slice rebuilt; 1:1 x0.6): U02, U10, U07, U15 x5 tints, U03, panels, U01/U04/U05/U06/U08, U16 x9',
    [U + 'bars/u02_bar_frame.png', U + 'bars/u02_fill_hp.png', U + 'bars/u02_fill_mp.png', U + 'bars/u02_fill_sp.png', U + 'bars/u10_boss_bar_frame.png', U + 'bars/u10_fill_boss.png', U + 'icons/u10_boss_icon.png', U + 'frames/u07_slot.png']
    + sorted(glob.glob(U + 'frames/u15_quality_frame_*.png')) + [U + 'frames/u03_level_badge.png'] + sorted(glob.glob(U + 'panels/*.png')) + sorted(glob.glob(U + 'hud/*.png')) + sorted(glob.glob(U + 'icons_u16/u16_*.png')), 0.6)
row('U11-U13 screens 1920x1080 (x0.3, over a dark backdrop)', [U + 'screens/u11_backpack.png', U + 'screens/u12_extract_result.png', U + 'screens/u13_vault_storage.png'], 0.3)
F = 'art_src/fx/fx_v1/'
fx = sorted(glob.glob(F + '*/*.png'))
row('FX frames (1:1 cut x0.6)', fx, 0.6)
sheet = sheet.crop((0, 0, W, y + 10)); sheet.save(sys.argv[1]); print(sys.argv[1], sheet.size)
