import sys,json,numpy as np
sys.path.insert(0,'/workspace/art_inbox/2026-10-21b/art_src/tools')
from rig_patch import load_psd, compose
import rig_joints as RJ
from scipy import ndimage as nd
R='/workspace/art_inbox/2026-10-21b/art_src/rigs/'
sets={'boar':'sprout_boar/sprout_boar_parts_s','hero_f':'hero/hero_parts_f','hero_s':'hero/hero_parts_s','hero_b':'hero/hero_parts_b'}
def comp(L,o):
    return RJ.to_f(compose(L,o,(L[o[0]].shape[1],L[o[0]].shape[0])))
res={}
for k,base in sets.items():
    res[k]={}
    for tag,suf in (('v2','_v2'),('v21','_v2_1')):
        L,o,_=load_psd(R+base+suf+'_src2x.psd'); N,_,_=load_psd(f'/workspace/v21/tmp/{k}_{tag}_nocaps_src2x.psd')
        log=json.load(open(R+base+suf+'_pivots.json'))['log']['joints']
        C=comp(L,o); CN=comp(N,o)
        for j,rec in log.items():
            for side,r in rec.items():
                n=r.get('part'); 
                if not n or 'added_px_1to1' not in r: continue
                A=(L[n][...,3]>N[n][...,3]+0.05)
                if A.sum()<4: continue
                vis=('visible' in r.get('action','')) if tag=='v21' else (o.index(n)>o.index([q for q in (log[j].get('child',{}).get('part'),log[j].get('parent',{}).get('part')) if q and q!=n][0] if len(rec)>1 else None) if False else None)
                d=np.abs(RJ.lum(C[...,:3])-RJ.lum(CN[...,:3]))[A]*255
                m=N[n][...,3]>0.5
                din=nd.distance_transform_edt(L[n][...,3]>0.5)
                dA=nd.distance_transform_edt(~A)
                src=m&(dA>=8)&(dA<=14)&(nd.distance_transform_edt(m)>3)
                Ain=A&(din>3)
                band=lambda:(RJ.lum(L[n][...,:3])[Ain].mean()-RJ.lum(N[n][...,:3])[src].mean())*255 if Ain.sum()>3 and src.sum()>3 else None
                oldend=m&(dA<=6)&(din>3)
                dark=int(((RJ.lum(L[n][...,:3])<0.30)&oldend).sum()/4)
                key=f'{j}:{n}'
                e=res[k].setdefault(key,{})
                e[tag]=dict(rest_dlum_mean=round(float(d.mean()),1),rest_dlum_p95=round(float(np.percentile(d,95)),1),
                            ext_minus_interior_lum=None if band() is None else round(float(band()),1),
                            dark_px_old_end=dark, action=r.get('action'))
json.dump(res,open('metrics.json','w'),indent=1,ensure_ascii=False)
for k,v in res.items():
    print('==',k)
    for key,e in v.items():
        a=e.get('v2',{}); b=e.get('v21',{})
        print(f"{key:32s} {('VIS' if 'visible' in (b.get('action') or '') else 'hid'):3s} restΔ v2={a.get('rest_dlum_mean')}/{a.get('rest_dlum_p95')} v21={b.get('rest_dlum_mean')}/{b.get('rest_dlum_p95')} | ext-int v2={a.get('ext_minus_interior_lum')} v21={b.get('ext_minus_interior_lum')} | dark@oldend v2={a.get('dark_px_old_end')} v21={b.get('dark_px_old_end')}")
