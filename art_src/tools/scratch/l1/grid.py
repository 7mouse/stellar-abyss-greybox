import sys
from PIL import Image,ImageDraw
src,out=sys.argv[1],sys.argv[2];x0,y0,x1,y1=map(int,sys.argv[3].split(','));z=float(sys.argv[4]) if len(sys.argv)>4 else 3
im=Image.open(src).convert('RGB').resize((1024,576)).crop((x0,y0,x1,y1));im=im.resize((int((x1-x0)*z),int((y1-y0)*z)),Image.LANCZOS)
dr=ImageDraw.Draw(im)
for x in range((x0//10)*10,x1,10):
  X=(x-x0)*z;dr.line([X,0,X,im.height],fill=(255,0,0) if x%50==0 else (255,180,180),width=1)
  if x%50==0: dr.text((X+2,2),str(x),fill=(200,0,0))
for y in range((y0//10)*10,y1,10):
  Y=(y-y0)*z;dr.line([0,Y,im.width,Y],fill=(0,0,255) if y%50==0 else (180,180,255),width=1)
  if y%50==0: dr.text((2,Y+2),str(y),fill=(0,0,200))
im.save(out)
