#!/usr/bin/env python3
"""make_shadows.py: S08 contact shadows (3 sizes) by tool - soft ellipse, warm charcoal #1E1A14, 256x128 canvas.
usage: make_shadows.py out_dir"""
import sys, os
import numpy as np
from PIL import Image
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
Y, X = np.mgrid[0:128, 0:256].astype(float) + 0.5
for name, (rx, ry, a) in {'s08_contact_shadow_s': (60, 22, 0.42), 's08_contact_shadow_m': (90, 32, 0.45), 's08_contact_shadow_l': (120, 46, 0.48)}.items():
    r = np.sqrt(((X - 128) / rx) ** 2 + ((Y - 64) / ry) ** 2)
    al = np.clip(1 - r, 0, 1) ** 1.6 * a
    im = np.zeros((128, 256, 4)); im[..., :3] = (30, 26, 20); im[..., 3] = al * 255
    Image.fromarray(im.astype(np.uint8), 'RGBA').save(f'{out}/{name}.png')
print('ok')
