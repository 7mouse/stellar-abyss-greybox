#!/usr/bin/env python3
"""make_palette.py: source palette strip for the recolour shader (rig-parts-spec §11).
usage: make_palette.py out_prefix k psd [psd ...] [--layers a,b,c]
k-means (k clusters) on opaque pixels of all part layers; slot 0 = outline colour sampled from the real
line pixels (darkest quarter of the silhouette band), last slot = highlight (99.5th luminance percentile).
Writes <out_prefix>.png (16x16 per colour, left->right) and <out_prefix>.json (hex + role)."""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rig_joints as RJ
from rig_patch import load_psd
args = sys.argv[1:]
only = None
if '--layers' in args:            # v3: restrict to some layers (e.g. a recolour target built from the variant's body only)
    i = args.index('--layers'); only = set(args[i + 1].split(',')); del args[i:i + 2]
out, k, psds = args[0], int(args[1]), args[2:]
layers = []
for p in psds:
    L, o, _ = load_psd(p); layers += [L[n] for n in o if (only is None or n in only)]
line = RJ.line_color(layers)
cols = RJ.palette(layers, k=k, line_rgb=line)
assert 8 <= len(cols) <= 16, len(cols)
RJ.palette_png(cols, out + '.png')
roles = ['outline'] + ['base'] * (len(cols) - 2) + ['highlight']
json.dump({'cell': 16, 'count': len(cols), 'order': 'index 0 = outline, last = highlight, middle dark->light',
           'colors': [{'i': i, 'hex': '#%02X%02X%02X' % c, 'rgb': c, 'role': r} for i, (c, r) in enumerate(zip(cols, roles))]},
          open(out + '.json', 'w'), indent=1)
print(out, len(cols), ['#%02X%02X%02X' % c for c in cols])
