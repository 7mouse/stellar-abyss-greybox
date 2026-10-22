#!/usr/bin/env python3
"""AI partsheet -> layered rig deliverable (rig-parts-spec §11/§12).
usage: cut_partsheet.py config.json [--no-caps]
config: source, out_dir, base, canvas2x, disp_scale, parts[{name,pick,box,rotate,erase_red,empty}],
order (bottom->top), pivots{name:[x,y]} (pick/box/pivots in display coords = real/disp_scale).
v2 (2026-10-21): optional joint post-processing, same keys as rig_patch.py:
  "joints":[{"pivot","parent","child","child_cls":"small|big","parent_cls",...}], "ops":[...],
  "fill_holes":[...], "defringe":true, "line_rgb":[r,g,b]
  If "joints" is present the raw cut is written as <base>_raw*.psd and rig_patch.py turns it into <base>
  (round overlapping joint heads, re-outlined, cleaned edges, updated _pivots). --no-caps skips that.
v3 (2026-10-21c, level-1 batch): "canvas2x_h" (non-square canvas, e.g. slime 512x384), "k" (fixed sheet->canvas2x scale,
  to match another facing), per part: "source" (another sheet, own segmentation, "disp_scale" optional),
  "png" (pre-cut RGBA file, no segmentation, e.g. derived eye/expression parts), "clip":[x0,y0,x1,y1] (keep only this
  rect of the picked component, sheet display coords), "flip_h", "scale_x", "drop_dark" (lum threshold: drop line pixels, e.g. soft highlight), "alpha_mul", "keep_holes" (re-open enclosed white), "cut_dark_in":[x0,y0,x1,y1,lum] (open a dark cavity), "recolor_ref":[x0,y0,x1,y1] (per-channel histogram match of non-line pixels to that sheet rect: variant recolour by tool) (horizontal squash), "swap":true
  (expression/blink swap: layer saved hidden, left out of the preview)."""
import json,sys,time,os
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage as nd
from psd_tools import PSDImage
from psd_tools.api.layers import PixelLayer
def T(m):print(time.strftime('%H:%M:%S'),m,flush=True)
c=json.load(open(sys.argv[1]));ds=c['disp_scale'];C=c['canvas2x'];CH=c.get('canvas2x_h',C);out=c['out_dir'];base=c['base']
CAPS=('joints' in c) and ('--no-caps' not in sys.argv)
final_base=base
if CAPS: base=base+'_raw'
for p_ in c['parts']:
  if p_.get('source') and p_['source']!=c['source']: print('note: per-part source',p_['name'],'(handled by caller)')
os.makedirs(out+'/parts',exist_ok=True)
T('step1 bg removal start')
def segment(path):
  rgb=np.array(Image.open(path).convert('RGB')).astype(int)
  d=255-rgb.min(2)
  fg=nd.binary_fill_holes(nd.binary_closing(d>28,iterations=2))
  lab,_=nd.label(fg)
  _,NI=nd.distance_transform_edt(lab==0,return_indices=True)
  alpha=(np.clip((d-18)*10,0,255)*fg).astype(np.uint8)
  alpha=np.maximum(alpha,(nd.binary_erosion(fg,iterations=2)*255).astype(np.uint8))
  a=alpha[...,None]/255.0
  col=np.where(a>0.05,(rgb-255*(1-a))/np.maximum(a,1e-3),rgb)
  return lab,NI,np.dstack([np.clip(col,0,255),alpha]).astype(np.uint8)
SEG={}
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
k=c.get('k') or min(CH*0.92/(pose[3]-pose[1]),C*0.94/(pose[2]-pose[0]))  # fit tall or wide subjects
def M(x,y):return ((x-(pose[0]+pose[2])/2)*k+C/2,(y-pose[3])*k+CH*0.977)
layers={};info={}
for p in c['parts']:
  n=p['name']
  if p.get('empty'):layers[n]=None;info[n]={'empty':True,'note':p.get('note','')};continue
  if p.get('png'):
    part=np.array(Image.open(p['png']).convert('RGBA'));i=0
  else:
    if p.get('source') and p['source']!=c['source']:
      if p['source'] not in SEG: SEG[p['source']]=segment(p['source'])
      lab_,NI_,rgba_=SEG[p['source']];ds_=p.get('disp_scale',ds)
    else: lab_,NI_,rgba_,ds_=lab,NI,rgba,ds
    px,py=[int(v*ds_) for v in p['pick']];i=lab_[NI_[0][py,px],NI_[1][py,px]]
    assert i,n
    sl=nd.find_objects(lab_)[i-1];m=(lab_[sl]==i)
    if p.get('clip'):
      x0_,y0_,x1_,y1_=[int(v*ds_) for v in p['clip']];yy_,xx_=np.mgrid[sl[0],sl[1]]
      m=m&(xx_>=x0_)&(xx_<x1_)&(yy_>=y0_)&(yy_<y1_)
    part=rgba_[sl].copy();part[...,3]=part[...,3]*m
    if p.get('keep_holes'):
      # re-open enclosed white background (e.g. a curled tail loop) that binary_fill_holes closed
      wh=(part[...,:3].min(2)>232)&m;wh=nd.binary_opening(wh,iterations=1);part[...,3][wh]=0
    if p.get('cut_dark_in'):
      # open up a dark cavity (e.g. the inside of a shell) inside a rect: largest dark blob there -> transparent
      x0_,y0_,x1_,y1_=[int(v*ds_) for v in p['cut_dark_in'][:4]];T_=p['cut_dark_in'][4]
      yy_,xx_=np.mgrid[sl[0],sl[1]];q=part.astype(float);lum=q[...,:3]@[0.299,0.587,0.114]
      dk=(lum<T_)&(xx_>=x0_)&(xx_<x1_)&(yy_>=y0_)&(yy_<y1_)&(part[...,3]>0)
      dk=nd.binary_opening(dk,iterations=2);l3,n3=nd.label(dk)
      if n3:
        big=np.argmax(nd.sum(dk,l3,range(1,n3+1)))+1;hole=nd.binary_fill_holes(nd.binary_dilation(l3==big,iterations=1))
        part[...,3][hole]=0
        l4,n4=nd.label(part[...,3]>0)
        if n4>1:
          keep_=np.argmax(nd.sum(np.ones_like(l4),l4,range(1,n4+1)))+1;part[...,3][l4!=keep_]=0
  if p.get('erase_red'):
    q=part.astype(int);red=(q[...,0]>q[...,1]+45)&(q[...,0]>q[...,2]+40)
    red=nd.binary_dilation(red,iterations=2);part[...,3][red]=0
    # keep largest remaining blob
    l2,nn=nd.label(part[...,3]>0)
    if nn>1:
      big=np.argmax(nd.sum(np.ones_like(l2),l2,range(1,nn+1)))+1;part[...,3][l2!=big]=0
  if p.get('recolor_ref'):
    # histogram-match the part's non-line pixels, per channel, to a reference rect of the main sheet (variant body)
    x0_,y0_,x1_,y1_=[int(v*ds) for v in p['recolor_ref']];ref_=rgb[y0_:y1_,x0_:x1_].reshape(-1,3)
    q=part.astype(float);lum=q[...,:3]@[0.299,0.587,0.114];sel=(q[...,3]>128)&(lum>p.get('recolor_min_lum',70))
    for ch in range(3):
      src_=q[...,ch][sel];order_=np.argsort(np.argsort(src_))/max(1,len(src_)-1)
      q[...,ch][sel]=np.quantile(ref_[:,ch],order_)
    part=np.clip(q,0,255).astype(np.uint8)
  if p.get('drop_dark') or p.get('alpha_mul'):
    q=part.astype(float);lum=q[...,:3]@[0.299,0.587,0.114]
    if p.get('drop_dark'):q[...,3]*=np.clip((lum-p['drop_dark'])/25,0,1)
    q[...,3]*=p.get('alpha_mul',1.0);part=np.clip(q,0,255).astype(np.uint8)
  img=Image.fromarray(part,'RGBA')
  if p.get('flip_h'):img=img.transpose(Image.FLIP_LEFT_RIGHT)
  if p.get('scale_x'):img=img.resize((max(1,round(img.width*p['scale_x'])),img.height),Image.LANCZOS)
  if p.get('rotate'):img=img.rotate(p['rotate'],expand=True,resample=Image.BICUBIC)
  img=img.crop(img.getbbox())
  b=p['box'];x0,y0=M(b[0],b[1]);x1,y1=M(b[2],b[3])
  s=min((x1-x0)/img.width,(y1-y0)/img.height)
  img=img.resize((max(1,round(img.width*s)),max(1,round(img.height*s))),Image.LANCZOS)
  L=round((x0+x1)/2-img.width/2);Tp=round((y0+y1)/2-img.height/2)
  layers[n]=(img,L,Tp);info[n]={'pick_component':int(i),'scale':round(s,3)}
  if p.get('swap'):info[n]['swap']=True
T('step2 end')
T('step3 compose start')
def full(n,scale):
  cv=Image.new('RGBA',(C,CH),(0,0,0,0))
  if layers[n]:img,L,Tp=layers[n];cv.alpha_composite(img,(L,Tp))
  return cv if scale==1 else cv.resize((C//2,CH//2),Image.LANCZOS)
SWAP={p['name'] for p in c['parts'] if p.get('swap')}
prev2=Image.new('RGBA',(C,CH),(0,0,0,0))
for n in c['order']:
  if n not in SWAP:prev2.alpha_composite(full(n,1))
T('step3 end')
T('step4 pivots start')
piv={n:[round(M(*xy)[0]/2,1),round(M(*xy)[1]/2,1)] for n,xy in c['pivots'].items()}
pl=Image.new('RGBA',(C//2,CH//2),(0,0,0,0));dr=ImageDraw.Draw(pl)
for n,(x,y) in piv.items():dr.ellipse([x-2,y-2,x+2,y+2],fill=(255,0,255,255))
json.dump({'canvas':[C//2,CH//2],'unit':'px@1:1','pivots':piv,'parts':info,'swap':sorted(SWAP)},open(f'{out}/{base}_pivots.json','w'),ensure_ascii=False,indent=1)
T('step4 end')
T('step5 export start')
for sc,suf in((2,''),(1,'_src2x')):
  W=C//sc;Hh=CH//sc;psd=PSDImage.new('RGBA',(W,Hh))
  for n in c['order']:
    im=full(n,1) if sc==1 else full(n,2)
    if n not in layers or layers[n] is None: im=Image.new('RGBA',(W,Hh),(0,0,0,0))
    ly=PixelLayer.frompil(im,psd,n,0,0)
    if n in SWAP: ly.visible=False
    psd.append(ly)
  pv=pl if sc==2 else pl.resize((C,CH),Image.NEAREST)
  psd.append(PixelLayer.frompil(pv,psd,'_pivots',0,0))
  psd.save(f'{out}/{base}{suf}.psd')
for n in c['order']:
  im=full(n,2)
  if im.getbbox():im.save(f'{out}/parts/{n}.png')
pre=prev2.resize((C//2,CH//2),Image.LANCZOS);pre.save(f'{out}/{base}_preview.png')
# side-by-side check sheet: reference pose | preview | preview+pivots on grey
ref=Image.fromarray(rgba).crop([int(v*ds) for v in pose]);ref.thumbnail((C//2,CH//2))
sh=Image.new('RGBA',(C//2*3,CH//2),(128,128,128,255));sh.alpha_composite(ref,(0,0));sh.alpha_composite(pre,(C//2,0))
pp=pre.copy();pp.alpha_composite(pl);sh.alpha_composite(pp,(C,0));sh.save(f'{out}/{base}_check.png')
T('step5 end')
if CAPS:
  T('step6 joint caps start')
  sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
  import rig_patch
  fix={k:c[k] for k in ('joints','ops','fill_holes','fill_holes_opts','defringe','line_rgb','line_w','cap_version','post_ops','solidify','fill_inset','erase_cut','hidden_caps_only_under_cover') if k in c}
  fix.update(parts_dir='parts',src_psd2x=f'{out}/{base}_src2x.psd',src_pivots=f'{out}/{base}_pivots.json',out_dir=out,base=final_base,scale=2)
  json.dump(fix,open(f'{out}/{final_base}_fix.json','w'),ensure_ascii=False,indent=1)
  rig_patch.run(f'{out}/{final_base}_fix.json')
  T('step6 end')
