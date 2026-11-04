"""Demo art pass for the facility: 44 px tiles (1 m), a wall you see from the front (face) and from above (roof), panelled floor,
hazard stripes, a vent grille, a sliding door and a wall console. Palette A only. Run from the repository root:
    py -3 tools/art/make_demo_art.py
Output: night_shift/environment/demo/art/. Nothing outside that folder is touched.

Look: a slightly oblique top-down view. A wall with floor to its south shows its front face (a pale metal panel above a strip of
machinery), anything else shows its roof (dark, with pipe runs). Open edges get a bright 2 px rim and a 1 px ink outline, the same
1 px outline and three-step shading the character sprites use. The light comes from the top left."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from pixel_canvas import Canvas, Rng

T = 44
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "night_shift", "environment", "demo", "art")
N, E, S, W = 1, 2, 4, 8  # roof masks: bit set when that neighbour is wall or outside (no rim there)


def panel_floor(variant):
    c = Canvas(T, T, "shadow")  # grout
    c.rect(1, 1, T - 2, T - 2, "wall")
    for (x, y) in ((1, 1), (T - 2, 1), (1, T - 2), (T - 2, T - 2)):
        c.set(x, y, "shadow")  # rounded corners
    c.rect(4, 4, T - 8, T - 8, "tile")
    for (x, y) in ((4, 4), (T - 5, 4), (4, T - 5), (T - 5, T - 5)):
        c.set(x, y, "wall")
    for x in range(2, T - 2):  # lit top and left edge, shaded bottom and right edge
        c.set(x, 1, "wall_top")
        c.set(x, T - 2, "deep")
    for y in range(2, T - 2):
        c.set(1, y, "wall_top")
        c.set(T - 2, y, "deep")
    for x in range(5, T - 5):  # inner step: the panel sits slightly below its frame
        c.set(x, T - 5, "floor")
    for y in range(5, T - 5):
        c.set(T - 5, y, "floor")
    for (x, y, dx, dy) in ((7, 7, 1, 1), (T - 8, 7, -1, 1), (7, T - 8, 1, -1), (T - 8, T - 8, -1, -1)):  # corner rivets
        c.set(x, y, "wall_top")
        c.set(x + dx, y, "wall_top")
        c.set(x, y + dy, "wall_top")
    r = Rng(variant * 977 + 5)
    if variant in (1, 3):
        for _ in range(10):
            c.set(7 + r.below(T - 14), 7 + r.below(T - 14), "floor")
    if variant in (2, 3):
        for _ in range(7):
            c.set(7 + r.below(T - 14), 7 + r.below(T - 14), "wall")
    return c


def vent_floor():
    c = Canvas(T, T, "shadow")
    c.rect(1, 1, T - 2, T - 2, "wall")
    c.rect(3, 3, T - 6, T - 6, "deep")
    for i in range(5):
        y = 6 + i * 7
        c.rect(5, y, T - 10, 3, "shadow")
        c.rect(5, y + 3, T - 10, 1, "wall")
    for x in range(2, T - 2):
        c.set(x, 1, "wall_top")
    for y in range(2, T - 2):
        c.set(1, y, "wall_top")
    for (x, y) in ((3, 3), (T - 4, 3), (3, T - 4), (T - 4, T - 4)):
        c.set(x, y, "wall_top")
    return c


def hazard(edge):
    """Amber and black warning stripes along one edge of a floor tile, 7 px wide."""
    c = Canvas(T, T)
    for y in range(T):
        for x in range(T):
            inside = {"n": y < 7, "s": y >= T - 7, "w": x < 7, "e": x >= T - 7}[edge]
            if inside:
                c.set(x, y, "backup" if ((x + y) // 4) % 2 == 0 else "shadow")
    if edge in ("n", "s"):
        edge_y = 7 if edge == "n" else T - 8
        for x in range(T):
            c.set(x, edge_y, "void")
    else:
        edge_x = 7 if edge == "w" else T - 8
        for y in range(T):
            c.set(edge_x, y, "void")
    return c


def pipe_run(horizontal=True):
    c = Canvas(T, T, "shadow")
    for y0 in (9, 24):
        c.rect(0, y0, T, 5, "uniform")
        c.rect(0, y0, T, 1, "uniform_light")
        c.rect(0, y0 + 4, T, 1, "void")
        for x in range(2, T, 11):  # brackets
            c.rect(x, y0 - 2, 2, 9, "wall")
            c.set(x, y0 - 2, "wall_top")
    for x in range(5, T, 11):
        c.set(x, 18, "wall")
        c.set(x + 1, 18, "wall")
        c.set(x, 35, "wall")
        c.set(x + 1, 35, "wall")
    return c if horizontal else c.rotated_cw()


def roof(mask):
    closed = {"n": bool(mask & N), "e": bool(mask & E), "s": bool(mask & S), "w": bool(mask & W)}
    if closed["e"] and closed["w"]:
        c = pipe_run(True)
    elif closed["n"] and closed["s"]:
        c = pipe_run(False)
    else:
        c = Canvas(T, T, "shadow")
        c.rect(2, 2, T - 4, T - 4, "deep")
        for (x, y) in ((6, 6), (T - 7, 6), (6, T - 7), (T - 7, T - 7)):
            c.rect(x, y, 2, 2, "wall")
    if not closed["s"]:
        c.rect(0, T - 3, T, 3, "uniform_light")
        c.rect(0, T - 1, T, 1, "void")
    if not closed["e"]:
        c.rect(T - 3, 0, 3, T, "uniform_light")
        c.rect(T - 1, 0, 1, T, "void")
    if not closed["n"]:  # lit sides: 1 px ink, 2 px bright rim that catches the light in dashes, 1 px step down
        c.rect(0, 0, T, 1, "void")
        c.rect(0, 1, T, 2, "accent")
        for x in range(4, T, 9):
            c.set(x, 1, "metal")
            c.set(x + 1, 1, "metal")
        c.rect(0, 3, T, 1, "uniform_light")
    if not closed["w"]:
        c.rect(0, 0, 1, T, "void")
        c.rect(1, 0 if closed["n"] else 1, 2, T, "accent")
        for y in range(4, T, 9):
            c.set(1, y, "metal")
            c.set(1, y + 1, "metal")
        c.rect(3, 0 if closed["n"] else 4, 1, T, "uniform_light")
    return c


def face(n_open, e_open, w_open, detail):
    """The front of a wall: pale metal panel over a strip of machinery. detail 0 clean, 1 busy, 2 console."""
    c = Canvas(T, T, "metal")
    c.rect(0, 18, T, 10, "wall_top")  # shade band at the foot of the panel
    for x in range(0, T, 2):  # dithered step between lit and shaded
        c.set(x, 17, "wall_top")
    for y in range(4, 17):
        c.set(0, y, "wall_top")  # panel seams
        c.set(T - 1, y, "wall_top")
    for x in range(7, T - 6, 11):  # rivets along the panel
        c.set(x, 13, "wall_top")
    c.rect(0, 28, T, 15, "wall")  # machinery strip
    c.rect(0, 28, T, 1, "void")
    if detail == 0:
        for j in range(4):
            c.rect(4, 31 + j * 3, 11, 1, "shadow")
            c.rect(17, 31 + j * 3, 11, 1, "shadow")
        c.rect(32, 32, 2, 1, "item")
        c.rect(36, 32, 2, 1, "backup")
        c.rect(30, 37, 12, 2, "uniform")
        c.rect(30, 37, 12, 1, "uniform_light")
    elif detail == 1:
        c.rect(3, 30, 20, 11, "void")
        c.rect(4, 31, 18, 9, "deep")
        for i in range(5):
            c.rect(6 + i * 3, 34, 2, 1, "item" if i % 2 == 0 else "wall_top")
        c.rect(6, 37, 14, 1, "wall")
        c.rect(26, 31, 4, 9, "shadow")
        c.rect(33, 31, 8, 3, "shadow")
        c.set(34, 32, "alarm")
        c.set(37, 32, "backup")
        c.rect(26, 38, 16, 2, "uniform")
        c.rect(26, 38, 16, 1, "uniform_light")
    else:
        c.rect(6, 4, 32, 15, "void")  # screen bezel
        c.rect(7, 5, 30, 13, "shadow")
        c.rect(9, 8, 11, 1, "item")
        c.rect(9, 11, 15, 1, "item")
        c.rect(9, 14, 8, 1, "item")
        c.outline(27, 7, 8, 9, "item")
        c.rect(30, 9, 2, 5, "item")
        c.rect(12, 22, 20, 5, "void")  # keyboard
        c.rect(13, 23, 18, 3, "backup")
        for x in range(15, 31, 3):
            c.set(x, 24, "shadow")
        c.rect(5, 22, 5, 5, "wall")
        c.rect(34, 22, 5, 5, "wall")
        c.rect(5, 22, 5, 1, "wall_top")
        c.rect(34, 22, 5, 1, "wall_top")
    c.rect(0, T - 1, T, 1, "void")
    if n_open:
        c.rect(0, 0, T, 1, "void")
        c.rect(0, 1, T, 2, "accent")
        for x in range(5, T, 9):
            c.set(x, 1, "metal")
            c.set(x + 1, 1, "metal")
        c.rect(0, 3, T, 1, "uniform_light")
    else:
        c.rect(0, 0, T, 2, "wall_top")
    if w_open:
        c.rect(0, 0, 1, T, "void")
        c.rect(1, 1, 2, T - 2, "accent")
        c.rect(3, 1, 1, T - 2, "uniform_light")
    if e_open:
        c.rect(T - 1, 0, 1, T, "void")
        c.rect(T - 3, 1, 2, T - 2, "uniform_light")
    return c


def door(state):
    """A one metre sliding door in a wall front. states: closed, locked, open."""
    c = Canvas(T, T)
    if state == "open":
        for x0 in (0, T - 7):
            c.rect(x0, 0, 7, T, "uniform")
            c.rect(x0, 0, 7, 1, "uniform_light")
            c.rect(x0, T - 1, 7, 1, "void")
            c.outline(x0, 0, 7, T, "void")
        return c
    c.rect(0, 0, T, T, "uniform")
    c.rect(0, 0, T, 3, "accent")
    for x in range(4, T, 9):
        c.set(x, 0, "metal")
    c.rect(0, 3, T, 1, "uniform_light")
    for (x0, x1) in ((3, 21), (23, 40)):  # the two leaves
        c.rect(x0, 6, x1 - x0, 33, "wall_top")
        c.rect(x0 + 1, 7, x1 - x0 - 2, 31, "uniform_light")
        c.rect(x0 + 2, 9, x1 - x0 - 4, 27, "uniform")
        c.rect(x0 + 2, 33, x1 - x0 - 4, 1, "deep")
    light = "alarm" if state == "locked" else "item"
    for (x, y) in ((15, 19), (28, 19)):  # a pair of status lights either side of the seam
        c.rect(x, y, 4, 4, light)
        c.set(x, y, "uniform")
        c.set(x + 3, y + 3, "uniform")
    c.rect(21, 4, 2, T - 6, "void")
    c.rect(0, 0, 3, T, "accent")
    c.rect(T - 3, 0, 3, T, "uniform_light")
    c.rect(0, 0, 1, T, "void")
    c.rect(T - 1, 0, 1, T, "void")
    c.rect(0, T - 1, T, 1, "void")
    return c


def main():
    os.makedirs(OUT, exist_ok=True)
    floors = Canvas(T * 9, T)
    for i in range(4):
        floors.blit(panel_floor(i), i * T, 0)
    floors.blit(vent_floor(), 4 * T, 0)
    for i, edge in enumerate(("n", "e", "s", "w")):
        floors.blit(hazard(edge), (5 + i) * T, 0)
    floors.save(os.path.join(OUT, "floors.png"))

    roofs = Canvas(T * 4, T * 4)
    for mask in range(16):
        roofs.blit(roof(mask), (mask % 4) * T, (mask // 4) * T)
    roofs.save(os.path.join(OUT, "roofs.png"))

    faces = Canvas(T * 8, T * 3)  # column = n_open + 2 * e_open + 4 * w_open, row = detail
    for detail in range(3):
        for m in range(8):
            faces.blit(face(bool(m & 1), bool(m & 2), bool(m & 4), detail), m * T, detail * T)
    faces.save(os.path.join(OUT, "faces.png"))

    for state in ("closed", "locked", "open"):
        door(state).save(os.path.join(OUT, "door_%s.png" % state))
    print("wrote", len(os.listdir(OUT)), "files to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
