#!/usr/bin/env python3
"""style_fix_v3.py: 2026-10-21e tool-only style fixes on cut assets (no painting).
  decals: pulled toward the moss ground (colour = moss tile mean x the decal's own shading, sat x0.6, darker),
          alpha re-made as a soft irregular edge: distance-to-edge ramp (22 px) + low-frequency noise, max 0.8,
          so the pale rim of the AI cut fades out (no sticker edge).
  light:  cooler tint (less yellow), alpha blurred 4 px.
usage: style_fix_v3.py   (run from the repo root; paths fixed below)"""
import glob, os
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as nd

T = 'art_src/terrain/floor1_v2/'
rng = np.random.default_rng(7)
def lowfreq_noise(h, w, scale=24):
    n = rng.random((h // scale + 3, w // scale + 3))
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w + 2 * scale, h + 2 * scale), Image.BICUBIC)).astype(float) / 255
    return n[scale:scale + h, scale:scale + w]
moss = np.asarray(Image.open(T + 'tiles/s01_ground_moss.png').convert('RGB')).astype(float).reshape(-1, 3).mean(0)
os.makedirs(T + 'decals_v3', exist_ok=True)
for p in sorted(glob.glob(T + 'props_bushes_decals/s07_moss_decal_*.png')):
    a = np.asarray(Image.open(p).convert('RGBA')).astype(float); rgb = a[..., :3]; al = a[..., 3] / 255
    pad = 24; a2 = np.pad(a, ((pad, pad), (pad, pad), (0, 0))); rgb = a2[..., :3]; al = a2[..., 3] / 255
    lum = rgb @ [0.299, 0.587, 0.114]; inside = al > 0.5
    shade = lum / max(lum[inside].mean(), 1)
    col = moss[None, None] * (0.86 + 0.5 * (shade[..., None] - 1)) * 0.95        # moss tile colour, decal's own light/dark
    g = col @ [0.299, 0.587, 0.114]; col = g[..., None] + (col - g[..., None]) * 0.75
    dist = nd.distance_transform_edt(inside)
    ramp = np.clip(dist / 22.0, 0, 1)
    nz = lowfreq_noise(*al.shape)
    alpha = np.clip(ramp * 1.35 - nz * 0.5, 0, 1) * 0.8          # 0 outside the shape, noisy soft edge inside
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))).astype(float)
    out = np.dstack([np.clip(col, 0, 255), alpha])
    Image.fromarray(out.astype(np.uint8), 'RGBA').save(T + 'decals_v3/' + os.path.basename(p))
os.makedirs(T + 'light_v3', exist_ok=True)
cool = np.array([236, 240, 222], float)
for p in sorted(glob.glob(T + 'light/s09_leaf_light_*.png')):
    im = Image.open(p).convert('RGBA'); pad = 16
    cv = Image.new('RGBA', (im.width + 2 * pad, im.height + 2 * pad)); cv.paste(im, (pad, pad))
    a = np.asarray(cv).astype(float); al = np.asarray(cv.getchannel('A').filter(ImageFilter.GaussianBlur(4))).astype(float) * 0.9
    lum = a[..., :3].max(2) / 255
    col = cool[None, None] * (0.85 + 0.15 * lum[..., None])
    Image.fromarray(np.dstack([np.clip(col, 0, 255), al]).astype(np.uint8), 'RGBA').save(T + 'light_v3/' + os.path.basename(p))
# U16 defringe: the gen2 icons were cut off a white sheet, so the 1-2 px anti-aliased rim is white-ish.
# Erode alpha by 1 px and pull the remaining partial pixels toward the dark outline colour.
U = 'art_src/ui/hud_v2/icons_u16/'
for p in sorted(glob.glob(U + 'u16_*.png')):
    im = Image.open(p).convert('RGBA')
    if im.info.get('defringed'): continue
    a = np.asarray(im).astype(float)
    al = np.asarray(im.getchannel('A').filter(ImageFilter.MinFilter(3))).astype(float)
    edge = (al > 0) & (al < 250)
    rgb = a[..., :3]; dark = np.array([46, 38, 32], float)
    t = (1 - al / 255.0)[..., None] * edge[..., None]
    rgb = rgb * (1 - t) + dark * t
    out = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), al]).astype(np.uint8), 'RGBA')
    out.thumbnail((116, 116), Image.LANCZOS)                      # square 128 slot with 6 px margin, centred
    sq = Image.new('RGBA', (128, 128)); sq.paste(out, ((128 - out.width) // 2, (128 - out.height) // 2)); out = sq
    from PIL import PngImagePlugin; meta = PngImagePlugin.PngInfo(); meta.add_text('defringed', '1')
    out.save(p, pnginfo=meta)
import json
mf = U + 'manifest.json'
if os.path.exists(mf):
    m = json.load(open(mf))
    for v in m['items'].values(): v['size'] = [128, 128]; v['post'] = 'style_fix_v3: 1 px alpha erode + rim pulled to outline colour, fit 116 centred on 128'
    json.dump(m, open(mf, 'w'), indent=1, ensure_ascii=False)
print('ok')
