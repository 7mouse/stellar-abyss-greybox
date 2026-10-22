import sys,json,numpy as np
sys.path.insert(0,'/workspace/art_inbox/2026-10-21b/art_src/tools')
from rig_patch import load_psd
import rig_joints as RJ, rig_check as RC
from scipy import ndimage as nd
cfg,base,jn,rad=sys.argv[1],sys.argv[2],sys.argv[3],float(sys.argv[4])
c=json.load(open(cfg)); S=2
L,o,_=load_psd(base+'_src2x.psd'); piv=json.load(open(base+'_pivots.json'))['pivots']
j=[x for x in c['joints'] if x['pivot']==jn][0]
p=np.array(piv[jn])*S
mov=set([j['child']]+RC.descendants(c['joints'],j['child']))
static=np.zeros(L[o[0]].shape[:2]);movA=np.zeros_like(static)
for n in o:
    if n in mov: movA=np.maximum(movA,L[n][...,3])
    else: static=np.maximum(static,L[n][...,3])
X,Y=RJ.grid(static.shape); disc=np.hypot(X-p[0],Y-p[1])<=rad*S
rest=np.maximum(static,movA)>0.5
for ang in (-30,-15,15,30):
    m=np.zeros_like(static)
    for n in mov: m=np.maximum(m,RJ.rotate_about(L[n],p,ang)[...,3])
    h=disc&rest&(np.maximum(static,m)<0.5)
    lab,k=nd.label(h)
    for i in range(1,k+1):
        ys,xs=np.nonzero(lab==i)
        print(ang,'blob',len(xs)/4,'center',round((xs.mean()-p[0])/S,1),round((ys.mean()-p[1])/S,1),'static max nearby',round(float(static[ys,xs].max()),2),'head rest a',round(float(movA[ys,xs].mean()),2))
