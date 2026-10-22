#!/usr/bin/env python3
"""swap_sheet.py: preview each swap layer of a rig version on top of the rest pose (zoomed crop), for review.
usage: swap_sheet.py <base 1:1 psd> out.png [--crop x0 y0 x1 y1] [--zoom 3] [--only name,name] [--hide name,name]"""
import sys, argparse
from PIL import Image, ImageDraw
from psd_tools import PSDImage
ap = argparse.ArgumentParser(); ap.add_argument('psd'); ap.add_argument('out'); ap.add_argument('--crop', nargs=4, type=int); ap.add_argument('--zoom', type=int, default=3)
ap.add_argument('--only', default=''); ap.add_argument('--hide', default='')
a = ap.parse_args(); psd = PSDImage.open(a.psd); W, H = psd.size
L = []
for l in psd:
    if l.name.startswith('_'): continue
    cv = Image.new('RGBA', (W, H)); im = l.topil()
    if im is not None: cv.alpha_composite(im.convert('RGBA'), (l.left, l.top))
    L.append((l.name, cv, l.visible))
swaps = [n for n, _, v in L if not v and (not a.only or n in a.only.split(','))]
cols = ['(rest)'] + swaps; crop = a.crop or (0, 0, W, H); cw, ch = (crop[2] - crop[0]) * a.zoom, (crop[3] - crop[1]) * a.zoom
sh = Image.new('RGBA', (len(cols) * (cw + 6), ch + 18), (120, 120, 120, 255)); d = ImageDraw.Draw(sh)
hide = set(a.hide.split(',')) if a.hide else set()
for i, sw in enumerate(cols):
    cv = Image.new('RGBA', (W, H), (150, 150, 150, 255))
    for n, im, vis in L:
        if (vis and n not in hide) or n == sw: cv.alpha_composite(im)
    sh.paste(cv.crop(crop).resize((cw, ch), Image.NEAREST), (i * (cw + 6), 18)); d.text((i * (cw + 6) + 2, 2), sw, fill=(255, 255, 255, 255))
sh.save(a.out); print(a.out, sh.size)
