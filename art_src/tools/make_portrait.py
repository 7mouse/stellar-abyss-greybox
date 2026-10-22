#!/usr/bin/env python3
"""make_portrait.py: C03 hero portrait (AI image, D proportion) -> circular 512 / 256 PNG with an anti-aliased alpha
circle, for the U01 portrait ring (ring inner hole is drawn over it). usage: make_portrait.py src.jpg out_dir"""
import sys, os
import numpy as np
from PIL import Image
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
im = Image.open(src).convert('RGB'); a = np.asarray(im).astype(float)
paper = np.median(np.concatenate([a[:8, :8].reshape(-1, 3), a[:8, -8:].reshape(-1, 3)]), 0)
fg = np.abs(a - paper).sum(2) > 40
ys, xs = np.nonzero(fg); cx, cy = (xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2
r = min(xs.max() - xs.min(), ys.max() - ys.min()) / 2 - 6          # 6 px inside the painted disc edge
crop = im.crop((int(cx - r), int(cy - r), int(cx + r), int(cy + r)))
for n in (512, 256):
    c = crop.resize((n, n), Image.LANCZOS).convert('RGBA')
    Y, X = np.mgrid[0:n * 4, 0:n * 4] + 0.5; m = (np.hypot(X - n * 2, Y - n * 2) <= n * 2).astype(np.uint8) * 255
    c.putalpha(Image.fromarray(m).resize((n, n), Image.LANCZOS)); c.save(f'{out}/c03_hero_portrait_{n}.png')
print('circle', round(cx), round(cy), round(r))
