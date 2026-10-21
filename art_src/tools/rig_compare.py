#!/usr/bin/env python3
"""rig_compare.py: combined multi-direction PSD (groups f/s/b, like hero_parts_v1.psd), combined preview,
and a before/after comparison sheet.
usage: rig_compare.py combine OUT_PREFIX dirPSD_f dirPSD_s dirPSD_b          (each a per-direction PSD)
       rig_compare.py compare OUT.png "label" old.psd new.psd [old2.psd new2.psd ...]"""
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

def compare(outp, label, pairs, zoom=2):
    rows = []
    for old, new in pairs:
        a, b = flat(old, (128, 128, 128, 255)), flat(new, (128, 128, 128, 255))
        W = a.width
        a = a.resize((W * zoom, W * zoom), Image.LANCZOS if W > 300 else Image.NEAREST)
        b = b.resize((W * zoom, W * zoom), Image.LANCZOS if W > 300 else Image.NEAREST)
        r = Image.new('RGBA', (a.width * 2 + 12, a.height + 22), (40, 40, 40, 255)); d = ImageDraw.Draw(r)
        r.paste(a, (0, 22)); r.paste(b, (a.width + 12, 22))
        d.text((6, 4), 'v1  ' + os.path.basename(old), fill=(255, 255, 0, 255))
        d.text((a.width + 18, 4), 'v2  ' + os.path.basename(new), fill=(120, 255, 120, 255))
        rows.append(r)
    sh = Image.new('RGBA', (max(r.width for r in rows), sum(r.height for r in rows) + 24), (40, 40, 40, 255))
    ImageDraw.Draw(sh).text((6, 6), label, fill=(255, 255, 255, 255)); y = 24
    for r in rows: sh.paste(r, (0, y)); y += r.height
    sh.save(outp)

if __name__ == '__main__':
    if sys.argv[1] == 'combine':
        combine(sys.argv[2], sys.argv[3:6])
    else:
        a = sys.argv[4:]; compare(sys.argv[2], sys.argv[3], list(zip(a[0::2], a[1::2])))
