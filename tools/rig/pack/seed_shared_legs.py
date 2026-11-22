"""Starts a role's sprites.json with the guard's legs: every legs_* entry copied, its file pointing at the guard's sheet (res://game/player/skin/guard/...). Every role wears the
same trousers and boots, so the legs exist once in memory, and a role's skin folder holds only its own upper body and falls.
    python seed_shared_legs.py <guard skin folder> <role skin folder>
Run before pack_skin.py, which adds the role's own sheets to the file. A role that already has a sprites.json keeps its entries (the legs are only added or refreshed)."""
import json, os, sys

RES = "res://game/player/skin/guard/"
guard, role = sys.argv[1], sys.argv[2]
os.makedirs(role, exist_ok=True)
guard_meta = json.load(open(os.path.join(guard, "sprites.json")))
path = os.path.join(role, "sprites.json")
meta = json.load(open(path)) if os.path.exists(path) else {}
for name, entry in guard_meta.items():
    if name.startswith("legs_"):
        entry = dict(entry)
        entry["file"] = entry["file"] if entry["file"].startswith("res://") else RES + entry["file"]
        meta[name] = entry
json.dump(meta, open(path, "w"), indent=1)
print("%s: %d shared legs sheets" % (role, sum(1 for n in meta if n.startswith("legs_"))))
