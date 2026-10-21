#!/usr/bin/env python3
"""make_ui_states.py: U09 cooldown mask + pressed overlay derived by tool from a round button's silhouette.
usage: make_ui_states.py button.png out_dir
cooldown mask: the button's opaque silhouette, eroded 6% (inside the rim), charcoal #1E1C1A at alpha 0.62 (the game
sweeps it radially by shader); pressed: same silhouette, black at alpha 0.28."""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage as nd
b = np.asarray(Image.open(sys.argv[1]).convert('RGBA')).astype(float); out = sys.argv[2]; os.makedirs(out, exist_ok=True)
m = nd.binary_fill_holes(b[..., 3] > 128); m = nd.binary_erosion(m, iterations=max(1, int(0.06 * m.shape[0])))
soft = np.clip(nd.distance_transform_edt(m) / 1.5, 0, 1)
for name, rgb, al in (('u09_cooldown_mask', (30, 28, 26), 0.62), ('u09_pressed', (0, 0, 0), 0.28)):
    o = np.zeros_like(b); o[..., :3] = rgb; o[..., 3] = soft * al * 255
    Image.fromarray(o.astype(np.uint8), 'RGBA').save(f'{out}/{name}.png')
print('ok', m.shape)
