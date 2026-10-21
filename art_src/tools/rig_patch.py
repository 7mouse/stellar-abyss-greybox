#!/usr/bin/env python3
"""rig_patch.py: upgrade an existing rig PSD (no re-generation) -> next version.
usage: rig_patch.py fix_config.json [more.json ...] [--root REPO] [--out-root DIR]   (run from the repo root)
Each config: src_psd2x, src_pivots (1:1 json), out_dir, base, scale(2), line_rgb (optional, 0..255),
  defringe(bool), fill_holes[parts], ops[...], joints[...]
ops (coordinates/offsets at 1:1):
  {"op":"translate","parts":[..],"d":[dx,dy],"pivots":[..]}
  {"op":"align_x","part":p,"top_band":12,"to_pivot":"neck"}            shift part so its top band is centred on pivot x
  {"op":"cut_above_curve","part":p,"ellipse":[cx,cy,ax,by]}             remove pixels above the lower half-ellipse, re-outline
  {"op":"attach","child":p,"parent":q,"joint":"elbow_l","parent_from":"shoulder_l","child_from":"wrist_l",
       "with_parts":[..],"with_pivots":[..],"inset":2}                    move child so its joint end meets parent's
  {"op":"pivot_to_edge","pivot":n,"parents":[..],"dir":[0,-1],"inset":2,"x_from_part":p}
joints: {"pivot":n,"parent":q,"child":p,"child_cls":"small|big","parent_cls":null|"small"|"big",
         "child_from":pivot|null, "parent_from":pivot|null, "child_target":px, "parent_target":px}
"""
import json, os, sys, time
import numpy as np
from PIL import Image, ImageDraw
from psd_tools import PSDImage
from psd_tools.api.layers import PixelLayer, Group
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rig_joints as RJ

CLS = {'small': RJ.SMALL, 'big': RJ.BIG}

def load_psd(path):
    psd = PSDImage.open(path)
    W, H = psd.size
    layers, order = {}, []
    for l in psd:
        if l.name.startswith('_'):
            continue
        cv = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        im = l.topil()
        if im is not None:
            cv.alpha_composite(im.convert('RGBA'), (l.left, l.top))
        layers[l.name] = RJ.to_f(cv)
        order.append(l.name)
    return layers, order, (W, H)

def reoutline(a, old_alpha, line_rgb, lw):
    m_new = a[..., 3] > 0.5
    changed = np.abs(a[..., 3] - old_alpha) > 0.05
    if not changed.any():
        return a
    from scipy import ndimage as nd
    din = nd.distance_transform_edt(m_new)
    near = nd.distance_transform_edt(~changed) <= lw + 2.5
    st = (np.clip(lw + 0.5 - din, 0, 1) * near * (a[..., 3] > 0.02))[..., None] * 0.92
    out = a.copy()
    out[..., :3] = out[..., :3] * (1 - st) + np.asarray(line_rgb)[None, None] * st
    return out

def compose(layers, order, size, bg=None):
    W, H = size
    cv = Image.new('RGBA', (W, H), bg or (0, 0, 0, 0))
    for n in order:
        if layers.get(n) is not None:
            cv.alpha_composite(RJ.to_img(layers[n]))
    return cv

def pivot_layer(piv, size, k=1):
    pl = Image.new('RGBA', size, (0, 0, 0, 0)); d = ImageDraw.Draw(pl)
    for n, (x, y) in piv.items():
        x, y = x * k, y * k; r = 2 * k
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 0, 255, 255))
    return pl

def _res(path, root):
    return path if (os.path.isabs(path) or root is None) else os.path.join(root, path)

def run(cfg_path, root=None, out_root=None):
    """root: where relative src_* paths resolve (repo checkout); out_root: where relative out_dir resolves."""
    t0 = time.time()
    c = json.load(open(cfg_path))
    c['src_psd2x'] = _res(c['src_psd2x'], root); c['src_pivots'] = _res(c['src_pivots'], root)
    c['out_dir'] = _res(c['out_dir'], out_root or root)
    S = c.get('scale', 2)
    base, out = c['base'], c['out_dir']
    PD = c.get('parts_dir', 'parts_v2')
    os.makedirs(f'{out}/{PD}', exist_ok=True)
    L, order, size = load_psd(c['src_psd2x'])
    pj = json.load(open(c['src_pivots']))
    P = {n: np.array(xy, dtype=np.float64) * S for n, xy in pj['pivots'].items()}   # 2x coords
    log = {'ops': [], 'joints': {}, 'cleanup': {}}
    line = np.array(c['line_rgb']) / 255.0 if c.get('line_rgb') else RJ.line_color(list(L.values()))
    lw = c.get('line_w', 1.0) * S
    # 1. cleanup
    if c.get('defringe', True):
        for n in order:
            L[n] = RJ.defringe(L[n])
    for n in c.get('fill_holes', []):
        fh = c.get('fill_holes_opts', {}).get(n, {})
        L[n], k = RJ.fill_holes(L[n], max_area=c.get('fill_holes_max', 4000), close_r=int(fh.get('close_r', 0) * S),
                                box=[int(v * S) for v in fh['box']] if fh.get('box') else None)
        log['cleanup'][n] = f'filled {k / (S * S):.0f} px@1:1 hole'
    # 2. ops
    for op in c.get('ops', []):
        kind = op['op']
        if kind == 'translate':
            d = np.array(op['d'], dtype=np.float64) * S
            for n in op['parts']:
                L[n] = RJ.translate(L[n], d)
            for n in op.get('pivots', []):
                P[n] = P[n] + d
            log['ops'].append({**op})
        elif kind == 'align_x':
            a = L[op['part']][..., 3] > 0.5
            ys, xs = np.nonzero(a)
            top = ys.min(); band = a[top: top + int(op.get('top_band', 12) * S)]
            bx = np.nonzero(band.any(0))[0]
            cx = (bx.min() + bx.max() + 1) / 2
            dx = round(P[op['to_pivot']][0] - cx)
            L[op['part']] = RJ.translate(L[op['part']], (dx, 0))
            for n in op.get('pivots', []):
                P[n] = P[n] + np.array([dx, 0])
            log['ops'].append({**op, 'dx_1to1': dx / S})
        elif kind == 'cut_above_curve':
            n = op['part']; a = L[n]; old = a[..., 3].copy()
            cx, cy, ax, by = [v * S for v in op['ellipse']]
            X, Y = RJ.grid(a.shape)
            q = np.clip(1 - ((X - cx) / ax) ** 2, 0, 1)
            ycurve = cy + by * np.sqrt(q)
            inside = np.abs(X - cx) < ax
            # soft edge 1px
            keep = np.where(inside, np.clip(Y - ycurve + 0.5, 0, 1), 1.0)
            a = a.copy(); a[..., 3] = a[..., 3] * keep
            L[n] = reoutline(a, old, line, lw)
            log['ops'].append({**op, 'removed_px_1to1': round(float((old - a[..., 3] > 0.5).sum()) / S / S)})
        elif kind == 'attach':
            ch, pa, j = op['child'], op['parent'], op['joint']
            up = RJ.unit(P[j] - P[op['parent_from']]) if op.get('parent_from') else RJ.unit(P[j] - RJ.centroid(L[pa][..., 3]))
            uc = RJ.unit(P[j] - P[op['child_from']]) if op.get('child_from') else RJ.unit(P[j] - RJ.centroid(L[ch][..., 3]))
            pp = RJ.end_profile(L[pa][..., 3], P[j], up); cp = RJ.end_profile(L[ch][..., 3], P[j], uc)
            pend = P[j] + up * pp['t_end'] + pp['v'] * pp['s0']
            cend = P[j] + uc * cp['t_end'] + cp['v'] * cp['s0']
            inset = op.get('inset', 2) * S
            d = np.round((pend - up * inset) - cend)   # child end goes `inset` px inside the parent end
            gap_before = float(np.linalg.norm(pend - cend)) / S
            for n in [ch] + op.get('with_parts', []):
                L[n] = RJ.translate(L[n], d)
            for n in op.get('with_pivots', []):
                P[n] = P[n] + d
            P[j] = pend - up * inset / 2      # joint centre in the middle of the overlap
            log['ops'].append({**op, 'moved_1to1': (d / S).tolist(), 'end_gap_before_1to1': round(gap_before, 1),
                               'new_pivot': (P[j] / S).round(1).tolist()})
        elif kind == 'swing_attach':
            # rotate the child around its far pivot (hinge, e.g. wrist) so its joint end overlaps the parent
            # by `overlap` px. Keeps the hand where it was, closes the gap at the elbow.
            from scipy import ndimage as nd
            ch, pa, j, hg = op['child'], op['parent'], op['joint'], op['hinge']
            H_ = P[hg]; uc = RJ.unit(P[j] - H_)
            cp = RJ.end_profile(L[ch][..., 3], P[j], uc)
            cend = P[j] + uc * cp['t_end'] + cp['v'] * cp['s0']
            # end centre sits hw back from the tip
            cc = cend - uc * cp['hw']
            pm = L[pa][..., 3] > 0.5
            _, (iy, ix) = nd.distance_transform_edt(~pm, return_indices=True)
            yy, xx = int(cc[1]), int(cc[0])
            q = np.array([ix[yy, xx] + 0.5, iy[yy, xx] + 0.5])
            gap = float(np.linalg.norm(q - cc)) - cp['hw']
            w = RJ.unit(q - cc)
            T = q - w * (cp['hw'] - op.get('overlap', 6) * S)
            a0 = np.degrees(np.arctan2(cc[1] - H_[1], cc[0] - H_[0])); a1 = np.degrees(np.arctan2(T[1] - H_[1], T[0] - H_[0]))
            ang = -(a1 - a0)            # PIL rotate: positive = counter-clockwise on screen
            L[ch] = RJ.rotate_about(L[ch], H_, ang)
            for n in op.get('with_parts', []):
                L[n] = RJ.rotate_about(L[n], H_, ang)
            P[j] = T
            log['ops'].append({**op, 'gap_before_1to1': round(gap / S, 1), 'rotated_deg': round(float(-ang), 1),
                               'new_pivot': (T / S).round(1).tolist()})
        elif kind == 'pivot_to_overlap':
            m = (L[op['parts'][0]][..., 3] > 0.5) & (L[op['parts'][1]][..., 3] > 0.5)
            if m.any():
                P[op['pivot']] = RJ.centroid(m.astype(np.float32))
            log['ops'].append({**op, 'new_pivot': (P[op['pivot']] / S).round(1).tolist(), 'overlap_px_1to1': int(m.sum() / S / S)})
        elif kind == 'pivot_to_edge':
            n = op['pivot']; dvec = RJ.unit(op['dir'])
            par = np.maximum.reduce([L[q][..., 3] for q in op['parents']]) > 0.5
            if op.get('x_from_part'):
                cx = RJ.centroid(L[op['x_from_part']][..., 3])[0]
                P[n] = np.array([cx, P[n][1]])
            p = P[n].copy(); steps = 0
            while steps < 200:
                x, y = int(p[0]), int(p[1])
                if 0 <= y < par.shape[0] and 0 <= x < par.shape[1] and par[y, x]:
                    break
                p += dvec; steps += 1
            P[n] = p + dvec * op.get('inset', 2) * S
            log['ops'].append({**op, 'new_pivot': (P[n] / S).round(1).tolist()})
        else:
            raise ValueError(kind)
    # 3. joints: round caps
    idx = {n: i for i, n in enumerate(order)}
    for jt in c.get('joints', []):
        j, pa, ch = jt['pivot'], jt['parent'], jt['child']
        rec = {}
        if jt.get('child_cls'):
          uc = RJ.unit(P[j] - P[jt['child_from']]) if jt.get('child_from') else RJ.unit(P[j] - RJ.centroid(L[ch][..., 3]))
          L[ch], rec['child'] = RJ.round_cap(L[ch], P[j], uc, CLS[jt['child_cls']], S, on_top=idx[ch] > idx[pa],
                                          line_rgb=line, line_w=lw, target=jt.get('child_target'), cap_r=jt.get('child_cap_r'))
          rec['child']['part'] = ch; rec['child']['cls'] = jt['child_cls']
        if jt.get('parent_cls'):
            up = RJ.unit(P[j] - P[jt['parent_from']]) if jt.get('parent_from') else RJ.unit(P[j] - RJ.centroid(L[pa][..., 3]))
            L[pa], rec['parent'] = RJ.round_cap(L[pa], P[j], up, CLS[jt['parent_cls']], S, on_top=idx[pa] > idx[ch],
                                               line_rgb=line, line_w=lw, target=jt.get('parent_target'), cap_r=jt.get('parent_cap_r'),
                                               hide_under=(np.maximum.reduce([L[q][..., 3] for q in jt['parent_hide_under']])
                                                           if jt.get('parent_hide_under') else None))
            rec['parent']['part'] = pa; rec['parent']['cls'] = jt['parent_cls']
        log['joints'][j] = rec
    # 4. export
    W, H = size; W1, H1 = W // S, H // S
    piv1 = {n: [round(float(v[0]) / S, 1), round(float(v[1]) / S, 1)] for n, v in P.items()}
    small = {n: RJ.to_f(RJ.to_img(L[n]).resize((W1, H1), Image.LANCZOS)) for n in order}
    for sc, suf, LL, sz, k in ((1, '', small, (W1, H1), 1), (S, '_src2x', L, (W, H), S)):
        psd = PSDImage.new('RGBA', sz)
        for n in order:
            psd.append(PixelLayer.frompil(RJ.to_img(LL[n]), psd, n, 0, 0))
        psd.append(PixelLayer.frompil(pivot_layer(piv1, sz, k), psd, '_pivots', 0, 0))
        psd.save(f'{out}/{base}{suf}.psd')
    for n in order:
        im = RJ.to_img(small[n])
        if im.getbbox():
            im.save(f'{out}/{PD}/{n}.png')
    compose(small, order, (W1, H1)).save(f'{out}/{base}_preview.png')
    json.dump({'canvas': [W1, H1], 'unit': 'px@1:1', 'version': base, 'order': order, 'pivots': piv1,
               'line_rgb': [int(round(x * 255)) for x in line], 'log': log},
              open(f'{out}/{base}_pivots.json', 'w'), ensure_ascii=False, indent=1,
              default=lambda o: o.tolist() if hasattr(o, 'tolist') else str(o))
    print(f'{base}: done in {time.time() - t0:.1f}s', flush=True)
    return dict(layers=L, small=small, order=order, pivots=piv1, size=size, log=log, line=line)

if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('configs', nargs='+')
    ap.add_argument('--root', default=None, help='repo checkout for relative src paths (default: cwd)')
    ap.add_argument('--out-root', default=None, help='base for relative out_dir (default: --root)')
    a = ap.parse_args()
    for p in a.configs:
        run(p, a.root or os.getcwd(), a.out_root)
