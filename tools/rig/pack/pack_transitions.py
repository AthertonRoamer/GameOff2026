"""Packs the transitions between gaits into the game: <layer>_tr_<from>_<to>_<frame> (see _transitions() in anim.py) and the upper body's swing from one side to
the other, torso_flip_<walk|run>_<quarter> (see _flip()). Run by pack_skin.py.
    python pack_transitions.py <rendered dir> <heads.json> <shoulders.json> <the role's skin folder in the game>
heads.json and shoulders.json come from a SHOULDERS=1 render of the same states plus the forward and sideways torso sheets (see pack_skin.py).

A transition goes from the placing and size of one sheet to those of the other (a gait's size is in sheets.py, and an upper body is moved so its head sits where the
forward sheet's does), so every frame is moved and resized by the blend of the two, as its pose is blended in Blender, and baked: a transition's sheet has no "scale"
of its own. A swing to the other side goes from the sheet's placing to its mirror image's."""
import glob, json, os, re, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheets import GAIT_SCALE, HEAD_REFERENCE, TRANSITION_FPS

PX_PER_M = 256 / 1.45
MARGIN = 2
COLS = 4
BIG = 800


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def parse(state):
    """(layer, gait it starts as, gait it ends as, whether it ends on the mirror image) for a rendered state's name."""
    flip = re.match(r"torso_flip_(walk|run)_\d$", state)
    if flip:
        return "torso", "side_" + flip.group(1), "side_" + flip.group(1), True
    layer = state.split("_tr_")[0]
    rest = state[len(layer) + 4:]  # <from>_<to>_<frame>, the gait names having underscores themselves
    for a in GAIT_SCALE:
        if rest.startswith(a + "_"):
            tail = rest[len(a) + 1:]
            for b in GAIT_SCALE:
                if tail.startswith(b + "_") and tail[len(b) + 1:].isdigit():
                    return layer, a, b, False
    raise ValueError("not a transition: " + state)


def main(rendered, heads_file, shoulders_file, skin):
    heads = json.load(open(heads_file))
    shoulders = json.load(open(shoulders_file))
    meta = json.load(open(f"{skin}/sprites.json"))

    def shift_of(gait):
        """How far (sheet pixels, before scaling) an upper body sheet of this gait is moved to put its head where the forward sheet's is."""
        own = "torso_" + gait
        if own not in HEAD_REFERENCE:
            return np.zeros(2)
        return np.array(heads[HEAD_REFERENCE[own]]).mean(axis=0) / GAIT_SCALE[gait] - np.array(heads[own]).mean(axis=0)

    states = {re.sub(r"_\d\d\.png$", "", os.path.basename(f)) for f in glob.glob(f"{rendered}/*_tr_*_[0-9][0-9].png") + glob.glob(f"{rendered}/torso_flip_*_[0-9][0-9].png")}
    for state in sorted(states):
        layer, gait_a, gait_b, mirrored = parse(state)
        files = sorted(glob.glob(f"{rendered}/{state}_[0-9][0-9].png"))
        n = len(files)
        d_a, d_b = (shift_of(gait_a), shift_of(gait_b)) if layer == "torso" else (np.zeros(2), np.zeros(2))
        if mirrored:
            d_b = np.array([-d_a[0], d_a[1]])
        k_a, k_b = GAIT_SCALE[gait_a], GAIT_SCALE[gait_b]
        canvases, ks, shifts = [], [], []
        for i, f in enumerate(files):
            s = smooth((i + 1) / n)
            k = k_a * (1 - s) + k_b * s
            d = d_a * (1 - s) + d_b * s
            im = Image.open(f).convert("RGBA")
            size = im.width
            px, py = size / 2, size / 2 + 0.12 * PX_PER_M
            if abs(k - 1.0) > 1e-3:
                im = im.resize((int(round(size * k)), int(round(size * k))), Image.LANCZOS)
            canvas = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
            canvas.alpha_composite(im, (int(round(BIG / 2 - px * k + k * d[0])), int(round(BIG / 2 - py * k + k * d[1]))))
            canvases.append(canvas)
            ks.append(k)
            shifts.append(d)
        box = None
        for c in canvases:
            b = c.getchannel("A").getbbox()
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        x0, y0, x1, y1 = box[0] - MARGIN, box[1] - MARGIN, box[2] + MARGIN, box[3] + MARGIN
        w, h = x1 - x0, y1 - y0
        rows = (n + COLS - 1) // COLS
        sheet = Image.new("RGBA", (w * COLS, h * rows), (0, 0, 0, 0))
        for i, c in enumerate(canvases):
            sheet.alpha_composite(c.crop((x0, y0, x1, y1)), ((i % COLS) * w, (i // COLS) * h))
        sheet.save(f"{skin}/{state}.png", optimize=True)
        cx = cy = BIG / 2
        entry = dict(file=f"{state}.png", frames=n, hframes=COLS, vframes=rows, frame_size=size, frame_w=w, frame_h=h, pivot_px=[cx, cy],
            godot_offset=[round(x0 + w / 2 - cx, 1), round(y0 + h / 2 - cy, 1)], fps=TRANSITION_FPS, loop=False, px_per_m=round(PX_PER_M, 2))
        if layer == "torso":
            entry["shoulders"] = [[round(ks[i] * (r[0] + shifts[i][0]), 1), round(ks[i] * (r[1] + shifts[i][1]), 1), round(ks[i] * (r[2] + shifts[i][0]), 1),
                round(ks[i] * (r[3] + shifts[i][1]), 1)] for i, r in enumerate(shoulders[state])]
        meta[state] = entry
        print("packed %-34s %d frames %dx%d" % (state, n, w, h))
    json.dump(meta, open(f"{skin}/sprites.json", "w"), indent=1)


if __name__ == "__main__":
    main(*sys.argv[1:5])
