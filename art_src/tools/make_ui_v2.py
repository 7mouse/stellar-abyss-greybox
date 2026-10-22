#!/usr/bin/env python3
"""make_ui_v2.py: thin-border HUD / menu set from AI UI sheets, by tool only.
Every frame is rebuilt 9-slice-safe: the 4 corners are the AI pixels as cut; each edge is ONE slice of the AI edge
(the middle column/row) repeated, and the centre is one flat colour, so stretching never smears an ornament.
Margins = how far the corner differs from that middle slice (+2 px). Panel interiors get the charcoal at 85% alpha
(ui_style_v1: 炭黑半透明底板). Bars: frame (charcoal + thin line) under a fill strip clipped in x.
usage: make_ui_v2.py config.json"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd
sys.path.insert(0, os.path.dirname(__file__))
from cut_sprites import segment, rgb2hsv

_cache = {}
def sheet(p):
    if p not in _cache: _cache[p] = segment(p)
    return _cache[p]

def pick(src, xy, ds=1.25):
    rgb, lab, NI, rgba = sheet(src); x, y = int(xy[0] * ds), int(xy[1] * ds)
    i = lab[NI[0][y, x], NI[1][y, x]]; sl = nd.find_objects(lab)[i - 1]
    part = rgba[sl].copy(); part[..., 3] *= (lab[sl] == i); return part

def rect(src, r, ds=1.25):
    rgb, lab, NI, rgba = sheet(src); x0, y0, x1, y1 = [int(v * ds) for v in r]
    p = rgba[y0:y1, x0:x1].copy(); ys, xs = np.nonzero(p[..., 3] > 8)
    return p[ys.min():ys.max() + 1, xs.min():xs.max() + 1]

def rs(a, k=None, size=None):
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA')
    size = size or (max(1, round(im.width * k)), max(1, round(im.height * k)))
    return np.asarray(im.resize(size, Image.LANCZOS)).astype(float)

def margins(a, thr=10.0):
    H, W = a.shape[:2]; cx, cy = W // 2, H // 2
    dc = np.abs(a - a[:, cx:cx + 1]).mean((0, 2)); dr = np.abs(a - a[cy:cy + 1]).mean((1, 2))
    def ext(d, n):
        idx = np.nonzero(d[: n // 2] > thr)[0]; return int(idx.max()) + 1 if len(idx) else 1
    return {'left': ext(dc, W) + 2, 'right': ext(dc[::-1], W) + 2, 'top': ext(dr, H) + 2, 'bottom': ext(dr[::-1], H) + 2}

def paper_map(h, w, seed=3):
    """hand-made-paper grain, periodic on (h, w) by construction (FFT-filtered noise), mean 0, ~unit range.
    blotches (low frequency) + fibre grain (high frequency, slightly stretched in x)."""
    r = np.random.default_rng(seed); fy = np.fft.fftfreq(h)[:, None]; fx = np.fft.fftfreq(w)[None, :]
    def band(f0, sx=1.0):
        f = np.sqrt((fx * sx) ** 2 + fy ** 2) + 1e-6; n = np.fft.fft2(r.standard_normal((h, w)))
        g = np.real(np.fft.ifft2(n * np.exp(-(f / f0) ** 2))); return g / (g.std() + 1e-9)
    return 0.7 * band(0.02) + 0.45 * band(0.25, 0.35)

def add_paper(o, y0, y1, x0, x1, k=0.05, seed=3):
    """multiply the region by (1 + k * paper), plus a faint warm tint; the map is periodic on the region size"""
    if y1 - y0 < 2 or x1 - x0 < 2: return o
    pm = paper_map(y1 - y0, x1 - x0, seed)[..., None]
    reg = o[y0:y1, x0:x1, :3] * (1 + k * pm) + np.array([2.5, 1.5, 0]) ; o[y0:y1, x0:x1, :3] = np.clip(reg, 0, 255); return o

def nine(a, tw, th, m=None, fill_alpha=None, tile_center=False, paper=0.0):
    """tile_center: the centre is tiled from the source centre (for pieces whose centre carries the paper grain)"""
    H, W = a.shape[:2]; m = m or margins(a); L, R, T, B = m['left'], m['right'], m['top'], m['bottom']
    cx, cy = W // 2, H // 2; o = np.zeros((th, tw, 4))
    o[:T, :L] = a[:T, :L]; o[:T, tw - R:] = a[:T, W - R:]; o[th - B:, :L] = a[H - B:, :L]; o[th - B:, tw - R:] = a[H - B:, W - R:]
    o[:T, L:tw - R] = a[:T, cx:cx + 1]; o[th - B:, L:tw - R] = a[H - B:, cx:cx + 1]
    o[T:th - B, :L] = a[cy:cy + 1, :L]; o[T:th - B, tw - R:] = a[cy:cy + 1, W - R:]
    centre = np.median(a[T:H - B, L:W - R].reshape(-1, 4), 0)
    if tile_center:
        c = a[T:H - B, L:W - R]; ch, cw = th - T - B, tw - L - R
        o[T:th - B, L:tw - R] = np.tile(c, (ch // c.shape[0] + 1, cw // c.shape[1] + 1, 1))[:ch, :cw]
    else:
        o[T:th - B, L:tw - R] = centre
        if paper: o = add_paper(o, T, th - B, L, tw - R, paper)
    if fill_alpha is not None:   # the charcoal interior (anything close to the centre colour, inside the line) goes translucent
        close = (np.abs(o[..., :3] - centre[:3]).sum(-1) < 60) & (o[..., 3] > 200)
        inner = np.zeros((th, tw), bool); inner[2:-2, 2:-2] = True
        o[..., 3] = np.where(close & inner, 255 * fill_alpha, o[..., 3])
    return o, m

def save(a, p):
    os.makedirs(os.path.dirname(p), exist_ok=True); Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA').save(p)

def hexrgb(h): h = h.lstrip('#'); return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)

def tint_line(a, col, light=150):
    """recolour the light line pixels (the off-white border) to col, keeping their shading"""
    o = a.copy(); lum = a[..., :3] @ [0.299, 0.587, 0.114]; w = np.clip((lum - 70) / (light - 70), 0, 1)[..., None]
    o[..., :3] = a[..., :3] * (1 - w) + (col * np.clip(lum / 235, 0.6, 1.1)[..., None]) * w; return o

def main(cfgp):
    c = json.load(open(cfgp)); out = c['out']; man = {}
    for it in c['items']:
        n = it['name']; src = it['src']; rec = {'spec': it.get('spec', ''), 'src': src}
        a = pick(src, it['pick']) if 'pick' in it else rect(src, it['rect'])
        if it.get('fit_h'): a = rs(a, it['fit_h'] / a.shape[0])
        if it.get('fit'): a = rs(a, it['fit'] / max(a.shape[:2]))
        kind = it.get('kind', 'fixed')
        if kind == 'nine':
            tw, th = it.get('size', [a.shape[1], a.shape[0]])
            o, m = nine(a, tw, th, it.get('margins'), it.get('fill_alpha', 0.85), paper=it.get('paper', c.get('paper', 0.0))); rec['nine'] = m
            if it.get('paper', c.get('paper', 0.0)): rec['paper'] = 'centre fill carries the paper grain, periodic on the centre size: use TILE (or stretch) for the centre'
            if it.get('tints'):
                base = o
                for tn, col in it['tints'].items():
                    save(tint_line(base, hexrgb(col)), f"{out}/{it.get('group','')}/{n}_{tn}.png")
                rec['tints'] = it['tints']
            if it.get('keep_feature'):   # e.g. the card's emblem circle: cut from the source, put back at the same relative spot
                fx0, fy0, fx1, fy1 = it['keep_feature']; H, W = a.shape[:2]
                f = a[int(fy0 * H):int(fy1 * H), int(fx0 * W):int(fx1 * W)].copy()
                k = it.get('feature_scale', 1.0); f = rs(f, k) if k != 1 else f
                X = int((fx0 + fx1) / 2 * tw - f.shape[1] / 2); Y = int(fy0 * H * it.get('feature_y_scale', 1.0))
                im = Image.fromarray(np.clip(o, 0, 255).astype(np.uint8), 'RGBA'); im.alpha_composite(Image.fromarray(np.clip(f, 0, 255).astype(np.uint8), 'RGBA'), (X, Y))
                o = np.asarray(im).astype(float); rec['feature_at'] = [X, Y, f.shape[1], f.shape[0]]
            a = o
        elif kind == 'fill':   # vertical profile of the AI fill, repeated in x -> recoloured strips
            rgbp = a[..., :3]; h, s, v = rgb2hsv(rgbp); m = (s > 0.3) & (a[..., 3] > 200)
            ys, xs = np.nonzero(m); y0, y1 = ys.min(), ys.max() + 1
            rows = [y for y in range(y0, y1) if m[y].sum() > 0.5 * m.sum(1).max()]   # full-width fill rows only
            prof = np.array([rgbp[y][m[y]].mean(0) for y in rows])
            lum = prof @ [0.299, 0.587, 0.114]; shade = lum / lum.mean()
            hh = it.get('height', y1 - y0); shade = np.interp(np.linspace(0, len(shade) - 1, hh), np.arange(len(shade)), shade)
            rec['fills'] = {}
            for fn, col in it['fills'].items():
                st = np.zeros((hh, it.get('width', 8), 4)); st[..., :3] = np.clip(hexrgb(col) * shade[:, None, None], 0, 255); st[..., 3] = 255
                save(st, f"{out}/{it.get('group','')}/{fn}.png"); rec['fills'][fn] = col
            man[n] = rec; continue
        if it.get('size') and kind == 'fixed': a = rs(a, size=tuple(it['size']))
        if kind == 'fixed' and (it.get('fill_alpha') is not None or it.get('hollow')):
            H, W = a.shape[:2]; lum = a[..., :3] @ [0.299, 0.587, 0.114]; dark = (lum < 75) & (a[..., 3] > 200)
            yy, xx = np.mgrid[0:H, 0:W]; r = np.hypot(yy - (H - 1) / 2, xx - (W - 1) / 2) / (min(H, W) / 2)
            inner = r < 0.9
            if it.get('hollow'):   # the portrait / minimap shows through: charcoal inside the inner line is cut out
                a[..., 3] = np.where(dark & (r < it['hollow']), 0, a[..., 3])
            if it.get('fill_alpha') is not None:
                a[..., 3] = np.where(dark & inner & (a[..., 3] > 0), a[..., 3] * it['fill_alpha'], a[..., 3])
        if kind == 'fixed' and c.get('paper') and it.get('paper', True) and it.get('group') != 'hud_icons':
            H, W = a.shape[:2]; lum = a[..., :3] @ [0.299, 0.587, 0.114]; dk = ((lum < 75) & (a[..., 3] > 0))[..., None]
            pm = paper_map(H, W, 5)[..., None]; a[..., :3] = np.where(dk, np.clip(a[..., :3] * (1 + c['paper'] * pm) + [2.5, 1.5, 0], 0, 255), a[..., :3])
        if it.get('inset_png'):   # e.g. the boss head inside the emblem ring
            ip = Image.open(it['inset_png']).convert('RGBA'); ip.thumbnail(tuple(it['inset_box'][2:]), Image.LANCZOS)
            im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA'); X, Y = it['inset_box'][:2]
            lay = Image.new('RGBA', im.size); lay.alpha_composite(ip, (X + (it['inset_box'][2] - ip.width) // 2, Y + (it['inset_box'][3] - ip.height) // 2))
            circ = Image.new('L', im.size, 0); ImageDraw.Draw(circ).ellipse([X, Y, X + it['inset_box'][2], Y + it['inset_box'][3]], fill=255)
            lay.putalpha(Image.fromarray(np.minimum(np.asarray(lay.getchannel('A')), np.asarray(circ))))
            im.alpha_composite(lay); a = np.asarray(im).astype(float)
        p = f"{out}/{it.get('group','')}/{n}.png"; save(a, p); rec['size'] = [a.shape[1], a.shape[0]]; man[n] = rec
    if c.get('paper'):   # engine-side alternative: one tileable grain overlay (multiply / overlay blend, clipped to the panel)
        pm = paper_map(256, 256, 3); g = np.clip(128 + 128 * c['paper'] * 2.5 * pm, 0, 255)
        save(np.dstack([g, g, g, np.full_like(g, 255)]), f"{out}/panels/ui_paper_grain_tile_256.png")
    json.dump(man, open(f"{out}/manifest_v2.json", 'w'), ensure_ascii=False, indent=1)
    for k, v in man.items(): print(k, v.get('size'), v.get('nine', ''))

if __name__ == '__main__':
    main(sys.argv[1])
