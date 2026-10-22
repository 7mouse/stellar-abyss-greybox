#!/usr/bin/env python3
"""split_tree.py: one AI tree on white -> <name>.png (whole), <name>_crown.png, <name>_base.png on one canvas
(same size, same offset, so they stack exactly). crown = the biggest foliage blob, closed and hole-filled
(branches seen between leaf clusters go with it); base = everything else (trunk, roots, mossy foot).
The engine y-sorts the base and draws the crown above characters (fade it when the player is behind).
usage: split_tree.py src.jpg out_dir name canvas_w canvas_h [hue_lo,hue_hi of the leaves, 0..1]"""
import sys, os, json
import numpy as np
from PIL import Image
from scipy import ndimage as nd
sys.path.insert(0, os.path.dirname(__file__))
from cut_sprites import segment, rgb2hsv

src, od, name, CW, CH = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
rgb, lab, NI, rgba = segment(src)
H, W = lab.shape; ids, cnt = np.unique(lab[lab > 0], return_counts=True); obj = lab == ids[cnt.argmax()]
h, s, v = rgb2hsv(rgb)
ys, xs = np.nonzero(obj); y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
# the white paper seen through gaps between branches must be transparent (segment() fills enclosed holes)
d = 255 - rgb.min(2); rgba[..., 3] = np.clip((d - 14) * 9, 0, 255) * obj
hr = [float(x) for x in (sys.argv[6].split(',') if len(sys.argv) > 6 else '0.0,1.0'.split(','))]
fol = obj & (h >= hr[0]) & (h <= hr[1]) & (s > 0.25) & (v > 0.3)
fol = nd.binary_opening(fol, iterations=2)
fl, n = nd.label(fol); keep = np.zeros_like(fol)
ycut = y0 + 0.72 * (y1 - y0)                     # leaf clusters centred above this belong to the crown; the mossy foot is below
for i, sl in enumerate(nd.find_objects(fl)):
    m = fl[sl] == i + 1; cy = sl[0].start + np.nonzero(m)[0].mean()
    if cy < ycut and m.sum() > 60: keep[sl] |= m
yy = np.arange(H)[:, None] * np.ones((1, W))
can = obj & (nd.binary_dilation(keep, iterations=5) | (yy < y0 + 0.45 * (y1 - y0)))
vis = obj & (rgba[..., 3] > 20)
def comps(m):
    l, n = nd.label(m); return l, (nd.sum(m, l, range(1, n + 1)) if n else np.array([]))
bl, ba = comps(vis & ~can)                       # stray bark/outline crumbs left in the base go to the crown
if len(ba): can |= (bl > 0) & (bl != int(np.argmax(ba)) + 1)
cl, ca = comps(vis & can)                        # stray foot-moss bits in the crown go back to the base
for i in range(len(ca)):
    if i != int(np.argmax(ca)) and np.nonzero(cl == i + 1)[0].mean() > y0 + 0.6 * (y1 - y0): can &= cl != i + 1
crown = rgba.copy(); crown[..., 3] *= can; base = rgba.copy(); base[..., 3] *= ~can
k = min(1.0, (CW - 8) / (x1 - x0), (CH - 8) / (y1 - y0))
os.makedirs(od, exist_ok=True); meta = {}
for nm, a in ((name, rgba * np.dstack([np.ones((H, W, 3)), obj[..., None]])), (name + '_crown', crown), (name + '_base', base)):
    im = Image.fromarray(np.clip(a[y0:y1, x0:x1], 0, 255).astype(np.uint8), 'RGBA')
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    cv = Image.new('RGBA', (CW, CH)); ox = (CW - im.width) // 2; oy = CH - im.height - 4
    cv.alpha_composite(im, (ox, oy)); cv.save(f'{od}/{nm}.png')
ys2 = np.nonzero(obj[:, :].any(1))[0]
foot = int(oy + (y1 - y0) * k * 0.93)
meta = {'canvas': [CW, CH], 'scale': round(k, 3), 'sort_y': foot, 'src': src,
        'crown_px': int(can.sum()), 'base_px': int((obj & ~can).sum())}
json.dump(meta, open(f'{od}/{name}.json', 'w'), indent=1); print(name, meta)
