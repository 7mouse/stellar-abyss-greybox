import sys,json,numpy as np
sys.path.insert(0,'/tmp/sag/art_src/tools')
from rig_patch import load_psd
import rig_joints as RJ
from PIL import Image, ImageDraw
def zoom(psd,piv,items,out,half=20,k=6,bgc=(150,150,150,255),solo=False):
    L,order,size=load_psd(psd); P=json.load(open(piv))['pivots']
    tiles=[]
    for (pv,parts) in items:
        p=np.array(P[pv])*2
        cv=Image.new('RGBA',size,bgc)
        for n in order:
            if solo and n not in parts: continue
            cv.alpha_composite(RJ.to_img(L[n]))
        h=half*2
        c=cv.crop((int(p[0]-h),int(p[1]-h),int(p[0]+h),int(p[1]+h))).resize((2*h*k//2,2*h*k//2),Image.NEAREST)
        d=ImageDraw.Draw(c); d.text((3,3),pv+' '+','.join(parts),fill=(255,255,0,255))
        tiles.append(c)
    W=sum(t.width for t in tiles); sh=Image.new('RGBA',(W,tiles[0].height))
    x=0
    for t in tiles: sh.paste(t,(x,0)); x+=t.width
    sh.save(out)
if __name__=='__main__':
    pass
