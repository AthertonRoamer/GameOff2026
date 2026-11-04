import json, sys
from PIL import Image
# usage: pack_legs.py <rendered dir> <game skin dir> <state> <frames> <fps> <loop 0/1>
src, dst, state, n, fps, loop = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6] == "1"
m = json.load(open(f"{src}/sprites.json"))[state]
size, cols = m["size"], 4
rows = (n + cols - 1) // cols
sheet = Image.new("RGBA", (size*cols, size*rows), (0,0,0,0))
for i in range(n):
    sheet.alpha_composite(Image.open(f"{src}/{state}_{i:02d}.png").convert("RGBA"), ((i % cols)*size, (i // cols)*size))
sheet.save(f"{dst}/{state}.png", optimize=True)
px, py = m["pivot"]
meta = json.load(open(f"{dst}/sprites.json"))
meta[state] = dict(file=f"{state}.png", frames=n, hframes=cols, vframes=rows, frame_size=size, pivot_px=[round(px,1), round(py,1)],
    godot_offset=[round(size/2-px,1), round(size/2-py,1)], fps=fps, loop=loop, px_per_m=m["px_per_m"])
json.dump(meta, open(f"{dst}/sprites.json","w"), indent=1)
print("packed", state, meta[state])
