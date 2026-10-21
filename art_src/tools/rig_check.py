#!/usr/bin/env python3
"""rig_check.py: joint self-check for a rig version (optionally against the previous version).
usage: rig_check.py fix_config.json [--prev old_src2x.psd old_pivots.json] --sheet out.png --json out.json
For each joint the child (and everything hanging off it) is rotated -30..+30 deg around the pivot.
Numeric: uncovered pixels (1:1) inside a disc of 0.6 x min(half widths) around the pivot, parent(s)+child only.
Visual: crops of the full composite at -30 / 0 / +30, previous version left, this version right."""
import json, sys, os, argparse
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rig_joints as RJ
from rig_patch import load_psd, HIDDEN

ANG = (-30, -15, 0, 15, 30)

def descendants(joints, part):
    out = []
    for j in joints:
        if j['parent'] == part and j['child'] != part:
            out += [j['child']] + descendants(joints, j['child'])
    return out

def comp_gap(L, order, piv, joints, j, S=2, angles=ANG, radius=None, band=None):
    """Visible holes: pixels inside a disc around the pivot that are opaque in the full composite at rest
    but become transparent when the child chain rotates (what the programmer sees as a seam/gap)."""
    p = np.array(piv[j['pivot']]) * S
    mov = set([j['child']] + descendants(joints, j['child']))
    static = np.zeros(L[order[0]].shape[:2], np.float32)
    for n in order:
        if n not in mov:
            static = np.maximum(static, L[n][..., 3])
    movA = np.zeros_like(static)
    for n in mov:
        movA = np.maximum(movA, L[n][..., 3])
    X, Y = RJ.grid(static.shape)
    pr = RJ.end_profile(L[j['child']][..., 3], p, RJ.unit(p - RJ.centroid(L[j['child']][..., 3])))
    r = radius * S if radius else max(pr['hw'] * 0.8, 3 * S)
    disc = np.hypot(X - p[0], Y - p[1]) <= r
    rest = np.maximum(static, movA) > 0.5
    if band:
        # seam metric (v3): only holes within `band` px (1:1) of the parent(s) edge count. Wide accessory parts
        # (mushroom cap, curled tail, crown) otherwise score their own silhouette change as 'holes'.
        from scipy import ndimage as nd
        pm = np.maximum.reduce([L[q][..., 3] for q in j.get('test_parents', [j['parent']])]) > 0.5
        disc = disc & (nd.distance_transform_edt(~pm) <= band * S)
    out = {}
    for ang in angles:
        if ang == 0:
            out[ang] = 0.0; continue
        m = np.zeros_like(static)
        for n in mov:
            m = np.maximum(m, RJ.rotate_about(L[n], p, ang)[..., 3])
        hole = disc & rest & (np.maximum(static, m) < 0.5)
        out[ang] = round(float(hole.sum()) / (S * S), 1)
    return out, r / S

def test(L, order, piv, joints, S=2, radii=None, band=None):
    res = {}
    for j in joints:
        p = np.array(piv[j['pivot']]) * S
        pars = j.get('test_parents', [j['parent']])
        par = L[pars[0]].copy()
        for q in pars[1:]:
            par[..., 3] = np.maximum(par[..., 3], L[q][..., 3])
        uc = RJ.unit(p - np.array(piv[j['child_from']]) * S) if j.get('child_from') else None
        r, rc = RJ.joint_gap_test(par, L[j['child']], p, ANG, scale=S, u_child=uc)
        cg, cr = comp_gap(L, order, piv, joints, j, S, radius=(radii or {}).get(j['pivot']))
        if band:
            sg, _ = comp_gap(L, order, piv, joints, j, S, radius=(radii or {}).get(j['pivot']), band=band)
        res[j['pivot']] = dict(parent='+'.join(pars), child=j['child'], pair_disc_r=round(rc, 1), pair_gaps=r,
                               pair_worst=max(r.values()), visible_disc_r=round(cr, 1), visible_gaps=cg, worst=max(cg.values()),
                               **({'seam_band': band, 'seam_gaps': sg, 'seam_worst': max(sg.values())} if band else {}))
    return res

def crop_rot(L, order, piv, joint, joints, ang, S=2, half=26):
    p = np.array(piv[joint['pivot']]) * S
    mov = set([joint['child']] + descendants(joints, joint['child']))
    Hh, W = L[order[0]].shape[:2]
    cv = Image.new('RGBA', (W, Hh), (128, 128, 128, 255))
    for n in order:
        a = L[n]
        if n in mov and ang:
            a = RJ.rotate_about(a, p, ang)
        cv.alpha_composite(RJ.to_img(a))
    h = half * S
    c = cv.crop((int(p[0] - h), int(p[1] - h), int(p[0] + h), int(p[1] + h))).resize((156, 156), Image.NEAREST)
    d = ImageDraw.Draw(c); d.ellipse([75, 75, 81, 81], outline=(255, 0, 255, 255))
    return c

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('config'); ap.add_argument('--prev', nargs=2); ap.add_argument('--sheet'); ap.add_argument('--json'); ap.add_argument('--out-root'); ap.add_argument('--labels', nargs=2, default=['v1', 'v2']); ap.add_argument('--seam-band', type=float, default=None, help='also report seam holes within N px (1:1) of the parent edge')
    a = ap.parse_args()
    c = json.load(open(a.config)); S = c.get('scale', 2)
    if not os.path.isabs(c['out_dir']):
        c['out_dir'] = os.path.join(a.out_root or os.getcwd(), c['out_dir'])
    base = f"{c['out_dir']}/{c['base']}"
    L2, o2, _ = load_psd(base + '_src2x.psd'); o2 = [n for n in o2 if n not in HIDDEN]; piv2 = json.load(open(base + '_pivots.json'))['pivots']
    joints = c['joints']
    radii = None
    if a.prev:
        L1, o1, _ = load_psd(a.prev[0]); o1 = [n for n in o1 if n not in HIDDEN]; piv1 = json.load(open(a.prev[1]))['pivots']
        out = {'previous': test(L1, o1, piv1, joints, S)}
        radii = {k: v['visible_disc_r'] for k, v in out['previous'].items()}   # same disc for both versions
    else:
        out = {}
    out['version'] = test(L2, o2, piv2, joints, S, radii, band=a.seam_band)
    if a.json:
        json.dump(out, open(a.json, 'w'), ensure_ascii=False, indent=1)
    if a.sheet:
        cols = 6 if a.prev else 3
        rows = len(joints)
        sh = Image.new('RGBA', (cols * 160 + 150, rows * 160 + 24), (40, 40, 40, 255)); d = ImageDraw.Draw(sh)
        A, B = a.labels
        hdr = ([f'{A} -30', f'{A} 0', f'{A} +30'] if a.prev else []) + [f'{B} -30', f'{B} 0', f'{B} +30']
        for i, hname in enumerate(hdr):
            d.text((150 + i * 160 + 50, 6), hname, fill=(255, 255, 0, 255))
        for r, j in enumerate(joints):
            y = 24 + r * 160
            g2 = out['version'][j['pivot']]['worst']
            g1 = out['previous'][j['pivot']]['worst'] if a.prev else None
            d.text((4, y + 60), f"{j['pivot']}\n{j['child']}\nholes {A}={g1}\nholes {B}={g2}" + (f"\nseam={out['version'][j['pivot']]['seam_worst']}" if a.seam_band else ''), fill=(255, 255, 255, 255))
            x = 150
            sets = ([(L1, o1, piv1)] if a.prev else []) + [(L2, o2, piv2)]
            for (LL, oo, pp) in sets:
                for ang in (-30, 0, 30):
                    sh.paste(crop_rot(LL, oo, pp, j, joints, ang, S), (x, y)); x += 160
        sh.save(a.sheet)
    for j in joints:
        v = out['version'][j['pivot']]
        pv = out['previous'][j['pivot']]['worst'] if a.prev else '-'
        pp = out['previous'][j['pivot']]['pair_worst'] if a.prev else '-'
        print(f"{j['pivot']:12s} {j['child']:16s} visible holes(px@1:1, worst +-30) {a.labels[0]}={pv} {a.labels[1]}={v['worst']} | pair-core {a.labels[0]}={pp} {a.labels[1]}={v['pair_worst']}" + (f" | seam(<= {a.seam_band}px of parent)={v['seam_worst']}" if a.seam_band else ''))

if __name__ == '__main__':
    main()
