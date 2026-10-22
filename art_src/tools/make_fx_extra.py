#!/usr/bin/env python3
"""make_fx_extra.py: F08 warning brush texture (AI sheet -> seamless 256 by tool) and F12 damage-number bitmap font
(tool-made from an OFL font, no AI). usage: make_fx_extra.py   (run from the repo root)
F08: the AI brush sheet is nearly periodic (measured period ~507 px at 1024); crop one period + 64 px overlap, min-cut wrap
     in x and y (make_tiles.wrap_x, no cross-fade), downscale to 256 with wrap padding. Output RGBA: white, alpha = stroke
     density (the shader tints it #7A2A2A / #C8584A per the warning spec).
F12: Lilita One (SIL OFL 1.1, Google Fonts) digits 0-9 + - ! x, 64 px, cream fill (#F2EBDD) with a 2 px lighter top
     gradient, 5 px dark-brown outline (#2A2018), 3 px drop shadow; AngelCode BMFont text .fnt + atlas png (Godot imports
     .fnt). Colour per event via modulate (outline stays dark): preview shows normal / crit / heal / player-hurt tints."""
import os, sys, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_tiles import wrap_x, seam_score

OUT = 'art_src/fx/fx_v2'

def f08(src='art_src/src/v21f/fx_f08_brush_gen1.jpg', period=None):
    g = np.asarray(Image.open(src).convert('L')).astype(float)
    if period is None:
        errs = {p: np.abs(g[:, :1024 - p] - g[:, p:]).mean() + np.abs(g[:1024 - p] - g[p:]).mean() for p in range(440, 560)}
        period = min(errs, key=errs.get)
    ov = 64; a = g[:period + ov, :period + ov][..., None].repeat(3, 2)
    a, cx = wrap_x(a, period); t, cy = wrap_x(a.transpose(1, 0, 2), period); a = t.transpose(1, 0, 2)
    pad = 32; big = np.pad(a, ((pad, pad), (pad, pad), (0, 0)), mode='wrap')
    s = 256 / period; im = Image.fromarray(np.clip(big, 0, 255).astype(np.uint8)).resize((round(big.shape[1] * s), round(big.shape[0] * s)), Image.LANCZOS)
    p2 = round(pad * s); im = im.crop((p2, p2, p2 + 256, p2 + 256))
    lum = np.asarray(im.convert('L')).astype(float)
    al = np.clip((255 - lum - 8) / (255 - lum - 8).max(), 0, 1) * 255
    out = np.dstack([np.full_like(al, 255), np.full_like(al, 255), np.full_like(al, 255), al]).astype(np.uint8)
    d = f'{OUT}/f08_warning_brush'; os.makedirs(d, exist_ok=True)
    Image.fromarray(out, 'RGBA').save(f'{d}/f08_warning_brush_256.png')
    sc = {'x': seam_score(np.dstack([al] * 3), 'x'), 'y': seam_score(np.dstack([al] * 3), 'y')}
    # 3x3 check on the warning red
    chk = Image.new('RGBA', (768, 768), (60, 56, 52, 255)); tint = Image.new('RGBA', (256, 256), (200, 88, 74, 255)); tint.putalpha(Image.fromarray(al.astype(np.uint8)))
    for i in range(3):
        for j in range(3): chk.alpha_composite(tint, (i * 256, j * 256))
    chk.save(f'{d}/f08_warning_brush_tiling_check.png')
    return {'period_px_at_1024': int(period), 'seam': sc}

def f12(font='/usr/share/fonts/truetype/sand-box/google/Lilita One/LilitaOne-Regular.ttf', size=64):
    chars = '0123456789+-!x'; ol = 5; sh = 3; padc = ol + sh + 2
    F = ImageFont.truetype(font, size); asc, desc = F.getmetrics(); lh = asc + desc + 2 * padc
    glyphs = []
    for ch in chars:
        bb = F.getbbox(ch); w = bb[2] - bb[0] + 2 * padc; h = lh
        m = Image.new('L', (w, h), 0); ImageDraw.Draw(m).text((padc - bb[0], padc), ch, font=F, fill=255)
        ma = np.asarray(m).astype(float) / 255
        olm = np.asarray(m.filter(ImageFilter.MaxFilter(2 * ol + 1)).filter(ImageFilter.GaussianBlur(0.6))).astype(float) / 255
        shm = np.roll(np.roll(olm, sh, 0), 1, 1) * 0.55
        ys = np.linspace(1, 0, h)[:, None]
        fill = np.array([242, 235, 221], float) * (0.9 + 0.1 * ys[..., None])           # light top -> slightly darker bottom
        line = np.array([42, 32, 24], float)
        a_ol = np.maximum(olm, shm); rgb = line[None, None] * np.ones((h, w, 1))
        rgb = rgb * (1 - ma[..., None]) + fill * ma[..., None]
        a = np.clip(np.maximum(a_ol, ma), 0, 1)
        glyphs.append((ch, np.dstack([rgb, a * 255]).astype(np.uint8), bb[2] - bb[0]))
    W = sum(g[1].shape[1] + 2 for g in glyphs); atlas = Image.new('RGBA', (W, lh), (0, 0, 0, 0)); x = 0
    lines = [f'info face="LilitaOne" size={size} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding={padc},{padc},{padc},{padc} spacing=2,2 outline={ol}',
             f'common lineHeight={lh} base={asc + padc} scaleW={W} scaleH={lh} pages=1 packed=0', 'page id=0 file="f12_damage_font.png"', f'chars count={len(glyphs)}']
    for ch, arr, adv in glyphs:
        atlas.alpha_composite(Image.fromarray(arr, 'RGBA'), (x, 0))
        lines.append(f'char id={ord(ch)} x={x} y=0 width={arr.shape[1]} height={lh} xoffset={-padc} yoffset=0 xadvance={adv + 2} page=0 chnl=15')
        x += arr.shape[1] + 2
    d = f'{OUT}/f12_damage_font'; os.makedirs(d, exist_ok=True)
    atlas.save(f'{d}/f12_damage_font.png'); open(f'{d}/f12_damage_font.fnt', 'w').write('\n'.join(lines) + '\n')
    # preview with the event tints (modulate)
    tints = {'normal': (255, 255, 255), 'crit (crimson)': (226, 120, 104), 'heal (moss)': (176, 210, 140), 'player hurt': (232, 150, 130)}
    pv = Image.new('RGBA', (900, 90 * len(tints)), (70, 74, 60, 255)); dd = ImageDraw.Draw(pv); gm = {g[0]: g for g in glyphs}
    for r, (nm, tc) in enumerate(tints.items()):
        txt = {'normal': '128', 'crit (crimson)': '256!', 'heal (moss)': '+35', 'player hurt': '-12'}[nm]; x = 20
        for ch in txt:
            arr = gm[ch][1].astype(float).copy(); arr[..., :3] *= np.array(tc, float) / 255
            pv.alpha_composite(Image.fromarray(arr.astype(np.uint8), 'RGBA'), (x, r * 90 + 4)); x += gm[ch][2] + 2
        dd.text((420, r * 90 + 36), nm + f'  modulate {tc}', fill=(240, 236, 226, 255))
    pv.save(f'{d}/f12_damage_font_preview.png')
    return {'font': 'Lilita One (SIL OFL 1.1)', 'size': size, 'chars': chars, 'atlas': list(atlas.size)}

if __name__ == '__main__':
    rec = {'f08': f08(), 'f12': f12()}
    json.dump(rec, open(f'{OUT}/extra_manifest.json', 'w'), ensure_ascii=False, indent=1); print(rec)
