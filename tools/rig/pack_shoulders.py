import json, sys
# usage: pack_shoulders.py <shoulders.json> <the role's sprites.json in the game>
sh = json.load(open(sys.argv[1]))
meta = json.load(open(sys.argv[2]))
for state, rows in sh.items():
    if state in meta:
        meta[state]["shoulders"] = rows  # per frame: [left x, left y, right x, right y], offsets from the pivot in sheet pixels
json.dump(meta, open(sys.argv[2], "w"), indent=1)
print("shoulders for", [s for s in sh if s in meta])
