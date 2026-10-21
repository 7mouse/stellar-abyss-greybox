import sys,numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage as nd
src=sys.argv[1];out=sys.argv[2];ds=1.25
rgb=np.array(Image.open(src).convert('RGB')).astype(int)
d=255-rgb.min(2)
fg=nd.binary_fill_holes(nd.binary_closing(d>28,iterations=2))
lab,n=nd.label(fg)
im=Image.open(src).convert('RGB').resize((1024,576));dr=ImageDraw.Draw(im)
for i,sl in enumerate(nd.find_objects(lab)):
  area=(lab[sl]==i+1).sum()
  if area<150: continue
  y0,y1=sl[0].start/ds,sl[0].stop/ds;x0,x1=sl[1].start/ds,sl[1].stop/ds
  print(i+1,[round(x0),round(y0),round(x1),round(y1)],int(area))
  dr.rectangle([x0,y0,x1,y1],outline=(255,0,0));dr.text((x0+2,y0+2),str(i+1),fill=(255,0,0))
im.save(out)
