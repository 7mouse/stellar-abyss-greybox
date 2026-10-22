#!/usr/bin/env python3
"""Seamless terrain tiles / edge overlays from AI ground images, by tool only (no painting).

Tiles: the whole 1024 image is downscaled to N+ov (576 for N=512, never upscaled), then wrapped with a
min-error boundary cut (image quilting): the ov px that run past the right/bottom edge are stitched onto the
left/top along the cheapest path through |A-B|, feathered 2 px. No cross-fade, so no ghosting.
Edges: an AI image with material A on top and B below; the A fringe becomes an alpha overlay strip (A pixels by
colour classification, fading into the A tile above), wrapped in x the same way. Corners are polar warps of the
straight strip (outer: A inside a rounded quarter, inner: the reverse).
Usage: make_tiles.py config.json
"""
import json, sys, os
import numpy as np
from PIL import Image
from scipy import ndimage

def seam_score(t, axis):
    t = t[..., :3].astype(float)
    if axis == 'x':
        wrap = np.abs(t[:, -1] - t[:, 0]).mean(); inner = np.abs(np.diff(t, axis=1)).mean()
    else:
        wrap = np.abs(t[-1] - t[0]).mean(); inner = np.abs(np.diff(t, axis=0)).mean()
    return round(float(wrap / max(inner, 1e-6)), 2)

def min_cut(err):
    """err: H x ov. Returns per-row column index of the cut (cheapest top-to-bottom path)."""
    H, W = err.shape; E = err.copy(); back = np.zeros((H, W), int)
    for i in range(1, H):
        prev = np.pad(E[i - 1], 1, constant_values=np.inf)
        cand = np.stack([prev[:-2], prev[1:-1], prev[2:]]); k = cand.argmin(0)
        E[i] += cand[k, np.arange(W)]; back[i] = np.arange(W) + k - 1
    path = np.zeros(H, int); path[-1] = E[-1].argmin()
    for i in range(H - 1, 0, -1): path[i - 1] = back[i, path[i]]
    return path

def wrap_x(img, n, feather=2):
    """img: H x (n+ov) x C float -> H x n x C, seamless in x."""
    ov = img.shape[1] - n; A = img[:, n:]; B = img[:, :ov]
    err = ((A[..., :3] - B[..., :3]) ** 2).sum(-1)
    if img.shape[2] == 4: err += ((A[..., 3] - B[..., 3]) ** 2) * 3
    path = min_cut(err)
    cols = np.arange(ov)[None, :]
    w = np.clip((cols - path[:, None]) / (2 * feather) + 0.5, 0, 1)   # 0 = take A (left of cut), 1 = take B
    out = img[:, :n].copy(); out[:, :ov] = A * (1 - w[..., None]) + B * w[..., None]
    return out, int(err[np.arange(len(path)), path].mean())

def tile(src, n=512, ov=64, desat=1.0, axes='xy', val=1.0):
    im = Image.open(src).convert('RGB')
    s = n + ov; im = im.resize((s, s), Image.LANCZOS)
    a = np.asarray(im).astype(float)
    if desat != 1.0:
        g = a @ [0.299, 0.587, 0.114]; a = g[..., None] + (a - g[..., None]) * desat
    a = a * val
    cost = {}
    if 'x' in axes: a, cost['x'] = wrap_x(a, n)
    if 'y' in axes:
        t, cost['y'] = wrap_x(a.transpose(1, 0, 2), n); a = t.transpose(1, 0, 2)
    return np.clip(a, 0, 255), cost

def h_cut(err):
    """cheapest left-to-right path through err (H x W) -> row index per column"""
    return min_cut(err.T)

def variant(A, B, band=(40, 104), feather=2):
    """Wang-style variant: keeps A's outer ring (so any mix of A and its variants tiles seamlessly, no rotation),
    swaps the interior for B along min-error cuts in a band 40..104 px from each edge (no cross-fade)."""
    n = A.shape[0]; b0, b1 = band; e = ((A[..., :3] - B[..., :3]) ** 2).sum(-1)
    yy, xx = np.mgrid[0:n, 0:n].astype(float); w = np.ones((n, n))
    top = b0 + h_cut(e[b0:b1]); w = np.minimum(w, np.clip((yy - top[None, :]) / (2 * feather) + 0.5, 0, 1))
    bot = b0 + h_cut(e[n - b1:n - b0][::-1]); w = np.minimum(w, np.clip(((n - 1 - yy) - bot[None, :]) / (2 * feather) + 0.5, 0, 1))
    lef = b0 + min_cut(e[:, b0:b1]); w = np.minimum(w, np.clip((xx - lef[:, None]) / (2 * feather) + 0.5, 0, 1))
    rig = b0 + min_cut(e[:, n - b1:n - b0][:, ::-1]); w = np.minimum(w, np.clip(((n - 1 - xx) - rig[:, None]) / (2 * feather) + 0.5, 0, 1))
    return A * (1 - w[..., None]) + B * w[..., None]

def green_mask(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return ((g > r * 1.04) & (g > b * 1.15)).astype(float)

def edge_strip(src, n=512, ov=64, h=128, boundary=None, fade=48, scale_to=576, desat=1.0, flip=False, val=1.0):
    """flip: the source has A (the overlay material) at the bottom; it is flipped so A is on top, and A = not-green."""
    im = Image.open(src).convert('RGB').resize((scale_to, scale_to), Image.LANCZOS)
    a = np.asarray(im).astype(float); H = a.shape[0]
    if desat != 1.0:
        gg = a @ [0.299, 0.587, 0.114]; a = gg[..., None] + (a - gg[..., None]) * desat
    a = a * val
    if flip: a = a[::-1].copy()
    amask = (lambda x: 1 - green_mask(x)) if flip else green_mask
    g = ndimage.uniform_filter(amask(a), 5)
    if boundary is None:   # the tile line goes where the A cover starts to break up (90% of its plateau), so the
        # whole fringe (grass tufts, scattered leaves) spills over the B tile below the line
        prof = ndimage.uniform_filter1d(g.mean(1), 9)
        b50 = H // 3 + int(np.argmax(prof[H // 3:] < 0.5 * prof[:H // 3].mean()))   # where A has mostly ended
        boundary = b50 - 22
    top = boundary - (h - 40)                  # 88 px of A above the line, 40 below for the fringe
    band = a[top:top + h]
    raw = amask(band) > 0.5
    dark = (band @ [0.299, 0.587, 0.114]) < 70        # outlines of the grass tufts count as A when touching A
    raw = raw | (dark & ndimage.binary_dilation(raw, iterations=2))
    m = ndimage.binary_closing(raw, iterations=1)
    m = ndimage.binary_opening(m, iterations=1).astype(float)
    m = ndimage.gaussian_filter(m, 0.8)
    ramp = np.clip(np.arange(h) / fade, 0, 1)[:, None]      # fades into the A tile above
    m[: h - 40] = np.maximum(m[: h - 40], 0)                 # keep
    alpha = np.minimum(m, ramp) * 255
    rgba = np.dstack([band, alpha])
    out, cost = wrap_x(rgba, n)
    return np.clip(out, 0, 255), boundary, cost

def corner(strip, size=128, R=40, inner=False, line=88):
    """polar-warp the straight strip around a corner. outer: A occupies x<c, y<c with a rounded corner."""
    h, w = strip.shape[:2]; c = size // 2; P = c - R
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    if not inner:
        d = np.where((xx > P) & (yy > P), np.hypot(xx - P, yy - P) - R, np.where(xx <= P, yy - c, xx - c))
        d = np.where((xx > P) & (yy <= P), xx - c, d)
        ang = np.arctan2(yy - P, xx - P)            # 0 (pointing +x) .. pi/2 (+y)
        u = np.where((xx > P) & (yy > P), P + R * (np.pi / 2 - ang), np.where(xx <= P, xx, P + R * np.pi / 2 + (P - yy)))
    else:   # A everywhere except the quadrant x>c, y>c (concave)
        Q = c + R
        d = np.where((xx < Q) & (yy < Q), R - np.hypot(Q - xx, Q - yy), np.where(xx >= Q, c - yy, c - xx))
        d = np.where((xx < Q) & (yy >= Q), c - xx, d)
        d = -d
        ang = np.arctan2(Q - yy, Q - xx)
        u = np.where((xx < Q) & (yy < Q), Q + R * ang, np.where(xx >= Q, xx, Q + R * np.pi / 2 + (yy - Q)))
        d = np.where((xx >= Q) | (yy >= Q), np.where(xx >= Q, yy - c, xx - c), d)
    rows = np.clip(line + d, 0, h - 1); cols = np.mod(u, w)
    out = np.stack([ndimage.map_coordinates(strip[..., k], [rows, cols], order=1, mode='nearest') for k in range(4)], -1)
    return np.clip(out, 0, 255)

def save(a, p):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    Image.fromarray(a.astype(np.uint8), 'RGBA' if a.shape[2] == 4 else 'RGB').save(p)

def tiling_check(a, p, k=3):
    big = np.tile(a, (k, k, 1)) if a.shape[2] == 3 else np.tile(a, (1, k, 1))
    im = Image.fromarray(big.astype(np.uint8)); im = im.resize((im.width // 2, im.height // 2), Image.LANCZOS); im.save(p)

def main(cfg_path):
    cfg = json.load(open(cfg_path)); out = cfg['out']; man = {}
    for t in cfg.get('tiles', []):
        a, cost = tile(t['src'], cfg.get('n', 512), cfg.get('ov', 64), t.get('desat', 1.0), val=t.get('val', 1.0))
        p = f"{out}/tiles/{t['name']}.png"; save(a, p); tiling_check(a, f"{out}/tiles/{t['name']}_tiling_check.png")
        man[t['name']] = {'file': p, 'size': [a.shape[1], a.shape[0]], 'src': t['src'], 'seam_ratio': {'x': seam_score(a, 'x'), 'y': seam_score(a, 'y')}, 'cut_cost': cost}
    tiles = {t['name']: np.asarray(Image.open(f"{out}/tiles/{t['name']}.png").convert('RGB')).astype(float) for t in cfg.get('tiles', [])}
    for v in cfg.get('variants', []):
        A = tiles[v['base']]; B = np.roll(A, (A.shape[0] // 2, A.shape[1] // 2), (0, 1)) if v['interior'] == 'roll' else tiles[v['interior']]
        o = variant(A, B); p = f"{out}/tiles/{v['name']}.png"; save(o, p); tiling_check(o, f"{out}/tiles/{v['name']}_tiling_check.png")
        man[v['name']] = {'file': p, 'size': [512, 512], 'variant_of': v['base'], 'interior': v['interior'], 'seam_ratio': {'x': seam_score(o, 'x'), 'y': seam_score(o, 'y')},
                          'use': f"same outer ring as {v['base']}: mix freely with it (no rotation/flip)"}
    for e in cfg.get('edges', []):
        s, b, cost = edge_strip(e['src'], boundary=e.get('boundary'), desat=e.get('desat', 1.0), flip=e.get('flip', False), val=e.get('val', 1.0))
        p = f"{out}/edges/{e['name']}.png"; save(s, p)
        rec = {'file': p, 'size': [s.shape[1], s.shape[0]], 'src': e['src'], 'boundary_row_576': b, 'seam_ratio': {'x': seam_score(s, 'x')}, 'line_row': 88,
               'use': f"alpha overlay; the tile boundary sits on row 88; {e.get('top','A')} tile above, {e.get('bottom','B')} tile below"}
        man[e['name']] = rec
        for kind in ('outer', 'inner'):
            c = corner(s, inner=(kind == 'inner')); pc = f"{out}/edges/{e['name']}_corner_{kind}.png"; save(c, pc)
            man[f"{e['name']}_corner_{kind}"] = {'file': pc, 'size': [128, 128], 'from': p, 'use': 'tile corner at the centre (64,64); outer = A in the top-left quadrant, inner = A everywhere but bottom-right'}
        tiling_check(s, f"{out}/edges/{e['name']}_tiling_check.png")
    json.dump(man, open(f"{out}/manifest_tiles.json", 'w'), ensure_ascii=False, indent=1)
    for k, v in man.items():
        if 'seam_ratio' in v: print(k, v['seam_ratio'])

if __name__ == '__main__':
    main(sys.argv[1])
