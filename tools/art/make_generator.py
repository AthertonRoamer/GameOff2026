"""Draws the backup generator (game/power/generator.tscn, the one players start and shoot) with the furniture's brushes and cel look:

    game/power/art/generator.png           whole (off or running: the lamp and the gauge's needle are drawn by Generator on top)
    game/power/art/generator_broken.png    shot down: the hatch torn, holes, scorching

Run from the project folder:  python tools/art/make_generator.py
Drawn at 176 px per metre like the furniture (shown at 0.25). Its body is 208 x 136 px: the 52 x 34 world px of Generator.SIZE.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image  # noqa: E402
from make_furniture import silhouette  # noqa: E402
from make_props import shape, new, line, disc, dot, poly, hazard_band, finish, cel, GAME_PPM  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/power/art"
W, H, PAD = 208, 136, 20
# where Generator draws its lamp, gauge and scope mark, in body pixels (keep in step with generator.gd)
LAMP = (184, 28)
GAUGE = (150, 98)
MARK = (184, 108)


def generator(broken=False):
    img = new(W + PAD * 2, H + PAD * 2)
    o = PAD

    def at(x, y):
        return o + x, o + y

    def box(x0, y0, x1, y1):
        return (o + x0, o + y0, o + x1, o + y1)

    shape(img, "rect", box(0, 0, W, H), (86, 94, 108), (44, 50, 64), ang=135, r=9, bev=4)  # the steel skid it stands on
    shape(img, "rect", box(7, 7, W - 7, H - 7), (168, 138, 72), (118, 94, 48), ang=135, r=7, bev=3)  # the housing: a worn plant yellow, so it stands out from the furniture
    # the radiator, left: a dark intake with slats
    shape(img, "rect", box(15, 16, 62, H - 16), (30, 34, 42), (16, 18, 24), ang=90, r=4, bev=1.5, hi=0.15, lo=0.15)
    for k in range(8):
        y = 21 + k * 12.4
        shape(img, "rect", box(19, y, 58, y + 6), (146, 154, 168), (78, 86, 100), ang=90, r=2, bev=1.0)
    # the engine fan, middle, under a guard
    fx, fy = at(103, H / 2)
    disc(img, fx, fy, 34, (150, 158, 170), (64, 70, 84), bev=3, power=1.1)
    disc(img, fx, fy, 28, (30, 33, 42), (18, 20, 27), bev=0)
    for k in range(6):
        a = math.radians(k * 60 + 12)
        poly(img, [(fx, fy), (fx + math.cos(a - 0.34) * 25, fy + math.sin(a - 0.34) * 25), (fx + math.cos(a + 0.34) * 25, fy + math.sin(a + 0.34) * 25)], fill=(92, 100, 114, 255), outline=(20, 22, 28, 255), width=1.2)
    for k in range(4):  # the guard's bars
        a = math.radians(k * 45)
        line(img, [(fx - math.cos(a) * 30, fy - math.sin(a) * 30), (fx + math.cos(a) * 30, fy + math.sin(a) * 30)], 1.6, (150, 158, 170), 190)
    disc(img, fx, fy, 8, (170, 176, 188), (84, 92, 106), bev=1.5)
    # the control panel, right: lamp socket, gauge, switches
    shape(img, "rect", box(136, 15, W - 14, H - 15), (70, 78, 94), (42, 48, 62), ang=135, r=4, bev=2.2)
    disc(img, *at(*LAMP), 9, (150, 156, 168), (70, 76, 90), bev=1.2)
    disc(img, *at(*LAMP), 6, (28, 32, 40), (18, 20, 26), bev=0)
    disc(img, *at(*GAUGE), 15, (170, 176, 186), (90, 96, 110), bev=1.5)
    disc(img, *at(*GAUGE), 11.5, (222, 220, 208), (180, 178, 168), bev=0)
    for k in range(7):
        a = math.radians(150 + k * 40)
        gx, gy = at(*GAUGE)
        line(img, [(gx + math.cos(a) * 8, gy + math.sin(a) * 8), (gx + math.cos(a) * 11, gy + math.sin(a) * 11)], 1.2, (50, 54, 62), 230)
    for k in range(3):
        shape(img, "rect", box(144 + k * 11, 22, 151 + k * 11, 36), (40, 44, 54), (22, 24, 30), r=1.5, bev=1)
        dot(img, o + 147.5 + k * 11, o + (26 if k != 1 else 32), 2.4, (190, 196, 206))
    hazard_band(img, box(141, 47, W - 19, 58), (196, 164, 60), (34, 32, 30), 10)
    # exhaust pipe along the top, fuel cap at the bottom, a cable to the panel
    shape(img, "rect", box(70, 12, 126, 24), (160, 166, 178), (80, 88, 102), ang=90, r=6, bev=2)
    disc(img, *at(124, 18), 9, (150, 156, 168), (66, 72, 86), bev=2, power=1.1)
    disc(img, *at(124, 18), 4.5, (20, 22, 28), (12, 14, 18), bev=0)
    disc(img, *at(80, H - 18), 8, (170, 82, 66), (110, 48, 40), bev=1.8)
    line(img, [at(96, H - 18), at(118, H - 14), at(136, H - 26)], 3.2, (26, 28, 34), 255)
    for x, y in ((11, 11), (W - 11, 11), (11, H - 11), (W - 11, H - 11)):
        disc(img, *at(x, y), 3.6, (180, 186, 196), (94, 100, 114), bev=0.9)  # the bolts to the floor
    for x, y, r in ((66, 112, 2.4), (130, 40, 1.8), (48, 11, 2.0), (172, H - 9, 2.4)):
        dot(img, o + x, o + y, r, (104, 70, 46), 170)  # rust

    if broken:
        for cx, cy, r in ((98, 62, 30), (160, 54, 20), (40, 96, 16)):  # scorching
            for k in range(6, 0, -1):
                dot(img, o + cx, o + cy, r * k / 6, (14, 12, 12), 46)
        poly(img, [at(76, 34), at(98, 52), at(90, 60), at(112, 78), at(104, 80), at(128, 104), at(94, 82), at(102, 78), at(82, 62), at(90, 58)], fill=(12, 12, 16, 255), outline=(206, 170, 90, 255), width=1.4)  # the housing split
        for x, y, r in ((52, 40, 4.5), (122, 96, 4), (158, 78, 3.5), (186, 58, 4), (72, 98, 3)):  # bullet holes
            dot(img, o + x, o + y, r + 1.8, (190, 196, 206), 230)
            dot(img, o + x, o + y, r, (10, 10, 14))
        line(img, [at(*GAUGE), at(GAUGE[0] + 9, GAUGE[1] + 6)], 1.3, (40, 44, 52), 255)  # cracked gauge glass
        line(img, [at(GAUGE[0] - 8, GAUGE[1] - 7), at(GAUGE[0] + 2, GAUGE[1] + 1), at(GAUGE[0] - 3, GAUGE[1] + 10)], 1.1, (250, 250, 250), 230)

    done = finish(img)
    return done.resize((round(done.width / GAME_PPM), round(done.height / GAME_PPM)), Image.LANCZOS)  # cel() shrinks by GAME_PPM: this keeps the body 208 x 136


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, broken in (("generator", False), ("generator_broken", True)):
        sprite, size = silhouette(cel(generator(broken)))
        sprite.save(OUT / f"{name}.png")
        print(name, sprite.size, "body", size)
