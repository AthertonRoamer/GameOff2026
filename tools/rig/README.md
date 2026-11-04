# tools/rig

Local tooling to re-render the character sprite sheets from the Night Shift kit's Blender rig. Nothing here is part of the game build (a `.gdignore` hides it from Godot, and the venv, models, clips and renders are git-ignored).

Setup (done once): Python 3.11, `python -m venv venv`, `venv\Scripts\pip install bpy numpy pillow`, and download `Xbot.glb` + `readyplayer.me.glb` from the three.js repo (`examples/models/gltf/`) next to `anim.py`.

- `anim.py`: the kit's renderer, plus support for Mixamo FBX clips in `clips/` (state `legs_turn`, from `Right Turn.fbx`).
  `venv\Scripts\python anim.py -- guard out legs_turn` renders frames to `out/guard/`.
- `pack_turn.py out\guard game\player\skin\guard`: packs the frames into `legs_turn.png` and adds its entry to the role's `sprites.json`.
- `contact.py`, `match.py`, `cmp.py`, `clip_info.py`: helpers for looking at a clip (contact sheet, measuring its turn angle).

Clip requirements: FBX Binary, Without Skin, In Place, starting and ending in a standing stance.
