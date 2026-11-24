import glob, sys
from PIL import Image
folder, state, cols, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
x0,y0,x1,y1 = [float(v) for v in sys.argv[5:9]]  # a crop, as fractions of the frame
files = sorted(glob.glob(f"{folder}/{state}_[0-9][0-9].png"))
ims = [Image.open(f).convert("RGBA") for f in files]
w = ims[0].size[0]
box = (int(x0*w), int(y0*w), int(x1*w), int(y1*w))
cw, ch = box[2]-box[0], box[3]-box[1]
rows = (len(ims)+cols-1)//cols
sheet = Image.new("RGBA", (cols*cw, rows*ch), (40,44,52,255))
for i, im in enumerate(ims):
    sheet.alpha_composite(im.crop(box), ((i%cols)*cw, (i//cols)*ch))
sheet.save(out); print(sheet.size)
