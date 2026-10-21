#!/usr/bin/env python3
"""AI partsheet -> layered rig deliverable (rig-parts-spec §11/§12).
usage: cut_partsheet.py config.json
config: source, out_dir, base, canvas2x, disp_scale, parts[{name,pick,box,rotate,erase_red,empty}],
order (bottom->top), pivots{name:[x,y]} (pick/box/pivots in display coords = real/disp_scale)."""
import json,sys,time,os
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage as nd
from psd_tools import PSDImage
from psd_tools.api.layers import PixelLayer
def T(m):print(time.strftime('%H:%M:%S'),m,flush=True)
c=json.load(open(sys.argv[1]));ds=c['disp_scale'];C=c['canvas2x'];out=c['out_dir'];base=c['base']
os.makedirs(out+'/parts',exist_ok=True)
T('step1 bg removal start')
rgb=np.array(Image.open(c['source']).convert('RGB')).astype(int)
d=255-rgb.min(2)
fg=nd.binary_fill_holes(nd.binary_closing(d>28,iterations=2))
lab,_=nd.label(fg)
_,NI=nd.distance_transform_edt(lab==0,return_indices=True)
alpha=(np.clip((d-18)*10,0,255)*fg).astype(np.uint8)
alpha=np.maximum(alpha,(nd.binary_erosion(fg,iterations=2)*255).astype(np.uint8))
# decontaminate white fringe: unpremultiply against white
a=alpha[...,None]/255.0
col=np.where(a>0.05,(rgb-255*(1-a))/np.maximum(a,1e-3),rgb)
rgba=np.dstack([np.clip(col,0,255),alpha]).astype(np.uint8)
T('step1 end')
T('step2 cut start')
K=None;pose=c['pose_box']
k=min(C*0.92/(pose[3]-pose[1]),C*0.94/(pose[2]-pose[0]))  # fit tall or wide subjects
def M(x,y):return ((x-(pose[0]+pose[2])/2)*k+C/2,(y-pose[3])*k+C*0.977)
layers={};info={}
for p in c['parts']:
  n=p['name']
  if p.get('empty'):layers[n]=None;info[n]={'empty':True,'note':p.get('note','')};continue
  px,py=[int(v*ds) for v in p['pick']];i=lab[NI[0][py,px],NI[1][py,px]]
  assert i,n
  sl=nd.find_objects(lab)[i-1];m=(lab[sl]==i)
  part=rgba[sl].copy();part[...,3]=part[...,3]*m
  if p.get('erase_red'):
    q=part.astype(int);red=(q[...,0]>q[...,1]+45)&(q[...,0]>q[...,2]+40)
    red=nd.binary_dilation(red,iterations=2);part[...,3][red]=0
    # keep largest remaining blob
    l2,nn=nd.label(part[...,3]>0)
    if nn>1:
      big=np.argmax(nd.sum(np.ones_like(l2),l2,range(1,nn+1)))+1;part[...,3][l2!=big]=0
  img=Image.fromarray(part,'RGBA')
  if p.get('rotate'):img=img.rotate(p['rotate'],expand=True,resample=Image.BICUBIC)
  img=img.crop(img.getbbox())
  b=p['box'];x0,y0=M(b[0],b[1]);x1,y1=M(b[2],b[3])
  s=min((x1-x0)/img.width,(y1-y0)/img.height)
  img=img.resize((max(1,round(img.width*s)),max(1,round(img.height*s))),Image.LANCZOS)
  L=round((x0+x1)/2-img.width/2);Tp=round((y0+y1)/2-img.height/2)
  layers[n]=(img,L,Tp);info[n]={'pick_component':int(i),'scale':round(s,3)}
T('step2 end')
T('step3 compose start')
def full(n,scale):
  cv=Image.new('RGBA',(C,C),(0,0,0,0))
  if layers[n]:img,L,Tp=layers[n];cv.alpha_composite(img,(L,Tp))
  return cv if scale==1 else cv.resize((C//2,C//2),Image.LANCZOS)
prev2=Image.new('RGBA',(C,C),(0,0,0,0))
for n in c['order']:prev2.alpha_composite(full(n,1))
T('step3 end')
T('step4 pivots start')
piv={n:[round(M(*xy)[0]/2,1),round(M(*xy)[1]/2,1)] for n,xy in c['pivots'].items()}
pl=Image.new('RGBA',(C//2,C//2),(0,0,0,0));dr=ImageDraw.Draw(pl)
for n,(x,y) in piv.items():dr.ellipse([x-2,y-2,x+2,y+2],fill=(255,0,255,255))
json.dump({'canvas':[C//2,C//2],'unit':'px@1:1','pivots':piv,'parts':info},open(f'{out}/{base}_pivots.json','w'),ensure_ascii=False,indent=1)
T('step4 end')
T('step5 export start')
for sc,suf in((2,''),(1,'_src2x')):
  W=C//sc;psd=PSDImage.new('RGBA',(W,W))
  for n in c['order']:
    im=full(n,1) if sc==1 else full(n,2)
    if n not in layers or layers[n] is None: im=Image.new('RGBA',(W,W),(0,0,0,0))
    psd.append(PixelLayer.frompil(im,psd,n,0,0))
  pv=pl if sc==2 else pl.resize((C,C),Image.NEAREST)
  psd.append(PixelLayer.frompil(pv,psd,'_pivots',0,0))
  psd.save(f'{out}/{base}{suf}.psd')
for n in c['order']:
  im=full(n,2)
  if im.getbbox():im.save(f'{out}/parts/{n}.png')
pre=prev2.resize((C//2,C//2),Image.LANCZOS);pre.save(f'{out}/{base}_preview.png')
# side-by-side check sheet: reference pose | preview | preview+pivots on grey
ref=Image.fromarray(rgba).crop([int(v*ds) for v in pose]);ref.thumbnail((C//2,C//2))
sh=Image.new('RGBA',(C//2*3,C//2),(128,128,128,255));sh.alpha_composite(ref,(0,0));sh.alpha_composite(pre,(C//2,0))
pp=pre.copy();pp.alpha_composite(pl);sh.alpha_composite(pp,(C,0));sh.save(f'{out}/{base}_check.png')
T('step5 end')
