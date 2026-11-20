"""Packs everything anim.py rendered for a role into the game's skin folder (game/player/skin/<role>/): the sheets, sprites.json, and the data the game reads from it.
    python pack_skin.py <rendered folder> <shoulders folder> <skin folder>
<rendered folder>   the pictures: `anim.py -- <role> <dir> <states>` writes <dir>/<role>/<state>_NN.png
<shoulders folder>  the same states without pictures (SHOULDERS=1), which writes shoulders.json (the lamp's shoulder in every frame) and heads.json; it must include
                    torso_walk and torso_run too, which the sideways and backwards torsos are lined up with
Only the states that were rendered are packed, so a part of a skin can be redone alone. In order:
  1. the sheets (pack_trimmed.py: each cut down to the area its frames use) at the speed and looping SHEETS in sheets.py gives them
  2. the shoulder positions of the upper body sheets (pack_shoulders.py)
  3. the size of the sideways and backwards sheets (GAIT_SCALE), and the placing of their upper bodies so the head stays where the forward sheets have it
  4. the transitions (pack_transitions.py)
  5. where each fall ends (end_pose.py)
Godot then has to import the new sheets and bake the frames (build_skin.ps1 does all of it)."""
import glob, json, os, re, subprocess, sys, tempfile
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sheets import GAIT_SCALE, HEAD_REFERENCE, SHEETS


def run(script, *args):
    subprocess.run([sys.executable, os.path.join(HERE, script), *[str(a) for a in args]], check=True)


def main(rendered, shoulders_dir, skin):
    present = {re.sub(r"_\d\d\.png$", "", os.path.basename(f)) for f in glob.glob(f"{rendered}/*_[0-9][0-9].png")}
    sheets = sorted(s for s in SHEETS if s in present)
    # 1. the sheets, those that are played the same way together
    for fps, loop in sorted({SHEETS[s] for s in sheets}):
        group = [s for s in sheets if SHEETS[s] == (fps, loop)]
        run("pack_trimmed.py", rendered, skin, fps, int(loop), *group)
    # 2. the shoulders
    shoulders = os.path.join(shoulders_dir, "shoulders.json")
    torsos = [s for s in sheets if s.startswith("torso_")]
    if torsos:  # (only these sheets: the transitions carry their own, moved and resized with their frames)
        wanted = {s: rows for s, rows in json.load(open(shoulders)).items() if s in torsos}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tmp:
            json.dump(wanted, tmp)
        run("pack_shoulders.py", tmp.name, os.path.join(skin, "sprites.json"))
        os.remove(tmp.name)
    # 3. size and placing
    meta = json.load(open(f"{skin}/sprites.json"))
    heads = json.load(open(os.path.join(shoulders_dir, "heads.json")))
    for sheet in sheets:
        layer, _, gait = sheet.partition("_")
        scale = GAIT_SCALE.get(gait)
        if scale is None:
            continue
        if scale != 1.0:
            meta[sheet]["scale"] = scale
        if sheet in HEAD_REFERENCE:
            shift = np.array(heads[HEAD_REFERENCE[sheet]]).mean(axis=0) / scale - np.array(heads[sheet]).mean(axis=0)
            entry = meta[sheet]
            entry["godot_offset"] = [round(entry["godot_offset"][0] + float(shift[0]), 1), round(entry["godot_offset"][1] + float(shift[1]), 1)]
            entry["shoulders"] = [[round(r[0] + float(shift[0]), 1), round(r[1] + float(shift[1]), 1), round(r[2] + float(shift[0]), 1), round(r[3] + float(shift[1]), 1)]
                for r in entry["shoulders"]]
            print("%-22s head moved by (%.1f, %.1f), scale %.2f" % (sheet, shift[0], shift[1], scale))
    json.dump(meta, open(f"{skin}/sprites.json", "w"), indent=1)
    # 4. the transitions
    if any("_tr_" in p or p.startswith("torso_flip_") for p in present):
        run("pack_transitions.py", rendered, os.path.join(shoulders_dir, "heads.json"), shoulders, skin)
    # 5. the falls
    if any(p.startswith("death_") for p in present):
        run("end_pose.py", skin)


if __name__ == "__main__":
    main(*sys.argv[1:4])
