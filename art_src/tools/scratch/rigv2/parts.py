import sys
from psd_tools import PSDImage
from PIL import Image,ImageDraw
f=sys.argv[1];out=sys.argv[2];names=sys.argv[3:]
p=PSDImage.open(f);W=p.size[0];k=1024//W
tiles=[]
for l in p:
  if l.name in names:
    cv=Image.new('RGBA',(W,W),(128,128,128,255));cv.alpha_composite(l.topil().convert('RGBA'),(l.left,l.top))
    bb=l.topil().getbbox();pad=10*W//256
    bb=(max(0,bb[0]-pad),max(0,bb[1]-pad),min(W,bb[2]+pad),min(W,bb[3]+pad))
    c=cv.crop(bb);s=300/max(c.size);c=c.resize((int(c.width*s),int(c.height*s)),Image.NEAREST)
    d=ImageDraw.Draw(c);d.text((2,2),f'{l.name} {bb}',fill='yellow');tiles.append(c)
H=max(t.height for t in tiles);sheet=Image.new('RGBA',(sum(t.width+6 for t in tiles),H),(60,60,60,255));x=0
for t in tiles:sheet.paste(t,(x,0));x+=t.width+6
sheet.save(out)
