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
            L[op['name']] = a; order.insert(order.index(op['below']), op['name'])
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
            L[op['name']] = np.zeros_like(L[order[0]]); order.insert(order.index(op['above']) + 1, op['name'])
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
