"""One-off: converts night_shift/environment/facility_layout.json from 0.5 m cells to 0.25 m cells so that walls are 0.25 m thin.
Every old floor cell becomes 2 x 2 new cells, an old wall cell (between two rooms) becomes ONE new cell, and a door (2 old cells, 1 m)
becomes 4 new cells (still 1 m). A rect that has a wall on its left or top grows one new cell that way, which is what turns the old 2 cell gap
into a 1 cell wall. Run from the repository root:  py -3 tools/art/convert_layout_to_quarter_metre.py"""
import json
import os

path = os.path.join(os.path.dirname(__file__), "..", "..", "night_shift", "environment", "facility_layout.json")
data = json.load(open(path))
if data["tile_size"] != 22:
    raise SystemExit("layout is not on the 0.5 m grid (tile_size 22), nothing to do")

old_floor = set()
for room in data["rooms"]:
    for (x0, y0, x1, y1) in room["rects"]:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                old_floor.add((x, y))

def runs(values):
    """Splits a list of booleans into (start, end, value) runs of equal neighbours."""
    out, start = [], 0
    for i in range(1, len(values) + 1):
        if i == len(values) or values[i] != values[start]:
            out.append((start, i - 1, values[start]))
            start = i
    return out


for room in data["rooms"]:
    new_rects = []
    for (x0, y0, x1, y1) in room["rects"]:
        # the edge can have wall above it along part of its length and floor above it along the rest (the corridor ring does),
        # so the rect is cut into pieces that each have one kind of neighbour, and only pieces with a wall beyond grow by a cell
        for (ra, rb, floor_above) in runs([(x, y0 - 1) in old_floor for x in range(x0, x1 + 1)]):
            sx0, sx1 = x0 + ra, x0 + rb
            for (ca, cb, floor_left) in runs([(sx0 - 1, y) in old_floor for y in range(y0, y1 + 1)]):
                sy0, sy1 = y0 + ca, y0 + cb
                grow_top = 0 if floor_above and sy0 == y0 else (0 if (sx0, sy0 - 1) in old_floor else 1)
                grow_left = 0 if floor_left else 1
                new_rects.append([2 * sx0 - grow_left, 2 * sy0 - grow_top, 2 * sx1 + 1, 2 * sy1 + 1])
    room["rects"] = new_rects
    room.pop("floor", None)  # one floor everywhere now
    room.pop("lamp", None)   # no lighting for now
for door in data["doors"]:
    x0, y0, x1, y1 = door["rect"]
    if y0 == y1:  # a door in a horizontal wall
        door["rect"] = [2 * x0, 2 * y0, 2 * x1 + 1, 2 * y0]
    else:         # a door in a vertical wall
        door["rect"] = [2 * x0, 2 * y0, 2 * x0, 2 * y1 + 1]

data["vents"] = [[2 * x, 2 * y] for (x, y) in data["vents"]]  # the top left cell of the 0.5 m vent grille
data["tile_size"] = 11
data["px_per_m"] = 44
data["_comment"] = ("Facility 9 layout. All numbers are tile coordinates, 1 tile = 11 px = 0.25 m. Rects are [x0, y0, x1, y1] inclusive. "
                    "Walls are not listed: every cell that touches a floor cell (including diagonally) and is not floor becomes wall, so rooms need a "
                    "gap of exactly one tile between them, and walls are one tile (0.25 m) thick. Doors list the wall cells they open and are "
                    "4 cells (1 m) wide. A vent is the top left cell of a 2 x 2 cell (0.5 m) grille.")
with open(path, "w") as f:
    json.dump(data, f, indent="\t")
print("converted", len(data["rooms"]), "rooms and", len(data["doors"]), "doors")
