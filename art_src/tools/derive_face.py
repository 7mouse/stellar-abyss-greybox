#!/usr/bin/env python3
"""derive_face.py: split a painted face disc (AI part) into floating feature parts by tool, no painting.
usage: derive_face.py sheet.jpg x0,y0,x1,y1(display coords) out_prefix [--ds 1.25] [--thr 38] [--erode 6]
Keeps pixels that differ from the face's own fill colour (median) by > thr inside the eroded disc (drops the outer
outline ring), labels blobs and saves them as <out_prefix>_eye_r/_eye_l/_mouth/_blush_r/_blush_l.png (viewer-left = r),
each on a white-free RGBA crop (alpha from colour distance), plus <out_prefix>_features.json with display boxes."""
import sys, json, argparse
import numpy as np
from PIL import Image
from scipy import ndimage as nd
ap = argparse.ArgumentParser(); ap.add_argument('sheet'); ap.add_argument('rect'); ap.add_argument('out')
ap.add_argument('--ds', type=float, default=1.25); ap.add_argument('--thr', type=float, default=38); ap.add_argument('--erode', type=int, default=6)
a = ap.parse_args()
x0, y0, x1, y1 = [int(float(v) * a.ds) for v in a.rect.split(',')]
rgb = np.array(Image.open(a.sheet).convert('RGB')).astype(float)[y0:y1, x0:x1]
d = 255 - rgb.min(2); disc = nd.binary_fill_holes(nd.binary_closing(d > 28, iterations=2))
lab, n = nd.label(disc); disc = lab == (np.argmax(nd.sum(disc, lab, range(1, n + 1))) + 1)
inner = nd.binary_erosion(disc, iterations=a.erode)
fill = np.median(rgb[inner], 0)
dist = np.sqrt(((rgb - fill) ** 2).sum(2))
feat = (dist > a.thr) & inner
lumc = rgb @ [0.299, 0.587, 0.114]
darkm = feat & (lumc < 140); pinkm = feat & ~nd.binary_dilation(darkm, iterations=2)
l2 = np.zeros(feat.shape, int); k_ = 0
for mm in (nd.binary_closing(darkm, iterations=1), nd.binary_opening(pinkm, iterations=1)):
    ll, nn = nd.label(nd.binary_dilation(mm, iterations=1) & feat)
    l2[ll > 0] = ll[ll > 0] + k_; k_ += nn
blobs = []
for i, sl in enumerate(nd.find_objects(l2)):
    m = (l2[sl] == i + 1) & inner[sl]
    if m.sum() < 30: continue
    px = rgb[sl][m]; lum = (px @ [0.299, 0.587, 0.114]).mean(); pink = (px[:, 0] - px[:, 2]).mean()
    blobs.append(dict(i=i + 1, sl=sl, area=int(m.sum()), lum=float(lum), pink=float(pink), cx=(sl[1].start + sl[1].stop) / 2, cy=(sl[0].start + sl[0].stop) / 2,
                      w=sl[1].stop - sl[1].start, h=sl[0].stop - sl[0].start))
dark = [b for b in blobs if b['lum'] < 110]; pinks = [b for b in blobs if b['lum'] >= 110 and b['pink'] > 15]
eyes = sorted(sorted(dark, key=lambda b: -b['area'])[:2], key=lambda b: b['cx']) if len(dark) >= 2 else dark
mouth = [b for b in dark if b not in eyes]
names = {}
if len(eyes) == 2: names['eye_r'], names['eye_l'] = eyes
elif eyes: names['eye'] = eyes[0]
if mouth: names['mouth'] = max(mouth, key=lambda b: b['area'])
pk = sorted(sorted(pinks, key=lambda b: -b['area'])[:2], key=lambda b: b['cx'])
if len(pk) == 2: names['blush_r'], names['blush_l'] = pk
elif pk: names['blush'] = pk[0]
out = {}
for nm, b in names.items():
    sl = b['sl']; pad = 3
    ys, xs = slice(max(0, sl[0].start - pad), sl[0].stop + pad), slice(max(0, sl[1].start - pad), sl[1].stop + pad)
    c = rgb[ys, xs]; dd = np.sqrt(((c - fill) ** 2).sum(2))
    al = np.clip((dd - a.thr * 0.5) / (a.thr * 0.8), 0, 1) * (l2[ys, xs] == b['i']) * inner[ys, xs]
    if nm.startswith('blush'): al = al * 0.85
    # un-mix the fill colour so the feature composites cleanly on any skin
    col = np.where(al[..., None] > 0.05, (c - fill * (1 - al[..., None])) / np.maximum(al[..., None], 1e-3), c)
    im = Image.fromarray(np.dstack([np.clip(col, 0, 255), al * 255]).astype(np.uint8), 'RGBA')
    im.save(f'{a.out}_{nm}.png')
    out[nm] = [round((x0 + xs.start) / a.ds, 1), round((y0 + ys.start) / a.ds, 1), round((x0 + xs.stop) / a.ds, 1), round((y0 + ys.stop) / a.ds, 1)]
json.dump({'fill_rgb': fill.round().tolist(), 'parts': out}, open(a.out + '_features.json', 'w'), indent=1)
print(json.dumps(out))
