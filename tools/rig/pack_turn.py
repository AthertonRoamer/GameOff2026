import json, sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
n, cols = 16, 4
size = json.load(open(f"{src}/sprites.json"))["legs_turn"]["size"]
sheet = Image.new("RGBA", (size*cols, size*((n+cols-1)//cols)), (0,0,0,0))
for i in range(n):
    sheet.alpha_composite(Image.open(f"{src}/legs_turn_{i:02d}.png").convert("RGBA"), ((i % cols)*size, (i // cols)*size))
sheet.save(f"{dst}/legs_turn.png", optimize=True)
m = json.load(open(f"{src}/sprites.json"))["legs_turn"]
px, py = m["pivot"]
meta = json.load(open(f"{dst}/sprites.json"))
meta["legs_turn"] = dict(file="legs_turn.png", frames=n, hframes=cols, vframes=(n+cols-1)//cols, frame_size=size,
    pivot_px=[round(px,1), round(py,1)], godot_offset=[round(size/2-px,1), round(size/2-py,1)], fps=16, loop=False, px_per_m=m["px_per_m"])
json.dump(meta, open(f"{dst}/sprites.json","w"), indent=1)
print("packed", meta["legs_turn"])
