"""Generates the facility's pixel art from Palette A: floor, wall and shadow atlases, doors, vent grate and light textures.
Run from the repository root:  py -3 tools/art/make_facility_art.py
Output goes to night_shift/environment/art/. Every pixel is a Palette A colour; the output is deterministic.

Scale (from the sprite kit): 44 px = 1 m. One tile is 22 px = 0.5 m, so a wall is 0.5 m thick, a door is 2 tiles = 1 m wide,
a corridor is 4 tiles = 2 m wide, and a character (64 px frame, about 22 px across the shoulders) fits a doorway with room to spare."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel_canvas import Canvas, Rng, rgb

T = 22
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "night_shift", "environment", "art")

# neighbour bits, used for walls (neighbour is wall) and for the shadow overlay (neighbour is wall)
N, NE, E, SE, S, SW, W, NW = 1, 2, 4, 8, 16, 32, 64, 128


def floor_tile(kind, variant):
    c = Canvas(T, T)
    r = Rng(ord(kind[0]) * 131 + variant * 17 + len(kind))
    if kind == "room":  # vinyl tile, every other tile one step darker, grout on the right and bottom edge
        c.rect(0, 0, T, T, "tile" if variant % 2 == 0 else "floor")
        for i in range(T):
            c.set(T - 1, i, "deep")
            c.set(i, T - 1, "deep")
        for _ in range(4):
            c.set(r.below(T - 2), r.below(T - 2), "floor" if variant % 2 == 0 else "tile")
    elif kind == "corridor":  # poured concrete with seams and speckle
        c.rect(0, 0, T, T, "floor")
        for _ in range(9):
            c.set(r.below(T), r.below(T), "tile")
        if variant in (0, 2):
            for i in range(T):
                c.set(T - 1, i, "deep")
        if variant == 1:
            for i in range(T):
                c.set(i, T - 1, "deep")
        if variant == 3:  # a crack
            x, y = 4 + r.below(6), 3
            for _ in range(12):
                c.set(x, y, "deep")
                y += 1
                x += r.below(3) - 1
    elif kind == "utility":  # diamond plate
        c.rect(0, 0, T, T, "tile")
        for row in range(4):
            for col in range(4):
                ox = col * 6 + (3 if row % 2 else 0) + (variant % 2)
                oy = row * 6 + 1
                for k in range(3):
                    c.set(ox + k, oy, "wall")
                    c.set(ox + k, oy + 1, "wall")
                c.set(ox, oy, "wall_top")
        for i in range(T):
            c.set(T - 1, i, "deep")
            c.set(i, T - 1, "deep")
    elif kind == "vault":  # dark riveted steel
        c.rect(0, 0, T, T, "deep")
        for i in range(T):
            c.set(T - 1, i, "shadow")
            c.set(i, T - 1, "shadow")
        for (x, y) in ((3, 3), (17, 3), (3, 17), (17, 17)):
            c.set(x, y, "wall")
        for i in range(6, 16):
            c.set(i, 10, "floor")
            c.set(10, i, "floor")
    elif kind == "outdoor":  # asphalt
        c.rect(0, 0, T, T, "deep")
        for _ in range(14):
            c.set(r.below(T), r.below(T), "floor" if r.chance(70) else "tile")
        if variant == 3:
            for i in range(0, T, 4):
                c.set(i, 11, "wall")
                c.set(i + 1, 11, "wall")
    return c


FLOOR_KINDS = ["room", "corridor", "utility", "vault", "outdoor"]


def make_floors():
    atlas = Canvas(T * 4, T * len(FLOOR_KINDS))
    for row, kind in enumerate(FLOOR_KINDS):
        for variant in range(4):
            atlas.blit(floor_tile(kind, variant), variant * T, row * T)
    return atlas


def wall_tile(mask):
    c = Canvas(T, T, "wall")
    n, e, s, w = bool(mask & N), bool(mask & E), bool(mask & S), bool(mask & W)
    # shaded sides first, lit sides over them, the ink outline last so it always wins at the corners
    if not s:
        for x in range(T):
            c.set(x, T - 2, "deep")
    if not e:
        for y in range(T):
            c.set(T - 2, y, "deep")
    if not n:
        for x in range(T):
            c.set(x, 1, "wall_top")
            c.set(x, 2, "wall_top")
    if not w:
        for y in range(T):
            c.set(1, y, "wall_top")
            c.set(2, y, "wall_top")
    if not n:
        for x in range(T):
            c.set(x, 0, "void")
    if not s:
        for x in range(T):
            c.set(x, T - 1, "void")
    if not w:
        for y in range(T):
            c.set(0, y, "void")
    if not e:
        for y in range(T):
            c.set(T - 1, y, "void")
    # inner corners: both neighbours are wall but the diagonal is open
    for (diag, a, b, xs, ys) in ((NE, n, e, (T - 2, T - 1), (0, 1)), (SE, s, e, (T - 2, T - 1), (T - 2, T - 1)),
                                  (SW, s, w, (0, 1), (T - 2, T - 1)), (NW, n, w, (0, 1), (0, 1))):
        if a and b and not (mask & diag):
            for x in xs:
                for y in ys:
                    c.set(x, y, "void")
    return c


def make_walls():
    atlas = Canvas(T * 16, T * 16)
    for mask in range(256):
        atlas.blit(wall_tile(mask), (mask % 16) * T, (mask // 16) * T)
    return atlas


def shadow_tile(mask):
    """Soft contact shadow on a floor cell that touches walls. The light comes from the top left, so walls above and to the left
    throw the long shadow and walls below and to the right only a thin one. Hard pixels and dithering, no alpha blending."""
    c = Canvas(T, T)
    if mask & N:
        for x in range(T):
            c.set(x, 0, "shadow")
            c.set(x, 1, "shadow")
            if (x % 2) == 0:
                c.set(x, 2, "deep")
    if mask & W:
        for y in range(T):
            c.set(0, y, "shadow")
            c.set(1, y, "shadow")
            if (y % 2) == 0:
                c.set(2, y, "deep")
    if mask & S:
        for x in range(T):
            c.set(x, T - 1, "deep")
    if mask & E:
        for y in range(T):
            c.set(T - 1, y, "deep")
    if (mask & NW) and not (mask & N) and not (mask & W):
        for (x, y) in ((0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (0, 2)):
            c.set(x, y, "shadow")
    if (mask & NE) and not (mask & N) and not (mask & E):
        for (x, y) in ((T - 1, 0), (T - 2, 0), (T - 1, 1)):
            c.set(x, y, "deep")
    if (mask & SW) and not (mask & S) and not (mask & W):
        for (x, y) in ((0, T - 1), (0, T - 2), (1, T - 1)):
            c.set(x, y, "deep")
    if (mask & SE) and not (mask & S) and not (mask & E):
        c.set(T - 1, T - 1, "deep")
    return c


def make_shadows():
    atlas = Canvas(T * 16, T * 16)
    for mask in range(256):
        atlas.blit(shadow_tile(mask), (mask % 16) * T, (mask // 16) * T)
    return atlas


def door_h(state, exterior):
    """A 2 tile wide door in a horizontal wall. states: closed, locked, open."""
    c = Canvas(T * 2, T)
    W2 = T * 2
    ends = [(0, 7), (W2 - 7, 7)]  # retracted panels when open
    if state == "open":
        for (x0, w) in ends:
            c.rect(x0, 0, w, T, "wall")
            c.rect(x0, 1, w, 2, "wall_top")
            c.rect(x0, T - 2, w, 1, "deep")
            c.outline(x0, 0, w, T, "void")
        for x in range(W2):  # door track on the floor
            c.set(x, 4, "deep")
            c.set(x, T - 5, "deep")
        return c
    c.rect(0, 0, W2, T, "wall")
    c.rect(1, 1, W2 - 2, T - 2, "wall")
    c.rect(2, 3, W2 - 4, T - 6, "metal")
    c.rect(2, 3, W2 - 4, 1, "wall_top")
    c.rect(2, T - 4, W2 - 4, 2, "wall")
    for y in range(3, T - 3):  # seam where the two sliding leaves meet
        c.set(T - 1, y, "void")
        c.set(T, y, "void")
    if exterior:  # hazard stripes: heavier doors lead outside
        for x in range(2, W2 - 2):
            if ((x + 0) // 3) % 2 == 0:
                c.set(x, 7, "backup")
                c.set(x, 8, "backup")
            else:
                c.set(x, 7, "void")
                c.set(x, 8, "void")
    light = "alarm" if state == "locked" else "backup"
    for (x, y) in ((T - 5, 11), (T - 4, 11), (T + 3, 11), (T + 4, 11)):
        c.set(x, y, light)
        c.set(x, y + 1, light)
    c.outline(0, 0, W2, T, "void")
    return c


def vent_grate():
    c = Canvas(T, T, "deep")
    c.outline(0, 0, T, T, "void")
    c.rect(2, 2, T - 4, T - 4, "shadow")
    for y in (5, 8, 11, 14, 17):
        for x in range(4, T - 4):
            c.set(x, y, "wall_top")
            c.set(x, y + 1, "wall")
    for (x, y) in ((1, 1), (T - 2, 1), (1, T - 2), (T - 2, T - 2)):
        c.set(x, y, "metal")
    return c


def radial_light(size=256, bands=4):
    c = Canvas(size, size)
    cx = cy = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / (size / 2.0)
            level = 0
            if d < 1.0:
                level = int(255 * (1.0 - math.floor(d * bands) / bands))
            c.set(x, y, (level, level, level, 255))
    return c


def cone_light(width=512, height=256, half_angle=28.0, bands=4):
    """A flashlight beam pointing right from the left-middle edge. Use it with the light's offset set to (width / 2, 0)."""
    c = Canvas(width, height)
    cy = (height - 1) / 2.0
    for y in range(height):
        for x in range(width):
            d = math.hypot(x, y - cy) / width
            ang = abs(math.degrees(math.atan2(y - cy, x + 0.001)))
            level = 0
            if d < 1.0 and ang <= half_angle:
                core = 1.0 if ang <= half_angle * 0.55 else 0.55
                level = int(255 * core * (1.0 - math.floor(d * bands) / bands))
            c.set(x, y, (level, level, level, 255))
    return c


def main():
    os.makedirs(OUT, exist_ok=True)
    make_floors().save(os.path.join(OUT, "floors.png"))
    make_walls().save(os.path.join(OUT, "walls.png"))
    make_shadows().save(os.path.join(OUT, "shadows.png"))
    for exterior in (False, True):
        for state in ("closed", "locked", "open"):
            name = "door_%s_%s" % ("exterior" if exterior else "interior", state)
            h = door_h(state, exterior)
            h.save(os.path.join(OUT, name + "_h.png"))
            h.rotated_cw().save(os.path.join(OUT, name + "_v.png"))
    vent_grate().save(os.path.join(OUT, "vent_grate.png"))
    radial_light().save(os.path.join(OUT, "light_radial.png"))
    cone_light().save(os.path.join(OUT, "light_cone.png"))
    print("wrote", len(os.listdir(OUT)), "files to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
