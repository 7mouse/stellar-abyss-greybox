import sys,json,numpy as np
sys.path.insert(0,'/workspace/art_inbox/2026-10-21b/art_src/tools')
from rig_patch import load_psd, compose
from PIL import Image, ImageDraw
def sheet(out, bases, labels, items, half=14, k=6, solo_rows=False):
    rows=[]
    for b,lab in zip(bases,labels):
        L,o,s=load_psd(b+'_src2x.psd'); P=json.load(open(b+'_pivots.json'))['pivots']
        full=compose(L,o,s,(128,128,128,255))
        for solo in ([False,True] if solo_rows else [False]):
            tiles=[]
            for (pv,dy,parts) in items:
                p=np.array(P[pv])*2; p[1]+=dy*2
                img=full if not solo else compose(L,[n for n in o if n in parts],s,(128,128,128,255))
                h=half*2
                c=img.crop((int(p[0]-h),int(p[1]-h),int(p[0]+h),int(p[1]+h))).resize((2*h*k//2,2*h*k//2),Image.NEAREST)
                d=ImageDraw.Draw(c); d.text((3,3),f"{lab} {pv}{' solo' if solo else ''}",fill=(255,255,0,255))
                tiles.append(c)
            r=Image.new('RGBA',(sum(t.width+4 for t in tiles),tiles[0].height+4),(30,30,30,255)); x=0
            for t in tiles: r.paste(t,(x,0)); x+=t.width+4
            rows.append(r)
    sh=Image.new('RGBA',(max(r.width for r in rows),sum(r.height for r in rows)),(30,30,30,255)); y=0
    for r in rows: sh.paste(r,(0,y)); y+=r.height
    sh.save(out)
