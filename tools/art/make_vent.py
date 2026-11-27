"""Draws the floor vent (a ventrat crawls between them) with the furniture's brushes and cel look, to game/abilities/art/vent.png.

Run from the project folder:  python tools/art/make_vent.py
Drawn at 176 px per metre like the furniture (shown at 0.25): a steel grille about 0.55 m square, lying on the floor.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_furniture import silhouette  # noqa: E402
from make_props import shape, new, line, disc, dot, finish, cel  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/abilities/art/vent.png"


def vent(w=96, h=96, pad=20):
    """A steel floor grille: a screwed-down frame, a dark duct under it, and slats tilted so each catches the light along its top edge."""
    img = new(w + pad * 2, h + pad * 2)
    o = pad
    shape(img, "rect", (o, o, o + w, o + h), (138, 148, 162), (78, 86, 102), ang=135, r=7, bev=3.5)  # the frame
    shape(img, "rect", (o + 6, o + 6, o + w - 6, o + h - 6), (108, 117, 132), (88, 96, 112), ang=135, r=5, bev=1.2)  # its raised lip
    inner = (o + 13, o + 13, o + w - 13, o + h - 13)
    shape(img, "rect", inner, (10, 12, 18), (24, 28, 38), ang=90, r=3, bev=2.0, hi=0.12, lo=0.1)  # the duct: dark, deeper at the top
    count = 6
    pitch = (inner[3] - inner[1] - 6) / count
    for k in range(count):
        top = inner[1] + 4 + k * pitch
        shape(img, "rect", (inner[0] + 3, top, inner[2] - 3, top + pitch * 0.58), (150, 160, 174), (82, 90, 106), ang=90, r=2, bev=1.1)  # a slat
        line(img, [(inner[0] + 6, top + 1.4), (inner[2] - 6, top + 1.4)], 1.1, (196, 204, 214), 170)  # light on its edge
        line(img, [(inner[0] + 5, top + pitch * 0.58 + 1.8), (inner[2] - 5, top + pitch * 0.58 + 1.8)], 2.0, (0, 0, 0), 150)  # its shadow in the duct
    mid = o + w / 2
    shape(img, "rect", (mid - 3, inner[1] + 1, mid + 3, inner[3] - 1), (126, 136, 150), (74, 82, 98), ang=0, r=2, bev=1.0)  # the centre brace
    for sx in (o + 7.5, o + w - 7.5):
        for sy in (o + 7.5, o + h - 7.5):
            disc(img, sx, sy, 4.2, (176, 182, 192), (92, 98, 112), bev=1.0)  # a screw
            line(img, [(sx - 2.4, sy - 1.4), (sx + 2.4, sy + 1.4)], 1.3, (40, 44, 56), 230)  # and its slot
    for x, y, r in ((o + 30, o + 7, 1.6), (o + w - 22, o + h - 8, 2.2), (o + 8, o + 61, 1.4)):
        dot(img, x, y, r, (104, 74, 52), 150)  # a little rust
    return finish(img)


if __name__ == "__main__":
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sprite, size = silhouette(cel(vent()))
    sprite.save(OUT)
    print(OUT, sprite.size, "body", size)
