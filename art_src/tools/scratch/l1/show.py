import sys
from PIL import Image
out=sys.argv[1];fs=sys.argv[2:];ims=[Image.open(f).convert('RGBA') for f in fs]
z=2 if max(i.width for i in ims)<=320 else 1
W=sum(i.width*z for i in ims)+10*len(ims);H=max(i.height*z for i in ims)
sh=Image.new('RGBA',(W,H),(120,120,120,255));x=0
for i in ims: sh.alpha_composite(i.resize((i.width*z,i.height*z)),(x,0));x+=i.width*z+10
sh.save(out)
