"""Writes where each death sheet's body ends up into the role's sprites.json (run after pack_trimmed.py): python end_pose.py game\player\skin\guard
For every state starting with "death": end_points (a coarse grid of points on the body in the last frame, relative to where the player stood, in sheet pixels; the
game used to keep these out of walls), end_center (their middle), end_shadow (the body's direction in radians, its length and its width, for the shadow) and end_hull
(the convex outline of every body pixel in the last frame, same units: the game keeps this out of walls)."""
import json, sys
import numpy as np
from PIL import Image

folder = sys.argv[1]
meta = json.load(open(f"{folder}/sprites.json"))
STEP = 24


def convex_hull(points):
    """Andrew's monotone chain: the outline of a set of points, counter-clockwise."""
    pts = sorted(set(map(tuple, points.tolist())))
    def half(seq):
        out = []
        for q in seq:
            while len(out) >= 2 and (out[-1][0] - out[-2][0]) * (q[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (q[0] - out[-2][0]) <= 0:
                out.pop()
            out.append(q)
        return out[:-1]
    return half(pts) + half(pts[::-1])
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
    v["end_hull"] = [[round(float(x), 1), round(float(y), 1)] for x, y in convex_hull(pts)]
    v["end_center"] = [round(float(centre[0]), 1), round(float(centre[1]), 1)]
    v["end_shadow"] = [round(float(np.arctan2(axis[1], axis[0])), 3), round(float(along.max() - along.min()), 1), round(float(across.max() - across.min()), 1)]
    print(name, "points", len(grid), "centre", v["end_center"], "shadow", v["end_shadow"])
json.dump(meta, open(f"{folder}/sprites.json", "w"), indent=1)
