#!/usr/bin/env python3
"""cut_sprites.py: AI sprite/tile sheet -> individual trimmed PNGs + manifest + contact sheet (no painting).
usage: cut_sprites.py config.json        (run from the repo root)
config: source, out_dir, disp_scale (1.25 for 1280x720 sheets read at 1024x576), items[...], recolor{...}
item: {"name", "pick":[x,y]}                one connected component (background removed like cut_partsheet)
      {"name", "rect":[x0,y0,x1,y1]}        every foreground pixel inside the rect (FX frames with loose particles)
      {"name", "tile":[x0,y0,x1,y1]}        opaque square texture crop (largest centred square inside the rect);
            "wrap":"xy"|"x" -> seam test (wrap-edge difference / inner neighbour difference) + a tool-fixed
            <name>_seamless.png (half-offset cross-fade), "size": upscale target (e.g. 512) also written as <name>_<size>.png
      "black": true (rect only) light on black -> alpha from brightness; "max": N downscale to fit N px (never up)
      optional per item: "group", "frame", "nine": true (estimate 9-slice margins), "recolor": name of a recolor op,
            "split_fill": {"fills":{name:[r,g,b]}} (bars: frame with the coloured fill replaced by the charcoal base +
            one fill strip per colour, fill area = the saturated interior)
recolor ops (config "recolor"): {name: {"sat": 0.55, "val": 0.95, "hue_to": [r,g,b]|null, "mix": 0.0..1}}
      sat/val scale HSV saturation/value; hue_to + mix pulls every saturated pixel's colour toward a muted target.
Writes <out_dir>/<group>/<name>.png, <out_dir>/manifest.json (size, source rect, seam scores, 9-slice), contact.png."""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd

def segment(path):
    rgb = np.array(Image.open(path).convert('RGB')).astype(float)
    d = 255 - rgb.min(2)
    fg = nd.binary_fill_holes(nd.binary_closing(d > 24, iterations=2))
    lab, _ = nd.label(fg)
    _, NI = nd.distance_transform_edt(lab == 0, return_indices=True)
    alpha = np.clip((d - 14) * 9, 0, 255) * fg
    alpha = np.maximum(alpha, nd.binary_erosion(fg, iterations=2) * 255.0)
    a = alpha[..., None] / 255.0
    col = np.where(a > 0.05, (rgb - 255 * (1 - a)) / np.maximum(a, 1e-3), rgb)
    return rgb, lab, NI, np.dstack([np.clip(col, 0, 255), alpha])

def soft_alpha(rgb):
    """for loose, semi-transparent FX: alpha straight from distance to the white paper, colour un-premultiplied"""
    d = 255 - rgb.min(2)
    al = np.clip((d - 10) / 90.0, 0, 1)
    a = al[..., None]
    col = np.where(a > 0.03, (rgb - 255 * (1 - a)) / np.maximum(a, 1e-3), rgb)
    return np.dstack([np.clip(col, 0, 255), al * 255])

def rgb2hsv(c):
    c = c / 255.0; mx = c.max(-1); mn = c.min(-1); df = mx - mn + 1e-9
    h = np.where(mx == c[..., 0], ((c[..., 1] - c[..., 2]) / df) % 6, np.where(mx == c[..., 1], (c[..., 2] - c[..., 0]) / df + 2, (c[..., 0] - c[..., 1]) / df + 4)) / 6
    s = np.where(mx > 0, (mx - mn) / (mx + 1e-9), 0); return h, s, mx

def hsv2rgb(h, s, v):
    i = np.floor(h * 6) % 6; f = h * 6 - np.floor(h * 6); p = v * (1 - s); q = v * (1 - f * s); t = v * (1 - (1 - f) * s)
    r = np.choose(i.astype(int), [v, q, p, p, t, v]); g = np.choose(i.astype(int), [t, v, v, q, p, p]); b = np.choose(i.astype(int), [p, p, t, v, v, q])
    return np.stack([r, g, b], -1) * 255

def recolor(px, op):
    out = px.copy(); h, s, v = rgb2hsv(px[..., :3])
    s2 = s * op.get('sat', 1.0); v2 = np.clip(v * op.get('val', 1.0), 0, 1)
    rgb = hsv2rgb(h, s2, v2)
    if op.get('hue_to') is not None:
        tgt = np.array(op['hue_to'], float); th, ts, tv = rgb2hsv(tgt[None, None])
        w = (np.clip((s - 0.25) / 0.3, 0, 1) * op.get('mix', 1.0))[..., None]
        moved = np.clip(tgt[None, None] * (v2 / max(float(tv[0, 0]), 1e-3))[..., None], 0, 255)   # target hue/sat, keep the shading
        rgb = rgb * (1 - w) + moved * w
    out[..., :3] = np.clip(rgb, 0, 255); return out

def seam_score(t, axis):
    t = t[..., :3].astype(float)
    if axis == 'x':
        wrap = np.abs(t[:, -1] - t[:, 0]).mean(); inner = np.abs(np.diff(t, axis=1)).mean()
    else:
        wrap = np.abs(t[-1] - t[0]).mean(); inner = np.abs(np.diff(t, axis=0)).mean()
    return round(float(wrap / max(inner, 1e-6)), 2)

def make_seamless(t, axes):
    t = t.astype(float); H, W = t.shape[:2]; out = t.copy()
    for ax in axes:
        n = W if ax == 'x' else H
        sh = np.roll(out, n // 2, axis=1 if ax == 'x' else 0)
        u = np.abs(np.linspace(-1, 1, n)); w = np.clip((u - 0.55) / 0.4, 0, 1)   # 1 near the wrap edge, 0 in the middle
        w = w[None, :, None] if ax == 'x' else w[:, None, None]
        out = out * (1 - w) + sh * w
    return np.clip(out, 0, 255)

def nine_margins(im):
    """border thickness measured from each edge inward to the flat interior, on the 1/3 and 2/3 lines (the centre
    line has the edge stud), +2px. Corner ornaments larger than this are reported separately."""
    a = np.asarray(im).astype(float); H, W = a.shape[:2]
    lum = a[..., :3] @ [0.299, 0.587, 0.114]; op = a[..., 3] > 200
    ref = np.median(lum[H // 3: 2 * H // 3, W // 3: 2 * W // 3])
    inner = (np.abs(lum - ref) < 18) & op
    inner = nd.binary_opening(inner, iterations=2)
    def first(v):
        idx = np.nonzero(v)[0]; return int(idx[0]) if len(idx) else len(v) // 2
    L_ = max(first(inner[int(H * f), :]) for f in (1 / 3, 2 / 3)); R_ = max(first(inner[int(H * f), ::-1]) for f in (1 / 3, 2 / 3))
    T_ = max(first(inner[:, int(W * f)]) for f in (1 / 3, 2 / 3)); B_ = max(first(inner[::-1, int(W * f)]) for f in (1 / 3, 2 / 3))
    # corner ornament extent: opaque non-interior pixels in each corner box beyond the straight border
    return {'left': L_ + 2, 'right': R_ + 2, 'top': T_ + 2, 'bottom': B_ + 2,
            'note': 'straight-border thickness (+2px) on the 1/3 & 2/3 lines; the stud at each edge midpoint will stretch unless split off'}

def main(cfg):
    c = json.load(open(cfg)); ds = c.get('disp_scale', 1.25); out = c['out_dir']; os.makedirs(out, exist_ok=True)
    rgb, lab, NI, rgba = segment(c['source']); man = {'source': c['source'], 'items': {}}
    R = c.get('recolor', {})
    thumbs = []
    for it in c['items']:
        n = it['name']; g = it.get('group', ''); od = os.path.join(out, g); os.makedirs(od, exist_ok=True); rec = {}
        if 'tile' in it:
            x0, y0, x1, y1 = [int(v * ds) for v in it['tile']]; s = min(x1 - x0, y1 - y0)
            if it.get('wrap') == 'x':
                t = rgb[y0:y1, x0:x1]
            else:
                cx, cy = (x0 + x1) // 2, (y0 + y1) // 2; t = rgb[cy - s // 2: cy - s // 2 + s, cx - s // 2: cx - s // 2 + s]
            px = np.dstack([t, np.full(t.shape[:2], 255.0)])
            if it.get('recolor'): px = recolor(px, R[it['recolor']])
            im = Image.fromarray(px.astype(np.uint8), 'RGBA'); im.save(f'{od}/{n}.png')
            axes = list(it.get('wrap', 'xy'))
            rec['seam_ratio'] = {ax: seam_score(px, ax) for ax in axes}
            rec['seamless_as_cut'] = all(v <= c.get('seam_ok', 1.6) for v in rec['seam_ratio'].values())
            fx = make_seamless(px, axes); Image.fromarray(fx.astype(np.uint8), 'RGBA').save(f'{od}/{n}_seamless.png')
            rec['seam_ratio_after_fix'] = {ax: seam_score(fx, ax) for ax in axes}
            if it.get('size'):
                sz = (it['size'], it['size']) if it.get('wrap', 'xy') == 'xy' else (it['size'], round(it['size'] * fx.shape[0] / fx.shape[1]))
                Image.fromarray(fx.astype(np.uint8), 'RGBA').resize(sz, Image.LANCZOS).save(f'{od}/{n}_seamless_{it["size"]}.png')
                rec['upscale'] = f'{fx.shape[1]}x{fx.shape[0]} -> {sz[0]}x{sz[1]} (source too small for the spec size; soft)'
            # 2x2 tiling preview
            tp = np.tile(px, (2, 2, 1)) if it.get('wrap', 'xy') == 'xy' else np.tile(px, (1, 2, 1))
            tf = np.tile(fx, (2, 2, 1)) if it.get('wrap', 'xy') == 'xy' else np.tile(fx, (1, 2, 1))
            Image.fromarray(np.concatenate([tp, np.full((tp.shape[0], 8, 4), 255.0), tf], 1).astype(np.uint8), 'RGBA').save(f'{od}/{n}_tiling_check.png')
        else:
            if 'pick' in it:
                px_, py_ = [int(v * ds) for v in it['pick']]; i = lab[NI[0][py_, px_], NI[1][py_, px_]]
                sl = nd.find_objects(lab)[i - 1]; m = lab[sl] == i; part = rgba[sl].copy(); part[..., 3] *= m
                rec['rect_src'] = [sl[1].start, sl[0].start, sl[1].stop, sl[0].stop]
            else:
                x0, y0, x1, y1 = [int(v * ds) for v in it['rect']]
                if it.get('black'):   # light on a black background (additive overlays): alpha = brightness
                    t = rgb[y0:y1, x0:x1]; al = np.clip((t.max(2) - 12) / 200.0, 0, 1)
                    col = np.where(al[..., None] > 0.02, t / np.maximum(t.max(2, keepdims=True), 1) * 255, 0)
                    part = np.dstack([col, al * 255])
                else:
                    part = soft_alpha(rgb[y0:y1, x0:x1]) if it.get('soft', True) else rgba[y0:y1, x0:x1].copy()
                rec['rect_src'] = [x0, y0, x1, y1]
            orig = part.copy()
            if it.get('recolor'): part = recolor(part, R[it['recolor']])
            im = Image.fromarray(part.astype(np.uint8), 'RGBA')
            bb = im.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox(); im = im.crop(bb)
            orig = orig[bb[1]:bb[3], bb[0]:bb[2]]
            if it.get('split_fill'):
                a = np.asarray(im).astype(float); h, s, v = rgb2hsv(orig[..., :3])   # fill found on the unrecoloured colours
                fillm = nd.binary_opening((s > 0.35) & (v > 0.25) & (a[..., 3] > 200), iterations=2)
                lab2, n2 = nd.label(fillm); ar = nd.sum(fillm, lab2, range(1, n2 + 1)); keep = [i + 1 for i, v in enumerate(ar) if v >= 0.2 * ar.max()]
                fillm = nd.binary_fill_holes(np.isin(lab2, keep)); fill_raw = fillm.copy()
                fillm = nd.binary_closing(fillm, structure=np.ones((1, 41), bool)) & (a[..., 3] > 200)   # bridge the gap under the centre stud
                fillm = nd.binary_dilation(fillm, iterations=1) & (a[..., 3] > 200)
                base = a.copy(); base[fillm, :3] = np.array(it['split_fill'].get('base_rgb', [34, 32, 30]), float)
                Image.fromarray(base.astype(np.uint8), 'RGBA').save(f'{od}/{n}_frame.png')
                ov = a.copy(); ov[..., 3] = np.where(fillm & ~nd.binary_erosion(~fill_raw, iterations=0 or 1) & fill_raw, 0, ov[..., 3])
                ov[..., 3] = np.where(fillm & fill_raw, 0, a[..., 3])          # overlay = frame with the fill area cut out, centre stud kept
                Image.fromarray(ov.astype(np.uint8), 'RGBA').save(f'{od}/{n}_overlay.png')
                rec['draw_order'] = f'{n}_frame (charcoal base) -> fill (scaled/clipped in x) -> {n}_overlay (rim + centre stud)'
                ys, xs = np.nonzero(fillm); y0f, y1f, x0f, x1f = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
                fl = a[y0f:y1f, x0f:x1f].copy(); fl[..., 3] *= fillm[y0f:y1f, x0f:x1f]
                lum = (fl[..., :3] @ [0.299, 0.587, 0.114]) / 255.0
                rec['fills'] = {}
                for fn, col in it['split_fill']['fills'].items():
                    f2 = fl.copy(); shade = (0.75 + 0.5 * (lum - lum[fillm[y0f:y1f, x0f:x1f]].mean()))[..., None]
                    f2[..., :3] = np.clip(np.array(col, float) * shade, 0, 255)
                    Image.fromarray(f2.astype(np.uint8), 'RGBA').save(f'{od}/{fn}.png'); rec['fills'][fn] = '#%02X%02X%02X' % tuple(col)
                rec['fill_rect_in_frame'] = [int(x0f), int(y0f), int(x1f), int(y1f)]
                rec['nine'] = {'left': int(x0f) + 2, 'right': int(a.shape[1] - x1f) + 2, 'top': int(y0f), 'bottom': int(a.shape[0] - y1f),
                               'note': 'frame: stretch only the straight middle; the centre stud (diamond) must be a separate overlay or it stretches'}
            if it.get('max'):     # downscale only, to fit the spec box
                k = min(1.0, it['max'] / max(im.size))
                if k < 1: im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS); rec['scale'] = round(k, 3)
            im.save(f'{od}/{n}.png')
            if it.get('nine'): rec['nine'] = nine_margins(im)
        rec['size'] = list(Image.open(f'{od}/{n}.png').size); rec['file'] = os.path.join(g, n + '.png')
        for k in ('frame', 'spec', 'note', 'recolor'):
            if it.get(k) is not None: rec[k] = it[k]
        man['items'][n] = rec; thumbs.append((n, f'{od}/{n}.png'))
    json.dump(man, open(f'{out}/manifest.json', 'w'), ensure_ascii=False, indent=1)
    # contact sheet
    cell = 150; cols = 8; rows = (len(thumbs) + cols - 1) // cols
    sh = Image.new('RGBA', (cols * cell, rows * (cell + 14)), (90, 90, 90, 255)); d = ImageDraw.Draw(sh)
    for i, (n, p) in enumerate(thumbs):
        im = Image.open(p).convert('RGBA'); im.thumbnail((cell - 6, cell - 6)); x = (i % cols) * cell; y = (i // cols) * (cell + 14)
        sh.alpha_composite(im, (x + 3, y + 3)); d.text((x + 2, y + cell), n[:24], fill=(255, 255, 255, 255))
    sh.save(f'{out}/contact.png'); print(out, len(thumbs), 'items')

if __name__ == '__main__':
    main(sys.argv[1])
