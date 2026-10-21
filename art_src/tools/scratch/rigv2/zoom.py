import sys
from psd_tools import PSDImage
from PIL import Image,ImageDraw
# zoom.py out.png box(x0,y0,x1,y1 at 1:1) psd1 psd2 ...  -> side by side, 2x psd assumed
out=sys.argv[1];box=[int(v) for v in sys.argv[2].split(',')];fs=sys.argv[3:]
tiles=[]
for f in fs:
  p=PSDImage.open(f);W=p.size[0];k=W//256
  cv=Image.new('RGBA',(W,W),(128,128,128,255))
  for l in p:
    if l.name=='_pivots':continue
    cv.alpha_composite(l.topil().convert('RGBA'),(l.left,l.top))
  c=cv.crop([v*k for v in box]);s=400/max(c.size);tiles.append(c.resize((int(c.width*s),int(c.height*s)),Image.NEAREST))
sh=Image.new('RGBA',(sum(t.width+8 for t in tiles),tiles[0].height),(30,30,30,255));x=0
for t in tiles:sh.paste(t,(x,0));x+=t.width+8
sh.save(out)
