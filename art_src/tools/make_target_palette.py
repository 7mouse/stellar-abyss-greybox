#!/usr/bin/env python3
"""make_target_palette.py: target strip for a recolour variant, index-matched to a source strip (rig-parts-spec §11).
usage: make_target_palette.py src_palette.json src_psd layer sheet.jpg x0,y0,x1,y1 out_prefix [--ds 1.25] [--min-lum 70]
Same mapping cut_partsheet's "recolor_ref" applies to the variant body: every source colour whose luminance is above
--min-lum is mapped per channel by quantile (its rank among the source layer's pixels -> the same quantile of the
reference rect on the sheet). Dark line colours (outline slot) and the highlight slot are kept, so index i of the
target is exactly what source colour i becomes."""
import sys, json, argparse, os
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rig_joints as RJ
from rig_patch import load_psd
ap = argparse.ArgumentParser(); ap.add_argument('src'); ap.add_argument('psd'); ap.add_argument('layer'); ap.add_argument('sheet'); ap.add_argument('rect'); ap.add_argument('out')
ap.add_argument('--ds', type=float, default=1.25); ap.add_argument('--min-lum', type=float, default=70)
a = ap.parse_args()
src = json.load(open(a.src)); cols = [np.array(c['rgb'], float) for c in src['colors']]
L, o, _ = load_psd(a.psd); lay = L[a.layer]; px = lay[..., :3][lay[..., 3] > 0.5] * 255
lum = px @ [0.299, 0.587, 0.114]; px = px[lum > a.min_lum]
x0, y0, x1, y1 = [int(float(v) * a.ds) for v in a.rect.split(',')]
ref = np.array(Image.open(a.sheet).convert('RGB')).astype(float)[y0:y1, x0:x1].reshape(-1, 3)
out = []
for i, c in enumerate(cols):
    l = c @ [0.299, 0.587, 0.114]
    if i == 0 or i == len(cols) - 1 or l <= a.min_lum:
        out.append(tuple(int(v) for v in c)); continue
    t = []
    for ch in range(3):
        q = (px[:, ch] <= c[ch]).mean(); t.append(int(round(np.quantile(ref[:, ch], np.clip(q, 0, 1)))))
    out.append(tuple(t))
RJ.palette_png(out, a.out + '.png')
json.dump({'cell': 16, 'count': len(out), 'source_strip': a.src, 'order': 'index-matched to the source strip (slot i -> slot i)',
           'colors': [{'i': i, 'hex': '#%02X%02X%02X' % c, 'rgb': c, 'from': src['colors'][i]['hex']} for i, c in enumerate(out)]}, open(a.out + '.json', 'w'), indent=1)
print(a.out, ['#%02X%02X%02X' % c for c in out])
