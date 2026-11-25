"""Builds the map's furniture: draws every prop (the ones in make_props.py and the new ones below), gives them the characters' cel look, trims each to its
silhouette and writes, for the game:

    game/furniture/art/<name>.png        the sprite (176 px per metre, so the map draws it at 0.25)
    game/furniture/items/<name>.tscn     a Furniture scene: sprite, footprint (collision) and what blocks light, ready to drag into the map
    tools/art/furniture_manifest.json    sizes and footprints (used to lay rooms out)

Run from the project folder:  python tools/art/make_furniture.py
A prop whose front matters (desks, couches, cabinets...) is drawn with its front at the top and also saved turned to face east, south and west
(name_n, name_e, name_s, name_w). To add a prop: write a draw function below (or draw a PNG yourself), add it to ITEMS, and run this.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_props as P  # noqa: E402
from make_props import S, new, shape, disc, line, dot, poly, text, hazard_band, finish, cel  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ART_DIR = ROOT / "game/furniture/art"
ITEM_DIR = ROOT / "game/furniture/items"
MARGIN = 16  # px of room round the silhouette for its soft shadow
ART_SCALE = 0.25  # the map draws 176 px/m art at 44 px/m

# ---------------------------------------------------------------- colours (natural, kept inside the game's navy / steel / wood palette)
WOOD = ((168, 124, 80), (128, 90, 56))
WOOD_DARK = ((120, 86, 56), (88, 60, 38))
LAMINATE = ((158, 146, 126), (122, 112, 96))
STEEL = ((132, 142, 156), (84, 92, 106))
STEEL_DARK = ((92, 100, 114), (54, 60, 72))
WHITE = ((192, 196, 202), (136, 142, 152))
FABRIC = ((74, 86, 118), (46, 54, 78))
FABRIC_OLIVE = ((94, 104, 74), (60, 68, 48))
GLASS = ((46, 70, 82), (22, 32, 40))
SCREEN = ((88, 150, 168), (40, 78, 92))


def _canvas(w, h, pad=20):
    return new(w + pad * 2, h + pad * 2), pad


# ---------------------------------------------------------------- new props (front at the top)

def desk(w=330, h=165, monitors=1):
    """An office desk seen from above: laminate top, a monitor at the back, keyboard, mouse, papers and a mug. The user sits at the bottom edge."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), *LAMINATE, ang=90, r=5, bev=3.5)
    shape(img, "rect", (o + 5, o + 5, o + w - 5, o + h - 5), (146, 134, 114), (126, 116, 98), ang=90, r=3, bev=1.5)
    mw = 78 if monitors == 1 else 70
    for i in range(monitors):
        cx = o + w / 2 + (i - (monitors - 1) / 2) * (mw + 14)
        shape(img, "rect", (cx - mw / 2, o + 18, cx + mw / 2, o + 30), (40, 44, 54), (20, 22, 28), bev=1.5, r=2)  # the monitor seen from above: a thin dark slab
        shape(img, "rect", (cx - 8, o + 30, cx + 8, o + 48), (56, 62, 74), (30, 34, 42), bev=1, r=2)  # its stand
        line(img, [(cx - mw / 2 + 4, o + 21), (cx + mw / 2 - 4, o + 21)], 1.6, SCREEN[0], 190)  # glow on the top edge
    kx = o + w / 2
    shape(img, "rect", (kx - 44, o + h - 70, kx + 44, o + h - 46), (60, 66, 78), (34, 38, 48), bev=1.5, r=3)  # keyboard
    for k in range(5):
        line(img, [(kx - 38, o + h - 64 + k * 4.4), (kx + 38, o + h - 64 + k * 4.4)], 1.2, (24, 26, 32), 170)
    shape(img, "rect", (kx + 60, o + h - 66, kx + 74, o + h - 46), (60, 66, 78), (34, 38, 48), bev=1, r=6)  # mouse
    shape(img, "rect", (o + 22, o + h - 78, o + 70, o + h - 38), (226, 224, 214), (190, 188, 178), bev=1, r=1, rot=-6)  # papers
    for k in range(3):
        line(img, [(o + 30, o + h - 70 + k * 9), (o + 60, o + h - 68 + k * 9)], 1.1, (110, 110, 120), 150)
    disc(img, o + w - 34, o + h - 54, 11, (230, 230, 226), (150, 152, 158), bev=1.5)  # a mug
    disc(img, o + w - 34, o + h - 54, 7, (60, 40, 28), (40, 26, 18), bev=0)
    return finish(img)


def chair_office(size=108):
    """A swivel chair from above: a round seat, a curved back at the bottom, two arms, the star base showing."""
    img, o = _canvas(size, size, 14)
    c = o + size / 2
    for a in range(5):  # base star
        ang = math.radians(a * 72 + 18)
        line(img, [(c, c), (c + math.cos(ang) * size * 0.46, c + math.sin(ang) * size * 0.46)], 6, (36, 40, 48))
        dot(img, c + math.cos(ang) * size * 0.46, c + math.sin(ang) * size * 0.46, 5, (22, 24, 30))
    for sx in (-1, 1):  # arms
        shape(img, "rect", (c + sx * size * 0.4 - 5, c - 18, c + sx * size * 0.4 + 5, c + 22), (50, 56, 70), (28, 32, 42), bev=1.2, r=4)
    disc(img, c, c - 4, size * 0.34, (86, 98, 130), (44, 52, 76), bev=2.5, power=1.1)  # seat
    shape(img, "rect", (c - size * 0.36, c + size * 0.3, c + size * 0.36, c + size * 0.46), (66, 76, 104), (36, 42, 62), bev=2, r=8)  # back
    return finish(img)


def chair_plain(size=92):
    """A plain canteen chair: square seat, back bar at the bottom, four legs at the corners."""
    img, o = _canvas(size, size, 14)
    shape(img, "rect", (o + 6, o + 4, o + size - 6, o + size - 22), (140, 100, 64), (104, 72, 44), bev=2.5, r=5)
    shape(img, "rect", (o + 6, o + size - 20, o + size - 6, o + size - 6), (110, 78, 48), (80, 56, 34), bev=2, r=4)
    for x in (o + 8, o + size - 14):
        for y in (o + 6, o + size - 26):
            shape(img, "rect", (x, y, x + 6, y + 6), (60, 66, 78), (30, 34, 44), bev=0.8, r=1)
    return finish(img)


def table_rect(w=352, h=176):
    """A canteen table: wood top with a darker edge band and a worn centre."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (120, 86, 56), (88, 60, 38), ang=90, r=6, bev=3.5)
    shape(img, "rect", (o + 8, o + 8, o + w - 8, o + h - 8), (174, 130, 86), (140, 100, 64), ang=90, r=3, bev=1.5)
    for k in range(5):
        line(img, [(o + 20, o + 28 + k * (h - 56) / 4), (o + w - 20, o + 28 + k * (h - 56) / 4)], 1.2, (100, 70, 44), 90)
    return finish(img)


def table_round(size=200):
    """A small round table with a pedestal ring."""
    img, o = _canvas(size, size)
    c = o + size / 2
    disc(img, c, c, size / 2, (120, 86, 56), (84, 58, 36), bev=3, power=1.2)
    disc(img, c, c, size / 2 - 9, (174, 130, 86), (130, 94, 60), bev=2, power=1.1)
    disc(img, c, c, 12, (92, 100, 114), (50, 56, 68), bev=1.5)
    return finish(img)


def couch(w=396, h=176):
    """A fabric couch from above: the back along the bottom, two arms, three seat cushions."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o + 6, o + w, o + h), *FABRIC, ang=90, r=18, bev=3.5)
    shape(img, "rect", (o + 6, o + h - 50, o + w - 6, o + h - 2), (60, 70, 100), (36, 42, 64), ang=90, r=14, bev=2.5)  # backrest
    for sx in (o, o + w - 46):
        shape(img, "rect", (sx, o + 12, sx + 46, o + h - 30), (66, 78, 110), (40, 48, 70), ang=0, r=16, bev=3)  # arms
    cw = (w - 92 - 8) / 3
    for i in range(3):
        x0 = o + 46 + i * (cw + 4)
        shape(img, "rect", (x0, o + 18, x0 + cw, o + h - 52), (88, 102, 138), (54, 64, 92), ang=90, r=10, bev=3)
        dot(img, x0 + cw / 2, o + 62, 3, (36, 42, 62))  # button
    return finish(img)


def locker_bank(w=240, h=124):
    """Three steel lockers seen from above; the doors face the top: louvres and a handle on each."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (116, 128, 146), (74, 84, 100), ang=90, r=4, bev=3.5)
    shape(img, "rect", (o + 4, o + 16, o + w - 4, o + h - 4), (124, 136, 154), (96, 108, 126), ang=90, r=2, bev=1.5)  # the flat top
    uw = w / 3
    for i in range(3):
        x0 = o + i * uw
        if i:
            line(img, [(x0, o + 2), (x0, o + h - 2)], 2.4, (36, 42, 54), 220)
        for k in range(4):  # louvres on the door's face
            line(img, [(x0 + 16, o + 3 + k * 3.2), (x0 + uw - 16, o + 3 + k * 3.2)], 1.3, (30, 36, 46), 210)
        shape(img, "rect", (x0 + uw - 22, o + 4, x0 + uw - 12, o + 13), (200, 204, 212), (110, 116, 128), bev=0.8, r=1)
    return finish(img)


def vending(w=198, h=176):
    """A drinks and snacks machine from above: dark body, its lit glass front along the top edge, a coin panel at one end."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (70, 78, 96), (40, 46, 60), ang=90, r=4, bev=3.5)
    shape(img, "rect", (o + 6, o + 22, o + w - 6, o + h - 6), (80, 88, 106), (56, 62, 78), ang=90, r=3, bev=1.5)
    shape(img, "rect", (o + 8, o + 4, o + w - 52, o + 18), *SCREEN, ang=90, bev=1.5, r=2)  # glass front
    for k in range(7):
        line(img, [(o + 14 + k * 20, o + 5), (o + 14 + k * 20, o + 17)], 1.2, (22, 34, 40), 180)
    shape(img, "rect", (o + w - 46, o + 4, o + w - 8, o + 18), (50, 56, 70), (30, 34, 44), bev=1.2, r=2)  # panel
    dot(img, o + w - 36, o + 11, 2.2, (110, 200, 150))
    dot(img, o + w - 24, o + 11, 2.2, (170, 170, 176))
    text(img, o + w / 2, o + h / 2 + 10, "DRINKS", 22, (170, 184, 204))
    return finish(img)


def fridge(w=176, h=165):
    """A tall steel-white fridge from above: handles down the front edge, vents at the back."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), *WHITE, ang=135, r=5, bev=3.5)
    shape(img, "rect", (o + 6, o + 16, o + w - 6, o + h - 6), (178, 184, 192), (150, 158, 170), ang=135, r=3, bev=1.5)
    for sx in (o + w * 0.18, o + w * 0.82):
        shape(img, "rect", (sx - 3, o + 3, sx + 3, o + 13), (90, 96, 108), (50, 54, 64), bev=0.8, r=1)
    for k in range(6):
        line(img, [(o + 24, o + h - 24 + k * 3 - 14), (o + w - 24, o + h - 24 + k * 3 - 14)], 1.1, (110, 116, 128), 120)
    return finish(img)


def filing_cabinet(w=112, h=132):
    """A grey filing cabinet from above: three drawer handles along the front."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (126, 134, 146), (82, 90, 104), ang=135, r=3, bev=3)
    shape(img, "rect", (o + 4, o + 14, o + w - 4, o + h - 4), (134, 142, 154), (108, 116, 130), ang=135, r=2, bev=1.2)
    shape(img, "rect", (o + 14, o + 4, o + w - 14, o + 10), (196, 202, 210), (120, 126, 138), bev=0.8, r=1)  # handle strip
    return finish(img)


def electrical_cabinet(w=198, h=88):
    """A wall electrical cabinet from above: a grey box, the louvred door along the front, a hazard strip on top."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (92, 100, 114), (56, 62, 76), ang=135, r=3, bev=3.5)
    shape(img, "rect", (o + 5, o + 18, o + w - 5, o + h - 5), (100, 108, 122), (76, 84, 98), ang=135, r=2, bev=1.2)
    hazard_band(img, (o + 5, o + 4, o + w - 5, o + 12), (150, 156, 166), (24, 24, 26), 9)
    for k in range(3):
        dot(img, o + 30 + k * (w - 60) / 2, o + 40, 3.4, (34, 38, 48))
    return finish(img)


def workbench(w=352, h=154):
    """A steel workbench from above: a wood top, a vice at one corner, tools laid out."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), *STEEL_DARK, ang=90, r=3, bev=3.5)
    shape(img, "rect", (o + 6, o + 6, o + w - 6, o + h - 6), (156, 116, 76), (120, 86, 54), ang=90, r=2, bev=1.5)
    shape(img, "rect", (o + 16, o + 14, o + 58, o + 46), (60, 66, 78), (32, 36, 46), bev=2, r=3)  # vice
    shape(img, "rect", (o + 28, o + 8, o + 46, o + 16), (92, 100, 114), (50, 56, 68), bev=1, r=1)
    line(img, [(o + 110, o + 46), (o + 190, o + 50)], 6, (140, 148, 160))  # a wrench
    dot(img, o + 106, o + 45, 8, (140, 148, 160))
    dot(img, o + 106, o + 45, 4, (70, 52, 36))
    shape(img, "rect", (o + 220, o + 30, o + 300, o + 70), (60, 66, 78), (34, 38, 48), bev=1.5, r=3)  # tool tray
    line(img, [(o + 230, o + 50), (o + 290, o + 50)], 1.2, (20, 22, 28), 160)
    shape(img, "rect", (o + w - 100, o + h - 62, o + w - 34, o + h - 24), (206, 200, 186), (170, 164, 150), bev=1, r=1, rot=8)  # plans
    return finish(img)


def bench(w=308, h=88):
    """A long wooden bench from above: slats with steel ends."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o + 8, o + 6, o + w - 8, o + h - 6), (96, 70, 46), (70, 50, 32), r=2, bev=1.5)
    for k in range(3):
        shape(img, "rect", (o + 4, o + 6 + k * (h - 12) / 3, o + w - 4, o + 6 + (k + 1) * (h - 12) / 3 - 3), (170, 128, 84), (126, 90, 58), ang=90, r=2, bev=2)
    for x in (o + 14, o + w - 22):
        shape(img, "rect", (x, o, x + 8, o + h), (70, 78, 94), (38, 44, 58), bev=1.5, r=1)
    return finish(img)


def bin_round(size=88):
    """A round bin from above: a grey drum with a pushed-in lid and a ring."""
    img, o = _canvas(size, size, 14)
    c = o + size / 2
    disc(img, c, c, size / 2, (112, 120, 134), (56, 62, 76), bev=3, power=1.2)
    disc(img, c, c, size / 2 - 8, (92, 100, 114), (66, 72, 86), bev=2, power=1.0)
    disc(img, c, c, 10, (40, 44, 54), (22, 24, 30), bev=1)
    return finish(img)


def plant(size=104):
    """A potted plant from above: leaves fanned out round a dark pot."""
    img, o = _canvas(size, size, 14)
    c = o + size / 2
    disc(img, c, c, size * 0.3, (84, 62, 48), (50, 36, 28), bev=2, power=1.1)
    greens = ((96, 124, 78), (62, 88, 56))
    for k in range(9):
        ang = math.radians(k * 40 + 10)
        tip = (c + math.cos(ang) * size * 0.46, c + math.sin(ang) * size * 0.46)
        mid = (c + math.cos(ang + 0.35) * size * 0.28, c + math.sin(ang + 0.35) * size * 0.28)
        mid2 = (c + math.cos(ang - 0.35) * size * 0.28, c + math.sin(ang - 0.35) * size * 0.28)
        poly(img, [(c, c), mid, tip, mid2], fill=greens[k % 2] + (255,), outline=(36, 54, 34, 255), width=1.4)
    disc(img, c, c, 8, (126, 154, 100), (70, 96, 60), bev=1)
    return finish(img)


def generator_unit(w=330, h=242):
    """A standby generator: a heavy olive housing, a big fan, exhaust stacks and a control strip along the front."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (92, 100, 82), (56, 62, 50), ang=135, r=8, bev=4)
    shape(img, "rect", (o + 8, o + 30, o + w - 8, o + h - 8), (104, 112, 94), (78, 86, 68), ang=135, r=5, bev=2)
    fx, fy = o + w * 0.34, o + h * 0.58
    disc(img, fx, fy, 72, (150, 158, 166), (60, 66, 76), bev=3, power=1.1)
    disc(img, fx, fy, 62, (40, 44, 52), (24, 26, 32), bev=0)
    for k in range(6):  # fan blades
        a = math.radians(k * 60 + 12)
        poly(img, [(fx, fy), (fx + math.cos(a - 0.3) * 56, fy + math.sin(a - 0.3) * 56), (fx + math.cos(a + 0.3) * 56, fy + math.sin(a + 0.3) * 56)], fill=(84, 92, 104, 255), outline=(20, 22, 28, 255), width=1.2)
    disc(img, fx, fy, 12, (160, 166, 176), (80, 86, 98), bev=1.5)
    for ex in (o + w * 0.72, o + w * 0.88):  # exhaust stacks
        disc(img, ex, o + h * 0.45, 22, (150, 156, 164), (62, 68, 80), bev=2.5, power=1.1)
        disc(img, ex, o + h * 0.45, 13, (24, 26, 30), (14, 16, 20), bev=0)
    shape(img, "rect", (o + 14, o + 8, o + w - 14, o + 24), (44, 50, 60), (26, 30, 38), bev=1.5, r=2)  # control strip
    for k in range(4):
        dot(img, o + 34 + k * 26, o + 16, 3, (110, 190, 150) if k == 0 else (170, 172, 178))
    return finish(img)


def safe_box(size=154):
    """A heavy steel safe from above: a big dial on a dark lid and a handle bar."""
    img, o = _canvas(size, size)
    c = o + size / 2
    shape(img, "rect", (o, o, o + size, o + size), (82, 88, 100), (44, 50, 62), ang=135, r=6, bev=4)
    shape(img, "rect", (o + 10, o + 22, o + size - 10, o + size - 10), (92, 98, 112), (62, 68, 82), ang=135, r=4, bev=2)
    disc(img, c, c + 6, 36, (150, 156, 168), (60, 66, 78), bev=3, power=1.1)
    disc(img, c, c + 6, 26, (36, 40, 48), (22, 24, 30), bev=1.5)
    for k in range(12):
        a = math.radians(k * 30)
        line(img, [(c + math.cos(a) * 20, c + 6 + math.sin(a) * 20), (c + math.cos(a) * 25, c + 6 + math.sin(a) * 25)], 1.4, (190, 196, 206))
    line(img, [(c - 14, c + 6), (c + 14, c + 6)], 5, (176, 182, 194))
    shape(img, "rect", (o + size - 32, o + 8, o + size - 14, o + 18), (180, 186, 198), (100, 106, 118), bev=1, r=1)
    return finish(img)


def counter(w=396, h=132, sink=False):
    """A kitchen counter: a pale laminate top, a steel sink with a tap (when `sink`), the front edge at the top."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (150, 154, 160), (108, 112, 122), ang=90, r=4, bev=3.5)
    shape(img, "rect", (o + 6, o + 14, o + w - 6, o + h - 6), (178, 180, 184), (152, 156, 162), ang=90, r=3, bev=1.5)
    if sink:
        shape(img, "rect", (o + w * 0.55, o + 28, o + w * 0.55 + 100, o + h - 20), (78, 86, 100), (40, 46, 58), bev=2.5, r=6)
        shape(img, "rect", (o + w * 0.55 + 8, o + 36, o + w * 0.55 + 92, o + h - 28), (110, 120, 136), (70, 78, 92), bev=1.5, r=4)
        dot(img, o + w * 0.55 + 50, o + h - 24, 5, (190, 196, 206))
        line(img, [(o + w * 0.55 + 50, o + h - 24), (o + w * 0.55 + 50, o + h - 8)], 4, (170, 176, 188))
    else:
        for k in range(3):
            shape(img, "rect", (o + 30 + k * (w - 60) / 3, o + 26, o + 30 + (k + 0.82) * (w - 60) / 3, o + h - 22), (186, 188, 192), (160, 164, 170), bev=1, r=3)
    return finish(img)


def bed(w=198, h=440):
    """A single bed from above, head at the top: a steel frame, pale sheet, a pillow and a folded olive blanket over the lower part."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (70, 78, 92), (40, 46, 58), ang=90, r=6, bev=3.5)  # frame
    shape(img, "rect", (o + 10, o + 22, o + w - 10, o + h - 8), (186, 192, 204), (150, 158, 174), ang=90, r=8, bev=2.5)  # mattress and sheet
    shape(img, "rect", (o + 26, o + 34, o + w - 26, o + 100), (226, 228, 232), (190, 194, 204), ang=90, r=14, bev=2.5)  # pillow
    shape(img, "rect", (o + 10, o + 150, o + w - 10, o + h - 8), *FABRIC_OLIVE, ang=90, r=8, bev=3)  # blanket
    line(img, [(o + 12, o + 166), (o + w - 12, o + 166)], 2.4, (44, 52, 34), 200)  # the fold
    line(img, [(o + 12, o + 169), (o + w - 12, o + 169)], 1.4, (150, 162, 120), 160)
    return finish(img)


def server_rack(w=132, h=220):
    """A server cabinet from above, its front along the top edge: a vented black top and a row of status lights."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (58, 64, 78), (30, 34, 44), ang=135, r=3, bev=3.5)
    shape(img, "rect", (o + 6, o + 18, o + w - 6, o + h - 6), (50, 56, 70), (34, 38, 50), ang=135, r=2, bev=1.5)
    for k in range(6):
        line(img, [(o + 18, o + 40 + k * 26), (o + w - 18, o + 40 + k * 26)], 5, (20, 22, 28), 220)  # vent slots
        line(img, [(o + 18, o + 38 + k * 26), (o + w - 18, o + 38 + k * 26)], 1.2, (110, 118, 134), 120)
    for k in range(5):
        dot(img, o + 18 + k * 24, o + 9, 3, (110, 200, 150) if k % 2 == 0 else (90, 150, 168))
    return finish(img)


def table_conference(w=660, h=264):
    """A long meeting table: dark wood with a lighter inlay and two cable ports down the middle."""
    img, o = _canvas(w, h)
    shape(img, "rect", (o, o, o + w, o + h), (104, 74, 48), (74, 52, 32), ang=90, r=18, bev=4)
    shape(img, "rect", (o + 14, o + 14, o + w - 14, o + h - 14), (150, 108, 70), (118, 84, 54), ang=90, r=12, bev=2)
    shape(img, "rect", (o + 60, o + h / 2 - 22, o + w - 60, o + h / 2 + 22), (126, 90, 58), (100, 70, 44), ang=90, r=8, bev=1.5)
    for x in (o + w * 0.35, o + w * 0.65):
        shape(img, "rect", (x - 16, o + h / 2 - 8, x + 16, o + h / 2 + 8), (40, 44, 54), (22, 24, 30), bev=1, r=3)
    return finish(img)


# ---------------------------------------------------------------- the list: name -> (draw function, footprint kind, solid, which turns to make)
# footprint: "rect" or "circle" fitted to the silhouette, or "none" (lies on the floor, no collision). turns: also write name_e/_s/_w (front faces east/south/west)
ITEMS = {
    # the props of make_props.py
    "barrel_navy": (lambda: P.barrel((66, 78, 98), (205, 205, 200), seed=1), "circle", True, False),
    "barrel_olive": (lambda: P.barrel((92, 100, 70), None, seed=2), "circle", True, False),
    "barrel_rust": (lambda: P.barrel((122, 84, 60), None, seed=3), "circle", True, False),
    "drum_plastic": (lambda: P.plastic_drum(), "circle", True, False),
    "keg": (lambda: P.keg(), "circle", True, False),
    "tyre": (lambda: P.tire(), "circle", True, False),
    "gas_bottle_olive": (lambda: P.gas_cylinder((84, 98, 70), size=96), "circle", True, False),
    "gas_bottle_steel": (lambda: P.gas_cylinder((150, 156, 166), size=96), "circle", True, False),
    "tote_black": (lambda: P.black_tote(), "rect", True, False),
    "chest_steel": (lambda: P.metal_cabinet(), "rect", True, False),
    "crate_wood": (lambda: P.wood_crate(), "rect", True, False),
    "box_cardboard": (lambda: P.cardboard(), "rect", True, False),
    "box_stack": (lambda: P.box_stack(), "rect", True, False),
    "pallet": (lambda: P.pallet(), "none", False, False),
    "pallet_jack": (lambda: P.pallet_jack(), "none", False, True),
    "rack_double": (lambda: P.rack(2), "rect", True, True),
    "rack_single": (lambda: P.rack(1), "rect", True, True),
    # new
    "desk": (lambda: desk(), "rect", True, True),
    "desk_monitors": (lambda: desk(w=440, h=165, monitors=3), "rect", True, True),
    "chair_office": (lambda: chair_office(), "circle", True, True),
    "chair_plain": (lambda: chair_plain(), "rect", True, True),
    "table_rect": (lambda: table_rect(), "rect", True, False),
    "table_round": (lambda: table_round(), "circle", True, False),
    "couch": (lambda: couch(), "rect", True, True),
    "locker_bank": (lambda: locker_bank(), "rect", True, True),
    "vending": (lambda: vending(), "rect", True, True),
    "fridge": (lambda: fridge(), "rect", True, True),
    "filing_cabinet": (lambda: filing_cabinet(), "rect", True, True),
    "electrical_cabinet": (lambda: electrical_cabinet(), "rect", True, True),
    "workbench": (lambda: workbench(), "rect", True, True),
    "bench": (lambda: bench(), "rect", True, True),
    "bin": (lambda: bin_round(), "circle", True, False),
    "plant": (lambda: plant(), "circle", True, False),
    "generator": (lambda: generator_unit(), "rect", True, True),
    "safe": (lambda: safe_box(), "rect", True, True),
    "counter": (lambda: counter(), "rect", True, True),
    "counter_sink": (lambda: counter(sink=True), "rect", True, True),
    "bed": (lambda: bed(), "rect", True, True),
    "server_rack": (lambda: server_rack(), "rect", True, True),
    "table_conference": (lambda: table_conference(), "rect", True, False),
}

DISPLAY = {"barrel_navy": "Steel drum (navy)", "barrel_olive": "Steel drum (olive)", "barrel_rust": "Old drum", "drum_plastic": "Plastic drum", "keg": "Keg",
    "tyre": "Tyre", "gas_bottle_olive": "Gas bottle (olive)", "gas_bottle_steel": "Gas bottle (steel)", "tote_black": "Tote", "chest_steel": "Steel chest",
    "crate_wood": "Wooden crate", "box_cardboard": "Cardboard box", "box_stack": "Stacked boxes", "pallet": "Pallet", "pallet_jack": "Pallet jack",
    "rack_double": "Racking (2 bays)", "rack_single": "Racking (1 bay)", "desk": "Desk", "desk_monitors": "Desk with three monitors", "chair_office": "Office chair",
    "chair_plain": "Chair", "table_rect": "Table", "table_round": "Round table", "couch": "Couch", "locker_bank": "Lockers", "vending": "Vending machine",
    "fridge": "Fridge", "filing_cabinet": "Filing cabinet", "electrical_cabinet": "Electrical cabinet", "workbench": "Workbench", "bench": "Bench", "bin": "Bin",
    "plant": "Plant", "generator": "Generator", "safe": "Safe", "counter": "Counter", "counter_sink": "Counter with sink", "bed": "Bed", "server_rack": "Server rack", "table_conference": "Conference table"}
# how tall each piece is, in metres: it decides which shadows fall on it (see LightLayers: LOW under 0.6, MID under 1.5, TALL above; 0 lies flat)
HEIGHT = {"barrel_navy": 0.9, "barrel_olive": 0.9, "barrel_rust": 0.9, "drum_plastic": 0.9, "keg": 0.55, "tyre": 0.3, "gas_bottle_olive": 1.3, "gas_bottle_steel": 1.3,
    "tote_black": 0.35, "chest_steel": 0.5, "crate_wood": 1.0, "box_cardboard": 0.4, "box_stack": 0.8, "pallet": 0.0, "pallet_jack": 0.0, "rack_double": 2.3, "rack_single": 2.3,
    "desk": 0.75, "desk_monitors": 0.75, "chair_office": 0.5, "chair_plain": 0.45, "table_rect": 0.75, "table_round": 0.75, "couch": 0.85, "locker_bank": 1.9, "vending": 1.8,
    "fridge": 1.7, "filing_cabinet": 1.3, "electrical_cabinet": 1.9, "workbench": 0.9, "bench": 0.45, "bin": 0.55, "plant": 0.55, "generator": 1.2, "safe": 1.0,
    "counter": 0.9, "counter_sink": 0.9, "bed": 0.5, "server_rack": 2.0, "table_conference": 0.75}

TURN_NAMES = {0: "n", 90: "e", 180: "s", 270: "w"}  # the way the front faces (the art is drawn facing north)


def silhouette(img):
    """Tightly trims a cel sprite to its body (the ink included, the shadow not), then gives it a margin all round, so the body sits in the middle of the texture.
    Returns the new image and the body's size in texture pixels."""
    a = np.asarray(img)
    body = a[..., 3] >= 250
    ys, xs = np.where(body)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    x0, x1, y0, y1 = int(x0), int(x1), int(y0), int(y1)
    w, h = x1 - x0, y1 - y0
    out = Image.new("RGBA", (w + MARGIN * 2, h + MARGIN * 2), (0, 0, 0, 0))
    src = img.crop((x0 - MARGIN, y0 - MARGIN, x1 + MARGIN, y1 + MARGIN))  # (PIL pads outside the image with transparent)
    out.alpha_composite(src)
    return out, (w, h)


def scene_text(name, base, display, solid, kind, size, w_px, h_px):
    fp = {"none": 0, "rect": 1, "circle": 2}[kind]
    lines = [
        '[gd_scene format=3]', '',
        '[ext_resource type="Script" path="res://game/furniture/furniture.gd" id="1_script"]',
        f'[ext_resource type="Texture2D" path="res://game/furniture/art/{name}.png" id="2_art"]', '',
        f'[node name="{"".join(p.capitalize() for p in name.split("_"))}" type="StaticBody2D"]',
        'script = ExtResource("1_script")',
        f'display_name = "{display}"',
        'texture = ExtResource("2_art")',
    ]
    if fp != 1:
        lines.append(f'footprint = {fp}')
    lines.append(f'footprint_size = Vector2({size[0]:.2f}, {size[1]:.2f})')
    lines.append(f'height = {HEIGHT[base]}')
    return "\n".join(lines) + "\n"


def main():
    ART_DIR.mkdir(parents=True, exist_ok=True)
    ITEM_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for base, (draw, kind, solid, turns) in ITEMS.items():
        flat = draw()
        for deg in ((0, 90, 180, 270) if turns else (0,)):
            name = base if not turns else f"{base}_{TURN_NAMES[deg]}"
            src = flat.rotate(-deg, expand=True, resample=Image.BICUBIC) if deg else flat  # clockwise
            sprite, (bw, bh) = silhouette(cel(src))
            sprite.save(ART_DIR / f"{name}.png")
            fw, fh = (bw - 2) * ART_SCALE, (bh - 2) * ART_SCALE  # the ink is not solid
            if kind == "circle":
                fw = fh = min(fw, fh)
            display = DISPLAY[base] + (f" (faces {TURN_NAMES[deg].upper()})" if turns else "")
            (ITEM_DIR / f"{name}.tscn").write_text(scene_text(name, base, display, solid, kind, (fw, fh), bw, bh), encoding="utf-8", newline="\n")
            manifest[name] = {"base": base, "kind": kind, "solid": solid, "w": round(fw, 2), "h": round(fh, 2), "art": [bw, bh]}
    (ROOT / "tools/art/furniture_manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    print(len(manifest), "furniture scenes")


if __name__ == "__main__":
    main()
