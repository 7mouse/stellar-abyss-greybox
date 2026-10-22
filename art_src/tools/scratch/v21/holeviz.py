import sys,json,numpy as np
sys.path.insert(0,'/workspace/art_inbox/2026-10-21b/art_src/tools')
from rig_patch import load_psd
import rig_joints as RJ, rig_check as RC
from PIL import Image
cfg,base,jn,ang,out=sys.argv[1],sys.argv[2],sys.argv[3],float(sys.argv[4]),sys.argv[5]
c=json.load(open(cfg)); S=2
L,o,_=load_psd(base+'_src2x.psd'); piv=json.load(open(base+'_pivots.json'))['pivots']
j=[x for x in c['joints'] if x['pivot']==jn][0]
p=np.array(piv[jn])*S
mov=set([j['child']]+RC.descendants(c['joints'],j['child']))
static=np.zeros(L[o[0]].shape[:2]);movA=np.zeros_like(static); m=np.zeros_like(static)
for n in o:
    if n in mov: movA=np.maximum(movA,L[n][...,3]); m=np.maximum(m,RJ.rotate_about(L[n],p,ang)[...,3])
    else: static=np.maximum(static,L[n][...,3])
rest=np.maximum(static,movA)>0.5
hole=rest&(np.maximum(static,m)<0.5)
img=np.zeros(static.shape+(3,),np.uint8)+40
img[static>0.5]=(90,90,200); img[(m>0.5)&~(static>0.5)]=(90,200,90); img[rest&~(np.maximum(static,m)>0.5)]=(255,0,0)
H=60
crop=img[int(p[1]-H):int(p[1]+H),int(p[0]-H):int(p[0]+H)]
im=Image.fromarray(crop).resize((480,480),Image.NEAREST); im.save(out)
