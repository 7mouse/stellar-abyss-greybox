#!/usr/bin/env python3
"""rig_compare.py: combined multi-direction PSD (groups f/s/b, like hero_parts_v1.psd), combined preview,
and a before/after comparison sheet.
usage: rig_compare.py combine OUT_PREFIX dirPSD_f dirPSD_s dirPSD_b          (each a per-direction PSD)
       rig_compare.py compare OUT.png "label" old.psd new.psd [old2.psd new2.psd ...] [--labels v2 v2.1]
       rig_compare.py rotsheet OUT.png old_fix.json new_fix.json joint[,joint...] [--labels v2 v2.1] [--out-root DIR]
           static full body + every listed joint at -30/0/+30 (child chain rotated), old left, new right"""
import sys, os
from PIL import Image, ImageDraw
from psd_tools import PSDImage
from psd_tools.api.layers import PixelLayer, Group

def flat(path, bg=None):
    p = PSDImage.open(path); W, H = p.size
    cv = Image.new('RGBA', (W, H), bg or (0, 0, 0, 0))
    for l in p:
        if l.name.startswith('_'): continue
        im = l.topil()
        if im is not None: cv.alpha_composite(im.convert('RGBA'), (l.left, l.top))
    return cv

def combine(prefix, paths):
    src = [PSDImage.open(p) for p in paths]
    W, H = src[0].size
    out = PSDImage.new('RGBA', (W, H))
    for name, s in zip('fsb', src):
        g = Group.new(out, name, open_folder=True)
        for l in s:
            im = Image.new('RGBA', (W, H), (0, 0, 0, 0)); t = l.topil()
            if t is not None: im.alpha_composite(t.convert('RGBA'), (l.left, l.top))
            g.append(PixelLayer.frompil(im, out, l.name, 0, 0))
    out.save(prefix + '.psd')
    pv = Image.new('RGBA', (W * 3, H), (0, 0, 0, 0))
    for i, p in enumerate(paths): pv.alpha_composite(flat(p), (i * W, 0))
    pv.save(prefix + '_preview.png')

def compare(outp, label, pairs, zoom=2, labels=('v1', 'v2')):
    rows = []
    for old, new in pairs:
        a, b = flat(old, (128, 128, 128, 255)), flat(new, (128, 128, 128, 255))
        W = a.width
        a = a.resize((W * zoom, W * zoom), Image.LANCZOS if W > 300 else Image.NEAREST)
        b = b.resize((W * zoom, W * zoom), Image.LANCZOS if W > 300 else Image.NEAREST)
        r = Image.new('RGBA', (a.width * 2 + 12, a.height + 22), (40, 40, 40, 255)); d = ImageDraw.Draw(r)
        r.paste(a, (0, 22)); r.paste(b, (a.width + 12, 22))
        d.text((6, 4), labels[0] + '  ' + os.path.basename(old), fill=(255, 255, 0, 255))
        d.text((a.width + 18, 4), labels[1] + '  ' + os.path.basename(new), fill=(120, 255, 120, 255))
        rows.append(r)
    sh = Image.new('RGBA', (max(r.width for r in rows), sum(r.height for r in rows) + 24), (40, 40, 40, 255))
    ImageDraw.Draw(sh).text((6, 6), label, fill=(255, 255, 255, 255)); y = 24
    for r in rows: sh.paste(r, (0, y)); y += r.height
    sh.save(outp)

def rotsheet(outp, cfg_old, cfg_new, joints, labels=('v2', 'v2.1'), out_root=None, half=30, cell=200):
    import json
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import rig_check as RC
    from rig_patch import load_psd, compose
    sets = []
    for cp in (cfg_old, cfg_new):
        c = json.load(open(cp)); od = c['out_dir']
        if not os.path.isabs(od): od = os.path.join(out_root or os.getcwd(), od)
        b = f"{od}/{c['base']}"
        L, o, sz = load_psd(b + '_src2x.psd'); pv = json.load(open(b + '_pivots.json'))['pivots']
        sets.append((L, o, sz, pv, c['joints']))
    W = 6 * cell + 160
    top = []
    for (L, o, sz, pv, jj) in sets:
        im = compose(L, o, sz, (128, 128, 128, 255)).resize((3 * cell, 3 * cell), Image.LANCZOS); top.append(im)
    sh = Image.new('RGBA', (W, 3 * cell + 30 + len(joints) * (cell + 8) + 30), (40, 40, 40, 255)); d = ImageDraw.Draw(sh)
    d.text((160 + 10, 8), labels[0] + ' rest', fill=(255, 255, 0, 255)); d.text((160 + 3 * cell + 10, 8), labels[1] + ' rest', fill=(120, 255, 120, 255))
    sh.paste(top[0], (160, 24)); sh.paste(top[1], (160 + 3 * cell, 24))
    y = 3 * cell + 40
    for i, hname in enumerate([f'{labels[0]} -30', f'{labels[0]} 0', f'{labels[0]} +30', f'{labels[1]} -30', f'{labels[1]} 0', f'{labels[1]} +30']):
        d.text((160 + i * cell + 60, y - 14), hname, fill=(255, 255, 0, 255) if i < 3 else (120, 255, 120, 255))
    for jn in joints:
        d.text((6, y + cell // 2 - 10), jn, fill=(255, 255, 255, 255))
        x = 160
        for (L, o, sz, pv, jj) in sets:
            jt = [q for q in jj if q['pivot'] == jn][0]
            for ang in (-30, 0, 30):
                cr = RC.crop_rot(L, o, pv, jt, jj, ang, 2, half).resize((cell, cell), Image.NEAREST)
                sh.paste(cr, (x, y)); x += cell
        y += cell + 8
    sh.save(outp)

if __name__ == '__main__':
    args = sys.argv[1:]; labels = ('v1', 'v2'); out_root = None
    if '--labels' in args:
        i = args.index('--labels'); labels = tuple(args[i + 1:i + 3]); del args[i:i + 3]
    if '--out-root' in args:
        i = args.index('--out-root'); out_root = args[i + 1]; del args[i:i + 2]
    if args[0] == 'combine':
        combine(args[1], args[2:5])
    elif args[0] == 'rotsheet':
        rotsheet(args[1], args[2], args[3], args[4].split(','), labels, out_root)
    else:
        a = args[3:]; compare(args[1], args[2], list(zip(a[0::2], a[1::2])), labels=labels)
