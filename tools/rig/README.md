# tools/rig

Local tooling to re-render the character sprite sheets from the Night Shift kit's Blender rig. Nothing here is part of the game build (a `.gdignore` hides it from Godot, and the venv, models, clips and renders are git-ignored).

Setup (done once): Python 3.11, `python -m venv venv`, `venv\Scripts\pip install bpy numpy pillow`, and download `Xbot.glb` + `readyplayer.me.glb` from the three.js repo (`examples/models/gltf/`) next to `anim.py`.

- `anim.py`: the kit's renderer, plus support for Mixamo FBX clips in `clips/` (state `legs_turn`, from `Right Turn.fbx`).
  `venv\Scripts\python anim.py -- guard out legs_turn` renders frames to `out/guard/`.
- `pack_legs.py out\guard game\player\skin\guard <state> <frames> <fps> <loop 0/1>`: packs rendered frames into `<state>.png` and adds its entry to the role's `sprites.json` (`pack_turn.py` is the older single-purpose version for `legs_turn`).
- States from clips: `legs_turn` (Right Turn.fbx), `legs_strafe_walk` (Walk Strafe Right.fbx), `legs_strafe_run` (Right Strafe.fbx), plus their upper bodies `torso_strafe_walk`, `torso_strafe_walk_aim` and `torso_strafe_run`. `yaw_offset` in a state squares a clip's body up to face forward.
- `contact.py`, `match.py`, `cmp.py`, `clip_info.py`: helpers for looking at a clip (contact sheet, measuring its turn angle).

Clip requirements: FBX Binary, Without Skin, In Place, starting and ending in a standing stance.
