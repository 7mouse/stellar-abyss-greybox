#!/usr/bin/env python3
"""ref_poses.py: reference key-pose sheets rendered from the rig itself (rig-parts-spec §1.3), no painting.
usage: ref_poses.py poses.json            (run from the repo root)
poses.json: {"rig": "<1:1 psd>", "pivots": "<pivots.json>", "fix": "<fix json with joints>" | null,
  "attach": {"part": "parent_part", ...}  (parts that are not joint children: hair, scarf, eyes, sword...),
  "root_part": "torso_s_mesh", "out": "<sheet.png>", "scale": 2,
  "anims": [{"name": "idle", "fps": 8, "timing": "...", "keys": [{"label": "1", "rot": {"neck": 5, ...},
              "root_d": [dx, dy], "root_rot": deg, "root_scale": [sx, sy], "hide": [...], "show": [...]}]}]}
Angles in degrees, positive = clockwise on screen. Each child chain rotates about its pivot, children follow.
Hidden (swap) layers stay hidden unless listed in "show" (e.g. eye_closed_r_s on the hit key)."""
import json, sys, os
import numpy as np
from PIL import Image, ImageDraw
from psd_tools import PSDImage

def mat_rot(p, deg):
    a = np.radians(deg); c, s = np.cos(a), np.sin(a)
    T1 = np.array([[1, 0, p[0]], [0, 1, p[1]], [0, 0, 1]]); R = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]]); T2 = np.array([[1, 0, -p[0]], [0, 1, -p[1]], [0, 0, 1]])
    return T1 @ R @ T2

def main(cfg):
    c = json.load(open(cfg)); psd = PSDImage.open(c['rig']); W, H = psd.size
    layers, order, hidden = {}, [], set()
    for l in psd:
        if l.name.startswith('_'): continue
        cv = Image.new('RGBA', (W, H), (0, 0, 0, 0)); im = l.topil()
        if im is not None: cv.alpha_composite(im.convert('RGBA'), (l.left, l.top))
        layers[l.name] = cv; order.append(l.name)
        if not l.visible: hidden.add(l.name)
    piv = json.load(open(c['pivots']))['pivots']
    joints = json.load(open(c['fix']))['joints'] if c.get('fix') else []
    parent = {j['child']: (j['parent'], j['pivot']) for j in joints}
    for k, v in c.get('attach', {}).items(): parent.setdefault(k, (v, None))
    def chain(part):
        out = []
        while part in parent:
            pa, pv = parent[part]
            if pv: out.append(pv)
            part = pa
        return out[::-1]
    S = c.get('scale', 2); pad = 8; cellW, cellH = W * S, H * S + 30
    anims = c['anims']; ncol = max(len(a['keys']) for a in anims)
    sheet = Image.new('RGBA', (180 + ncol * (cellW + pad), len(anims) * (cellH + pad) + 34), (236, 232, 222, 255)); d = ImageDraw.Draw(sheet)
    d.text((8, 8), c.get('title', os.path.basename(c['out'])) + '  (rendered from the rig: rotations about the _pivots points; positive = clockwise)', fill=(30, 30, 30, 255))
    rest_root = np.array(piv.get('root', [W / 2, H * 0.97]), float)
    for r, an in enumerate(anims):
        y0 = 34 + r * (cellH + pad)
        d.text((8, y0 + 8), f"{an['name']}\n{an.get('fps', '')} fps\n" + '\n'.join(an.get('timing', '').split('; ')), fill=(20, 20, 20, 255))
        for k, key in enumerate(an['keys']):
            rot = key.get('rot', {}); vis = [n for n in order if (n not in hidden or n in key.get('show', [])) and n not in key.get('hide', [])]
            Rm = np.eye(3)
            if key.get('root_scale'):
                sx, sy = key['root_scale']; Rm = np.array([[1, 0, rest_root[0]], [0, 1, rest_root[1]], [0, 0, 1]]) @ np.diag([sx, sy, 1]) @ np.array([[1, 0, -rest_root[0]], [0, 1, -rest_root[1]], [0, 0, 1]])
            if key.get('root_rot'):
                rp = np.array(piv.get(key.get('root_rot_pivot', 'root'), rest_root), float); Rm = mat_rot(rp, key['root_rot']) @ Rm
            dx, dy = key.get('root_d', [0, 0]); Rm = np.array([[1, 0, dx], [0, 1, dy], [0, 0, 1]]) @ Rm
            cv = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            for n in vis:
                M = Rm.copy()
                for pv in chain(n):
                    if rot.get(pv): M = M @ mat_rot(piv[pv], rot[pv])
                inv = np.linalg.inv(M)
                im = layers[n].transform((W, H), Image.AFFINE, tuple(inv[:2].ravel()), resample=Image.BICUBIC)
                cv.alpha_composite(im)
            x0 = 180 + k * (cellW + pad)
            bg = Image.new('RGBA', (cellW, H * S), (205, 200, 188, 255)); bg.alpha_composite(cv.resize((cellW, H * S), Image.LANCZOS))
            dd = ImageDraw.Draw(bg); gy = int(rest_root[1] * S); dd.line([0, gy, cellW, gy], fill=(150, 140, 120, 255))
            sheet.alpha_composite(bg, (x0, y0)); d.text((x0 + 4, y0 + H * S + 4), key.get('label', str(k + 1)), fill=(20, 20, 20, 255))
    os.makedirs(os.path.dirname(c['out']), exist_ok=True); sheet.save(c['out']); print(c['out'], sheet.size)

if __name__ == '__main__':
    for p in sys.argv[1:]: main(p)
