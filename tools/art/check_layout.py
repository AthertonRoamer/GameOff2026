"""Checks night_shift/environment/facility_layout.json: rooms do not overlap, every door opens a wall cell between the two rooms
it names, and every room can be reached from every other through doors.  Run:  py -3 tools/art/check_layout.py"""
import json
import os
import sys

path = os.path.join(os.path.dirname(__file__), "..", "..", "night_shift", "environment", "facility_layout.json")
data = json.load(open(path))
floor = {}  # cell -> room id
problems = []
for room in data["rooms"]:
    for (x0, y0, x1, y1) in room["rects"]:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if (x, y) in floor and floor[(x, y)] != room["id"]:
                    problems.append("rooms %s and %s overlap at %s" % (floor[(x, y)], room["id"], (x, y)))
                floor[(x, y)] = room["id"]

ids = {r["id"] for r in data["rooms"]}
edges = {i: set() for i in ids}
for door in data["doors"]:
    x0, y0, x1, y1 = door["rect"]
    a, b = door["a"], door["b"]
    if a not in ids or b not in ids:
        problems.append("door %s names an unknown room" % door["rect"])
        continue
    horizontal_wall = (y0 == y1)  # a door in a horizontal wall spans x and the rooms are above and below
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x, y) in floor:
                problems.append("door cell %s is floor of %s, it must be a wall cell" % ((x, y), floor[(x, y)]))
            before, after = ((x, y - 1), (x, y + 1)) if horizontal_wall else ((x - 1, y), (x + 1, y))
            rooms_here = {floor.get(before), floor.get(after)}
            if rooms_here != {a, b}:
                problems.append("door %s cell %s joins %s, expected %s and %s" % (door["rect"], (x, y), rooms_here, a, b))
    edges[a].add(b)
    edges[b].add(a)

seen, stack = set(), [data["rooms"][0]["id"]]
while stack:
    cur = stack.pop()
    if cur in seen:
        continue
    seen.add(cur)
    stack.extend(edges[cur] - seen)
for missing in ids - seen:
    problems.append("room %s cannot be reached through doors" % missing)

# rooms must keep a one tile wall between them, which means no two floor cells of different rooms may touch, even diagonally
for (x, y), room in floor.items():
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            other = floor.get((x + dx, y + dy))
            if other and other != room:
                problems.append("rooms %s and %s touch at %s, leave one tile for the wall" % (room, other, (x, y)))
                break

for (x, y) in data["vents"]:
    if (x, y) not in floor:
        problems.append("vent at %s is not on a floor cell" % ((x, y),))

width = max(x for x, _ in floor) - min(x for x, _ in floor) + 1
height = max(y for _, y in floor) - min(y for _, y in floor) + 1
print("%d rooms, %d doors, %d floor cells, map %d x %d tiles (%.0f x %.0f m)" % (len(ids), len(data["doors"]), len(floor), width, height, width / 2, height / 2))
if problems:
    print("\n".join(sorted(set(problems))[:40]))
    print("LAYOUT: %d problems" % len(set(problems)))
    sys.exit(1)
print("LAYOUT: ok")
