import sys
from psd_tools import PSDImage
from PIL import Image,ImageDraw
f=sys.argv[1];out=sys.argv[2];hl=sys.argv[3:] 
p=PSDImage.open(f);W=p.size[0]
cv=Image.new('RGBA',(W,W),(128,128,128,255))
for l in p:
  im=l.topil().convert('RGBA')
  if hl and l.name not in hl and l.name!='_pivots': 
    a=im.split()[3].point(lambda v:v*0.35);im.putalpha(a)
  cv.alpha_composite(im,(l.left,l.top))
cv=cv.resize((W*2,W*2),Image.NEAREST)
d=ImageDraw.Draw(cv)
for i in range(0,W*2,40):d.line([(i,0),(i,6)],fill='yellow');d.line([(0,i),(6,i)],fill='yellow')
cv.save(out)
