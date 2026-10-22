import sys,json,numpy as np
sys.path.insert(0,'/workspace/art_inbox/2026-10-21b/art_src/tools')
from rig_patch import load_psd
import rig_joints as RJ, rig_check as RC
from PIL import Image
cfg,base,joints_sel=sys.argv[1],sys.argv[2],sys.argv[3].split(',')
c=json.load(open(cfg)); S=2
L,o,_=load_psd(base+'_src2x.psd'); piv=json.load(open(base+'_pivots.json'))['pivots']
prevr=None
if len(sys.argv)>4: prevr={k:v['visible_disc_r'] for k,v in json.load(open(sys.argv[4]))['previous'].items()}
for j in c['joints']:
    if j['pivot'] not in joints_sel: continue
    r,rad=RC.comp_gap(L,o,piv,c['joints'],j,S,radius=(prevr or {}).get(j['pivot']))
    p=np.array(piv[j['pivot']])*S
    mov=set([j['child']]+RC.descendants(c['joints'],j['child']))
    static=np.zeros(L[o[0]].shape[:2]);movA=np.zeros_like(static)
    for n in o:
        if n in mov: movA=np.maximum(movA,L[n][...,3])
        else: static=np.maximum(static,L[n][...,3])
    X,Y=RJ.grid(static.shape); disc=np.hypot(X-p[0],Y-p[1])<=rad*S; rest=np.maximum(static,movA)>0.5
    print(j['pivot'],r,'r',round(rad,1))
    for ang in (-30,30):
        m=np.zeros_like(static)
        for n in mov: m=np.maximum(m,RJ.rotate_about(L[n],p,ang)[...,3])
        h=disc&rest&(np.maximum(static,m)<0.5)
        ys,xs=np.nonzero(h)
        if len(xs): print('  ',ang,'n',len(xs),'dx',round((xs.mean()-p[0])/S,1),'dy',round((ys.mean()-p[1])/S,1),'bbox',(xs.min()-p[0])/S,(xs.max()-p[0])/S,(ys.min()-p[1])/S,(ys.max()-p[1])/S)
