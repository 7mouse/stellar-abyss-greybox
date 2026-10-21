#!/usr/bin/env python3
"""rig_extras.py: add tool-derived layers to an existing rig version -> next version (no re-generation, no painting).
usage: rig_extras.py extras.json [more.json ...]   (run from the repo root)
config: src_psd2x, src_pivots, out_dir, base, parts_dir, scale (2), line_rgb (optional), ops[...]
ops (coords at 1:1):
  {"op":"dup_layer","src":"ear_s","name":"ear_far_s","d":[dx,dy],"below":"head_s","mul":0.85,"pivot_from":"ear_root","pivot":"ear_far_root"}
      copy a part (e.g. far ear), shift it, darken by `mul` (far-side shade), insert below a layer
  {"op":"blink","head":"head_f","eyes":[{"side":"r","ellipse":[cx,cy,rx,ry]}|{"side":"r","auto":[x0,y0,x1,y1]}],
       "suffix":"f","lid":"down"|"up","closed_only":false}
      closed_only + per-eye "open_layer": eyes that already are separate parts (slime, mushroom): only the closed swap is
      added, skin sampled from "head" (the body/stalk under the eye)
      eye_open_<side>_<suffix>: the head's own pixels inside the eye ellipse (visible, sits on the head)
      eye_closed_<side>_<suffix>: ellipse filled with the skin colour sampled around the eye (median of a ring, line
      pixels excluded) + one lid line in the outline colour (saved hidden = swap layer). "auto" finds the darkest
      blob (pupil) inside the box and fits the ellipse around it.
  {"op":"expr","head":"head_f","suffix":"f","eyes":[...same ellipses...],"brow":[...] }  -> see make_expressions in docs
  {"op":"open_white","part":"tail_s"}   re-open an enclosed white hole (tail loop)
  {"op":"empty","name":"eye_open_r_b","above":"head_b"}   structural empty layer (spec §11: allowed, skipped on import)
Swap layers are saved hidden; rig_patch.HIDDEN keeps them out of previews / cap covers / rig_check."""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as nd
from psd_tools import PSDImage
from psd_tools.api.layers import PixelLayer
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rig_joints as RJ
from rig_patch import load_psd, HIDDEN, compose, pivot_layer

def ellipse_mask(shape, cx, cy, rx, ry, soft=1.0):
    Y, X = np.mgrid[0:shape[0], 0:shape[1]].astype(np.float32) + 0.5
    r = np.sqrt(((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2)
    return np.clip((1 - r) * min(rx, ry) / soft + 0.5, 0, 1)

def auto_eye(head, box, S):
    x0, y0, x1, y1 = [int(v * S) for v in box]
    sub = head[y0:y1, x0:x1]; lum = sub[..., :3] @ [0.299, 0.587, 0.114]
    dk = (lum < 0.22) & (sub[..., 3] > 0.5)
    lab, n = nd.label(nd.binary_closing(dk, iterations=1))
    assert n, ('no dark blob in', box)
    i = np.argmax(nd.sum(dk, lab, range(1, n + 1))) + 1
    ys, xs = np.nonzero(lab == i)
    cx, cy = (xs.min() + xs.max() + 1) / 2 + x0, (ys.min() + ys.max() + 1) / 2 + y0
    rx, ry = (xs.max() - xs.min() + 1) / 2 + 1.2 * S, (ys.max() - ys.min() + 1) / 2 + 1.2 * S
    return [cx / S, cy / S, rx / S, ry / S]

def skin_color(head, cx, cy, rx, ry):
    m_out = ellipse_mask(head.shape[:2], cx, cy, rx * 1.9, ry * 1.6) > 0.5
    m_in = ellipse_mask(head.shape[:2], cx, cy, rx * 1.2, ry * 1.2) > 0.5
    ring = m_out & ~m_in & (head[..., 3] > 0.9)
    px = head[ring][:, :3]; lum = px @ [0.299, 0.587, 0.114]
    px = px[lum >= np.percentile(lum, 50)]          # skin is the light half of the ring (no hair / lines / brows)
    return np.median(px, 0)


# ---------------------------------------------------------------- v4 (2026-10-21f): parts from new AI sheets
_SEG = {}
def sheet_rgba(path):
    """white-paper sheet -> (labels, nearest-label index, un-premultiplied RGBA float 0..1), same rules as cut_partsheet"""
    if path in _SEG: return _SEG[path]
    rgb = np.array(Image.open(path).convert('RGB')).astype(float)
    d = 255 - rgb.min(2)
    fg = nd.binary_fill_holes(nd.binary_closing(d > 28, iterations=2))
    lab, _ = nd.label(fg)
    _, NI = nd.distance_transform_edt(lab == 0, return_indices=True)
    alpha = np.clip((d - 18) * 10, 0, 255) * fg
    alpha = np.maximum(alpha, nd.binary_erosion(fg, iterations=2) * 255.0)
    a = alpha[..., None] / 255.0
    col = np.where(a > 0.05, (rgb - 255 * (1 - a)) / np.maximum(a, 1e-3), rgb)
    _SEG[path] = (lab, NI, np.dstack([np.clip(col, 0, 255), alpha]) / 255.0)
    return _SEG[path]

def pick_part(op):
    """one connected component of an AI sheet (pick in display coords = real / disp_scale), optional clip / flip / keep_holes;
    "extra_picks": [[x,y],...] merges more components of the same sheet (e.g. a brow + an eye); "png": path uses a cut RGBA part"""
    if op.get('png'):
        im = Image.open(op['png']).convert('RGBA')
    else:
        lab, NI, rgba = sheet_rgba(op['source']); ds = op.get('disp_scale', 1.25)
        ids = []
        for pk in [op['pick']] + op.get('extra_picks', []):
            px, py = [int(v * ds) for v in pk]; i = lab[NI[0][py, px], NI[1][py, px]]
            assert i, op
            ids.append(i)
        objs = nd.find_objects(lab); sls = [objs[i - 1] for i in ids]
        sl = (slice(min(q[0].start for q in sls), max(q[0].stop for q in sls)), slice(min(q[1].start for q in sls), max(q[1].stop for q in sls)))
        m = np.isin(lab[sl], ids)
        if op.get('clip'):
            x0, y0, x1, y1 = [int(v * ds) for v in op['clip']]; yy, xx = np.mgrid[sl[0], sl[1]]
            m = m & (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
        part = rgba[sl].copy(); part[..., 3] *= m
        if op.get('keep_holes'):
            wh = (part[..., :3].min(2) > 0.91) & m; wh = nd.binary_opening(wh, iterations=1); part[..., 3][wh] = 0
        im = RJ.to_img(part)
    if op.get('flip_h'): im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if op.get('rotate'): im = im.rotate(op['rotate'], expand=True, resample=Image.BICUBIC)
    return im.crop(im.getbbox())

def fit_iou(part, target_alpha, S, scale_range=(0.6, 1.6), steps=21, region=None):
    """best scale + offset of `part` (PIL RGBA) so its alpha overlaps target_alpha (2x canvas) most (IoU), FFT correlation"""
    from scipy.signal import fftconvolve
    T = (target_alpha > 0.5).astype(np.float32)
    if region is not None:
        x0, y0, x1, y1 = [int(v * S) for v in region]; R = np.zeros_like(T); R[y0:y1, x0:x1] = 1; T = T * R
    k = 4                                 # search on a 1/4 grid, refine at full res
    Ts = T[::k, ::k]; At = Ts.sum()
    pa = np.asarray(part.getchannel('A')).astype(np.float32) / 255
    base = np.sqrt(At * k * k / max((pa > 0.5).sum(), 1))       # scale that equalises areas
    best = None
    for s in np.linspace(scale_range[0], scale_range[1], steps) * base:
        w, h = max(1, round(part.width * s / k)), max(1, round(part.height * s / k))
        P = (np.asarray(part.getchannel('A').resize((w, h), Image.BILINEAR)).astype(np.float32) / 255 > 0.5).astype(np.float32)
        inter = fftconvolve(Ts, P[::-1, ::-1], mode='full')
        iy, ix = np.unravel_index(np.argmax(inter), inter.shape)
        I = inter[iy, ix]; iou = I / (At + P.sum() - I)
        if best is None or iou > best[0]:
            best = (iou, s, (ix - w + 1) * k, (iy - h + 1) * k)
    iou, s, x, y = best
    # refine offset at full resolution (+-k px)
    w, h = round(part.width * s), round(part.height * s)
    P = (np.asarray(part.getchannel('A').resize((w, h), Image.BILINEAR)).astype(np.float32) / 255 > 0.5)
    bi = (-1, x, y)
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            X0, Y0 = x + dx, y + dy
            cv = np.zeros_like(T, bool); xa, ya = max(X0, 0), max(Y0, 0); xb, yb = min(X0 + w, T.shape[1]), min(Y0 + h, T.shape[0])
            if xb <= xa or yb <= ya: continue
            cv[ya:yb, xa:xb] = P[ya - Y0:yb - Y0, xa - X0:xb - X0]
            I = (cv & (T > 0.5)).sum(); u = (cv | (T > 0.5)).sum(); v = I / max(u, 1)
            if v > bi[0]: bi = (v, X0, Y0)
    return float(s), int(bi[1]), int(bi[2]), round(float(bi[0]), 3)

def place(part, s, x, y, shape):
    w, h = max(1, round(part.width * s)), max(1, round(part.height * s))
    cv = Image.new('RGBA', (shape[1], shape[0]), (0, 0, 0, 0)); cv.alpha_composite(part.resize((w, h), Image.LANCZOS), (int(x), int(y)))
    return RJ.to_f(cv)

def match_colors(a, ref, sel_a, sel_ref, mode='meanstd', strength=1.0):
    """recolour a's selected pixels toward ref's selected pixels (per channel). hist = rank/quantile match."""
    out = a.copy(); src = a[..., :3][sel_a]; rp = ref[..., :3][sel_ref]
    if len(src) < 10 or len(rp) < 10: return out
    if mode == 'hist':
        new = np.empty_like(src)
        for ch in range(3):
            r = np.argsort(np.argsort(src[:, ch])) / max(1, len(src) - 1); new[:, ch] = np.quantile(rp[:, ch], r)
    else:
        new = (src - src.mean(0)) / (src.std(0) + 1e-4) * rp.std(0) + rp.mean(0)
    out[..., :3][sel_a] = np.clip(src * (1 - strength) + new * strength, 0, 1)
    return out

def non_line(a, thr=0.28):
    return (a[..., 3] > 0.9) & ((a[..., :3] @ [0.299, 0.587, 0.114]) > thr)

def run(cfg_path):
    c = json.load(open(cfg_path)); S = c.get('scale', 2); out = c['out_dir']; base = c['base']; PD = c.get('parts_dir', 'parts_' + base.split('_v')[-1])
    os.makedirs(f'{out}/{PD}', exist_ok=True)
    L, order, size = load_psd(c['src_psd2x']); pj = json.load(open(c['src_pivots']))
    P = {n: np.array(v, float) for n, v in pj['pivots'].items()}
    hidden = set(HIDDEN) & set(order)
    line = np.array(c['line_rgb'], float) / 255 if c.get('line_rgb') else np.array(pj.get('line_rgb', [30, 24, 20]), float) / 255
    log = []
    for op in c['ops']:
        k = op['op']
        if k == 'dup_layer':
            a = RJ.translate(L[op['src']], np.array(op['d'], float) * S).copy()
            a[..., :3] *= op.get('mul', 1.0)
            L[op['name']] = a
            order.insert(order.index(op['below']) if op.get('below') else order.index(op['above']) + 1, op['name'])
            if op.get('swap'): hidden.add(op['name'])
            if op.get('pivot_from'):
                P[op['pivot']] = P[op['pivot_from']] + np.array(op['d'], float)
            log.append(op)
        elif k == 'open_white':
            # re-open enclosed white background inside a part (e.g. tail loop filled by the cut's hole filling)
            a = L[op['part']].copy(); wh = (a[..., :3].min(2) > op.get('min', 0.9)) & (a[..., 3] > 0.5)
            wh = nd.binary_opening(wh, iterations=1); lab, n = nd.label(wh)
            big = [i + 1 for i, v in enumerate(nd.sum(wh, lab, range(1, n + 1))) if v >= op.get('min_area', 12) * S * S]
            m = np.isin(lab, big); m = nd.binary_dilation(m, iterations=1) & (a[..., :3].min(2) > op.get('min', 0.9) - 0.12)
            a[..., 3][m] = 0; L[op['part']] = a; log.append({**op, 'opened_px_1to1': int(m.sum() / S / S)})
        elif k == 'empty':
            L[op['name']] = np.zeros_like(L[order[0]])
            order.insert(order.index(op['below']) if op.get('below') else order.index(op['above']) + 1, op['name'])
            if op.get('swap'): hidden.add(op['name'])
            log.append(op)
        elif k == 'blink':
            head = L[op['head']]; at = order.index(op['head']) + 1; rec = {**op, 'eyes_fit': []}
            closed_only = op.get('closed_only', False)
            for e in op['eyes']:
                el = e.get('ellipse') or auto_eye(head, e['auto'], S)
                cx, cy, rx, ry = [v * S for v in el]
                sk = skin_color(head, cx, cy, rx, ry)
                # open: the head's own eye pixels (identical at rest)
                mo = ellipse_mask(head.shape[:2], cx, cy, rx + 0.5 * S, ry + 0.5 * S, soft=S)
                eo = head.copy(); eo[..., 3] = eo[..., 3] * mo
                # closed: skin patch + lid line
                mc = ellipse_mask(head.shape[:2], cx, cy, rx * 1.12 + 0.5 * S, ry * 1.12 + 0.5 * S, soft=S) * (head[..., 3] > 0.5)
                ec = np.zeros_like(head); ec[..., :3] = sk; ec[..., 3] = mc
                im = Image.new('L', (head.shape[1] * 4, head.shape[0] * 4), 0); d = ImageDraw.Draw(im)
                sgn = -1 if op.get('lid', 'down') == 'up' else 1
                pts = []
                for t in np.linspace(-1, 1, 25):
                    x = cx + t * rx * 0.95; y = cy + ry * 0.2 + sgn * ry * 0.28 * (1 - t * t)
                    pts.append((x * 4, y * 4))
                d.line(pts, fill=255, width=int(round(op.get('lid_w', 1.3) * S * 4)), joint='curve')
                ln = np.asarray(im.resize((head.shape[1], head.shape[0]), Image.LANCZOS), np.float32) / 255 * mc
                ec[..., :3] = ec[..., :3] * (1 - ln[..., None]) + line * ln[..., None]
                pairs = ((f"eye_open_{e['side']}_{op['suffix']}", eo, False), (f"eye_closed_{e['side']}_{op['suffix']}", ec, True))
                if closed_only:      # the open eye is already its own layer (e['open_layer']); closed goes right above it
                    pairs = pairs[1:]; at = order.index(e['open_layer']) + 1
                for nm, arr, hid in pairs:
                    L[nm] = arr.astype(np.float32); order.insert(at, nm); at += 1
                    if hid: hidden.add(nm)
                P[f"eye_{e['side']}"] = np.array([cx / S, cy / S])
                rec['eyes_fit'].append({'side': e['side'], 'ellipse_1to1': [round(v / S, 1) for v in (cx, cy, rx, ry)], 'skin_rgb': (sk * 255).round().tolist()})
            log.append(rec)
        elif k == 'swap_from_png':
            # add a ready-made swap part (e.g. an expression) already placed on the canvas at 1:1 or 2x
            im = Image.open(op['png']).convert('RGBA')
            if im.size != (L[order[0]].shape[1], L[order[0]].shape[0]): im = im.resize((L[order[0]].shape[1], L[order[0]].shape[0]), Image.LANCZOS)
            L[op['name']] = RJ.to_f(im); order.insert(order.index(op['above']) + 1, op['name'])
            if op.get('swap', True): hidden.add(op['name'])
            log.append(op)
        elif k == 'add_part':
            # a part cut from a new AI sheet, fitted onto the canvas:
            #  "fit": {"iou": layer, "region": [x0,y0,x1,y1], "scale": [a,b]} best alpha overlap with an existing layer
            #         {"box": [x0,y0,x1,y1]} fit inside the box (aspect kept, centred)   {"at": [cx,cy], "h": px} | {"w": px}
            #  "recolor": {"to": layer, "mode": "meanstd"|"hist", "strength": 1}   palette match on non-line pixels
            #  "mask": {"ellipse": [cx,cy,rx,ry], "skin": [r,g,b], "skin_tol": 0.2, "of": layer, "feather": 1.0}
            #         keep only the face area (inside the ellipse and on the base layer's skin, holes filled)
            #  "alpha_mul", "darken", "above"/"below"/"replace", "swap", "pivots": {name: [x,y]}, "merge_into": layer
            im = pick_part(op); shp = L[order[0]].shape[:2]; f = op['fit']; rec = {**op}
            if 'iou' in f:
                s_, x_, y_, iou = fit_iou(im, L[f['iou']][..., 3], S, tuple(f.get('scale', (0.6, 1.6))), region=f.get('region'))
                rec['fit_result'] = {'scale': round(s_, 3), 'xy_2x': [x_, y_], 'iou': iou}
            elif 'box' in f:
                x0, y0, x1, y1 = [v * S for v in f['box']]; s_ = min((x1 - x0) / im.width, (y1 - y0) / im.height)
                x_, y_ = (x0 + x1) / 2 - im.width * s_ / 2, (y0 + y1) / 2 - im.height * s_ / 2
                if f.get('anchor') == 'bottom': y_ = y1 - im.height * s_
                if f.get('anchor') == 'top': y_ = y0
            else:
                s_ = (f['h'] * S / im.height) if 'h' in f else (f['w'] * S / im.width)
                x_, y_ = f['at'][0] * S - im.width * s_ / 2, f['at'][1] * S - im.height * s_ / 2
            a = place(im, s_, x_, y_, shp)
            if op.get('recolor'):
                rc = op['recolor']; ref = L[rc['to']]
                a = match_colors(a, ref, non_line(a, rc.get('thr', 0.28)), non_line(ref, rc.get('thr', 0.28)), rc.get('mode', 'meanstd'), rc.get('strength', 1.0))
            if op.get('mask'):
                mk = op['mask']; base_ = L[mk.get('of', op.get('above'))]
                X, Y = RJ.grid(shp); cx, cy, rx, ry = [v * S for v in mk['ellipse']]
                el = ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2 <= 1
                if mk.get('skin'):
                    sk = np.array(mk['skin'], float) / 255; dist = np.linalg.norm(base_[..., :3] - sk, axis=-1)
                    skin = (dist < mk.get('skin_tol', 0.2)) & (base_[..., 3] > 0.5)
                    if mk.get('skin_lum'):     # shaded skin: anything lighter than the hair counts
                        skin |= ((base_[..., :3] @ [0.299, 0.587, 0.114]) > mk['skin_lum']) & (base_[..., 3] > 0.5)
                    skin = nd.binary_opening(skin, iterations=1)
                    region = nd.binary_fill_holes(nd.binary_closing(skin, iterations=2)) & el
                    if mk.get('grow'): region = nd.binary_dilation(region, iterations=int(mk['grow'] * S)) & el & (base_[..., 3] > 0.5)
                else:
                    region = el & (base_[..., 3] > 0.5)
                soft = nd.gaussian_filter(region.astype(np.float32), mk.get('feather', 1.0) * S)
                soft = np.where(region, np.maximum(soft, 0.0), 0) if mk.get('inside_only', True) else soft
                # where the new face has no pixels inside the region, fall back to the base head (no holes)
                fill = base_.copy(); w_ = a[..., 3:4]
                comp = fill.copy(); comp[..., :3] = fill[..., :3] * (1 - w_) + a[..., :3] * w_; comp[..., 3] = np.maximum(fill[..., 3], a[..., 3])
                a = comp.copy(); a[..., 3] = comp[..., 3] * np.clip(soft * 1.6, 0, 1)
                rec['mask_px_1to1'] = int(region.sum() / S / S)
            if op.get('alpha_mul'): a = a.copy(); a[..., 3] *= op['alpha_mul']
            if op.get('darken'): a = a.copy(); a[..., :3] *= op['darken']
            n = op['name']
            if op.get('merge_into'):
                b_ = L[op['merge_into']]; w_ = a[..., 3:4]; c_ = b_.copy()
                c_[..., :3] = b_[..., :3] * (1 - w_) + a[..., :3] * w_; c_[..., 3] = np.maximum(b_[..., 3], a[..., 3]); L[op['merge_into']] = c_
            elif op.get('replace'):
                L[n] = a.astype(np.float32)
            else:
                L[n] = a.astype(np.float32)
                if op.get('below'): order.insert(order.index(op['below']), n)
                else: order.insert(order.index(op['above']) + 1, n)
                if op.get('swap'): hidden.add(n)
            for pn, xy in op.get('pivots', {}).items(): P[pn] = np.array(xy, float)
            rec.pop('mask', None); log.append(rec)
        elif k == 'split':
            # one limb -> two segments at a knee line (perpendicular to the limb direction through the new pivot);
            # caps / overlap are added afterwards by rig_patch joints (round_cap2), so the cut here is clean.
            a = L[op['part']]; kp = np.array(op['at'], float) * S; u = RJ.unit(np.array(P[op['to']], float) * S - np.array(P[op['from']], float) * S)
            X, Y = RJ.grid(a.shape[:2]); t = (X - kp[0]) * u[0] + (Y - kp[1]) * u[1]
            up = a.copy(); up[..., 3] *= np.clip(0.5 - t, 0, 1); lo = a.copy(); lo[..., 3] *= np.clip(t + 0.5, 0, 1)
            i = order.index(op['part']); order[i:i + 1] = ([op['lower'], op['upper']] if op.get('upper_on_top', True) else [op['upper'], op['lower']])
            del L[op['part']]; L[op['upper']] = up; L[op['lower']] = lo; P[op['pivot']] = kp / S
            log.append(op)
        elif k == 'underfill':
            # hidden overlap extension: grow the parent under the child's rest footprint (within `radius` of the pivot)
            # with the parent's own nearest interior colours, so rotating the child shows parent, not background.
            pa, ch = L[op['parent']], L[op['child']]; pv = np.array(P[op['pivot']], float) * S
            X, Y = RJ.grid(pa.shape[:2]); disc = np.hypot(X - pv[0], Y - pv[1]) <= op['radius'] * S
            cover = np.maximum.reduce([L[q][..., 3] for q in op.get('under', [op['child']])]) > 0.5
            pin = nd.binary_erosion(pa[..., 3] > 0.9, iterations=int(op.get('inset', 2) * S))
            pin &= (pa[..., :3] @ [0.299, 0.587, 0.114]) > op.get('min_lum', 0.18)
            reg = cover & disc & (pa[..., 3] < 0.95)
            if op.get('shrink'): reg &= nd.binary_erosion(cover, iterations=int(op['shrink'] * S))
            _, (iy, ix) = nd.distance_transform_edt(~pin, return_indices=True)
            col = pa[..., :3][iy, ix]
            col = nd.uniform_filter(col, size=(int(3 * S), int(3 * S), 1)) * op.get('shade', 0.92)
            if order.index(op['child']) > order.index(op['parent']):
                # child drawn above the parent: the extension goes into the parent itself (hidden under the child)
                new = pa.copy()
                new[..., :3] = np.where(reg[..., None], pa[..., :3] * pa[..., 3:4] + col * (1 - pa[..., 3:4]), pa[..., :3]); new[..., 3] = np.maximum(pa[..., 3], reg.astype(np.float32))
                L[op['parent']] = new.astype(np.float32); where = op['parent']
            else:
                # child drawn below the parent: a static under-layer (moves with the parent) right below the child
                reg2 = reg & (pa[..., 3] < 0.5)
                ul = np.zeros_like(pa); ul[..., :3] = col; ul[..., 3] = nd.gaussian_filter(reg2.astype(np.float32), 0.5 * S) * reg2
                where = op.get('layer', f"{op['parent'].replace('_mesh', '')}_under_{op['child']}")
                L[where] = ul.astype(np.float32); order.insert(order.index(op['child']), where); reg = reg2
            log.append({**op, 'added_px_1to1': int(reg.sum() / S / S), 'into': where})
        elif k == 'grade':
            # tone a layer by tool: saturation / value scale, alpha scale (e.g. a recoloured highlight that went rainbow)
            a = L[op['part']].copy(); g = a[..., :3] @ [0.299, 0.587, 0.114]
            new = np.clip((g[..., None] + (a[..., :3] - g[..., None]) * op.get('sat', 1.0)) * op.get('val', 1.0), 0, 1)
            sel = (g > op.get('min_lum', -1))[..., None]
            if op.get('min_lum') is not None: sel = nd.gaussian_filter(sel[..., 0].astype(np.float32), S)[..., None]
            a[..., :3] = a[..., :3] * (1 - sel) + new * sel
            a[..., 3] *= op.get('alpha', 1.0); L[op['part']] = a; log.append(op)
        elif k == 'translate_layer':
            L[op['part']] = RJ.translate(L[op['part']], np.array(op['d'], float) * S); log.append(op)
        elif k == 'remove':
            for n_ in op['parts']: order.remove(n_); L.pop(n_, None); hidden.discard(n_)
            log.append(op)
        elif k == 'reorder':
            n_ = op['part']; order.remove(n_)
            if op.get('below'): order.insert(order.index(op['below']), n_)
            else: order.insert(order.index(op['above']) + 1, n_)
            log.append(op)
        elif k == 'pivots':
            for pn, xy in op['set'].items(): P[pn] = np.array(xy, float)
            log.append(op)
        elif k == 'rename':
            for a_, b_ in op['map'].items():
                L[b_] = L.pop(a_); order[order.index(a_)] = b_
                if a_ in hidden: hidden.discard(a_); hidden.add(b_)
            log.append(op)
        else:
            raise ValueError(k)
    HIDDEN.clear(); HIDDEN.update(hidden)
    W, H = size; W1, H1 = W // S, H // S
    piv1 = {n: [round(float(v[0]), 1), round(float(v[1]), 1)] for n, v in P.items()}
    small = {n: RJ.to_f(RJ.to_img(L[n]).resize((W1, H1), Image.LANCZOS)) for n in order}
    for suf, LL, sz, kk in (('', small, (W1, H1), 1), ('_src2x', L, (W, H), S)):
        psd = PSDImage.new('RGBA', sz)
        for n in order:
            ly = PixelLayer.frompil(RJ.to_img(LL[n]), psd, n, 0, 0)
            if n in hidden: ly.visible = False
            psd.append(ly)
        psd.append(PixelLayer.frompil(pivot_layer(piv1, sz, kk), psd, '_pivots', 0, 0))
        psd.save(f'{out}/{base}{suf}.psd')
    for n in order:
        im = RJ.to_img(small[n])
        if im.getbbox(): im.save(f'{out}/{PD}/{n}.png')
    compose(small, order, (W1, H1)).save(f'{out}/{base}_preview.png')
    # swap preview: every hidden layer shown (closed eyes etc.)
    cv = compose(small, [n for n in order], (W1, H1))
    for n in order:
        if n in hidden: cv.alpha_composite(RJ.to_img(small[n]))
    cv.save(f'{out}/{base}_preview_swaps.png')
    json.dump({'canvas': [W1, H1], 'unit': 'px@1:1', 'version': base, 'order': order, 'swap': sorted(hidden & set(order)), 'pivots': piv1,
               'line_rgb': [int(round(x * 255)) for x in line], 'from': c['src_psd2x'], 'log': {'extras': log, 'previous': pj.get('log')}},
              open(f'{out}/{base}_pivots.json', 'w'), ensure_ascii=False, indent=1, default=lambda o: o.tolist() if hasattr(o, 'tolist') else str(o))
    print(base, 'layers', len(order), 'swap', sorted(hidden & set(order)))

if __name__ == '__main__':
    for p in sys.argv[1:]:
        HIDDEN.clear(); run(p)
