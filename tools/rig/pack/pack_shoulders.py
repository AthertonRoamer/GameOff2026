import json, sys
# usage: pack_shoulders.py <shoulders.json> <the role's sprites.json in the game> [rendered_state=game_state ...]
# Without the pairs, a state is matched by its own name; rendered_state=game_state is for a state packed under another name (see pack_trimmed.py).
sh = json.load(open(sys.argv[1]))
meta = json.load(open(sys.argv[2]))
names = dict(pair.split("=") for pair in sys.argv[3:])
done = []
for state, rows in sh.items():
    target = names.get(state, state)
    if target in meta:
        meta[target]["shoulders"] = rows  # per frame: [left x, left y, right x, right y], offsets from the pivot in sheet pixels
        done.append(target)
json.dump(meta, open(sys.argv[2], "w"), indent=1)
print("shoulders for", done)
