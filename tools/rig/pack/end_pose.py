"""Writes where each death sheet's body ends up into the role's sprites.json (run after pack_trimmed.py): python end_pose.py game\player\skin\guard
For every state starting with "death": end_points (a coarse grid of points on the body in the last frame, relative to where the player stood, in sheet pixels; the
game keeps these out of walls), end_center (their middle) and end_shadow (the body's direction in radians, its length and its width, for the shadow)."""
import json, sys
import numpy as np
from PIL import Image

folder = sys.argv[1]
meta = json.load(open(f"{folder}/sprites.json"))
STEP = 24
for name, v in meta.items():
    if not name.startswith("death"):
        continue
    alpha = np.array(Image.open(f"{folder}/{v['file']}"))[:, :, 3]
    w, h, last = v["frame_w"], v["frame_h"], v["frames"] - 1
    col, row = last % v["hframes"], last // v["hframes"]
    frame = alpha[row * h:(row + 1) * h, col * w:(col + 1) * w] > 20
    ys, xs = np.nonzero(frame)
    ox, oy = v["godot_offset"]
    pts = np.stack([xs - w / 2 + ox, ys - h / 2 + oy], axis=1).astype(float)
    centre = pts.mean(axis=0)
    cov = np.cov((pts - centre).T)
    vals, vecs = np.linalg.eigh(cov)
    axis = vecs[:, 1]
    along = (pts - centre) @ axis
    across = (pts - centre) @ vecs[:, 0]
    grid = {}
    for p in pts:
        grid.setdefault((int(p[0] // STEP), int(p[1] // STEP)), p)
    v["end_points"] = [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in grid.values()]
    v["end_center"] = [round(float(centre[0]), 1), round(float(centre[1]), 1)]
    v["end_shadow"] = [round(float(np.arctan2(axis[1], axis[0])), 3), round(float(along.max() - along.min()), 1), round(float(across.max() - across.min()), 1)]
    print(name, "points", len(grid), "centre", v["end_center"], "shadow", v["end_shadow"])
json.dump(meta, open(f"{folder}/sprites.json", "w"), indent=1)
