import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
ims = [Image.open(f"{src}/legs_turn_{i:02d}.png").convert("RGBA") for i in range(16)]
s = ims[0].width
sheet = Image.new("RGBA", (s*4, s*4), (200, 200, 200, 255))
for i, im in enumerate(ims):
    sheet.alpha_composite(im, ((i % 4)*s, (i // 4)*s))
sheet.convert("RGB").save(dst)
