import glob, json, os, re, sys
from PIL import Image

# usage: pack_trimmed.py <rendered dir> <game skin dir> <fps> <loop 0/1> <state or rendered_state=game_state> [...]
# (rendered_state=game_state packs a rendered state under another name in the game, e.g. a state rendered under another name)
# Each sheet is cut down to the area its frames really use (the same box for every frame of the state, plus a small margin), so a
# frame that is mostly empty costs only what it fills in video memory. The entry gets frame_w and frame_h (the cropped frame) next to frame_size (the
# frame that was rendered), and godot_offset is worked out for the cropped frame, so the character's position still sits on the node origin.
# The rendered dir's sprites.json is not needed: every state has its pivot at the same place in its frame (a state the renderer wrote down, like a fall, has its own).
# Run by pack_skin.py.
src, dst, fps, loop = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "1"
states = sys.argv[5:]
PX_PER_M = 256 / 1.45
MARGIN = 2
COLS = 4
meta = json.load(open(f"{dst}/sprites.json"))
rendered_meta = json.load(open(f"{src}/sprites.json")) if os.path.exists(f"{src}/sprites.json") else {}
for spec in states:
    rendered, _, state = spec.partition("=")
    state = state or rendered
    files = sorted(glob.glob(f"{src}/{rendered}_[0-9][0-9].png"))
    frames = [Image.open(f).convert("RGBA") for f in files]
    size = frames[0].width
    box = None
    for im in frames:
        b = im.getchannel("A").getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    x0, y0 = max(box[0] - MARGIN, 0), max(box[1] - MARGIN, 0)
    x1, y1 = min(box[2] + MARGIN, size), min(box[3] + MARGIN, size)
    w, h = x1 - x0, y1 - y0
    n = len(frames)
    rows = (n + COLS - 1) // COLS
    sheet = Image.new("RGBA", (w * COLS, h * rows), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        sheet.alpha_composite(im.crop((x0, y0, x1, y1)), ((i % COLS) * w, (i // COLS) * h))
    sheet.save(f"{dst}/{state}.png", optimize=True)
    px, py = size / 2, size / 2 + 0.12 * PX_PER_M  # the character's position in the rendered frame (the camera sits 0.12 m off centre)
    if rendered in rendered_meta: #a state the renderer wrote down (a lying body is not centred like the rest): its own pivot
        px, py = rendered_meta[rendered]["pivot"]
    meta[state] = dict(file=f"{state}.png", frames=n, hframes=COLS, vframes=rows, frame_size=size, frame_w=w, frame_h=h,
        pivot_px=[round(px, 1), round(py, 1)], godot_offset=[round(x0 + w / 2 - px, 1), round(y0 + h / 2 - py, 1)], fps=fps, loop=loop, px_per_m=round(PX_PER_M, 2))
    print("packed %-26s %d frames %dx%d (of %d)" % (state, n, w, h, size))
json.dump(meta, open(f"{dst}/sprites.json", "w"), indent=1)
