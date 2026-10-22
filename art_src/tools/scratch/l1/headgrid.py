import sys
from PIL import Image,ImageDraw
from psd_tools import PSDImage
psd=PSDImage.open(sys.argv[1]);name=sys.argv[2];x0,y0,x1,y1=map(int,sys.argv[3].split(','));z=int(sys.argv[4]);out=sys.argv[5]
cv=Image.new('RGBA',psd.size,(150,150,150,255))
for l in psd:
  if l.name.startswith('_') or not l.visible: continue
  im=l.topil()
  if im: cv.alpha_composite(im.convert('RGBA'),(l.left,l.top))
S=psd.size[0]//int(sys.argv[6]) if len(sys.argv)>6 else 1
c=cv.crop((x0*S,y0*S,x1*S,y1*S)).resize(((x1-x0)*z,(y1-y0)*z),Image.NEAREST);d=ImageDraw.Draw(c)
for x in range(x0,x1):
  if x%5==0:d.line([(x-x0)*z,0,(x-x0)*z,c.height],fill=(255,0,0) if x%10==0 else (255,170,170))
  if x%10==0:d.text(((x-x0)*z+1,1),str(x),fill=(255,255,0))
for y in range(y0,y1):
  if y%5==0:d.line([0,(y-y0)*z,c.width,(y-y0)*z],fill=(0,0,255) if y%10==0 else (170,170,255))
  if y%10==0:d.text((1,(y-y0)*z+1),str(y),fill=(255,255,0))
c.save(out)
