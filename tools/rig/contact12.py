import sys
from PIL import Image
src, name, dst = sys.argv[1], sys.argv[2], sys.argv[3]
ims=[Image.open(f"{src}/{name}_{i:02d}.png").convert("RGBA") for i in range(12)]
s=ims[0].width
sheet=Image.new("RGBA",(s*4,s*3),(200,200,200,255))
for i,im in enumerate(ims): sheet.alpha_composite(im,((i%4)*s,(i//4)*s))
sheet.convert("RGB").save(dst)
