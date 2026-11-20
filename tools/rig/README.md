# tools/rig

Renders a role's character sprite sheets in Blender and packs them into the game. Nothing here is part of the game build: `.gdignore` hides the folder from Godot, and the venv, the models, the clips and the renders are git-ignored (they stay on your machine).

```
tools/rig/
  build_skin.ps1     one command: render, pack, import into Godot, bake        <- start here
  anim.py            the renderer (runs in Blender): the character, the gait recipes, the poses
  pack/              turns rendered pictures into the game's sheets and sprites.json
    pack_skin.py       the driver: runs the others in order      sheets.py   how each sheet is played and how big it is drawn
    pack_trimmed.py    the sheets                                pack_transitions.py   the transitions
    pack_shoulders.py  the lamp's shoulder positions             end_pose.py   where each fall ends up
  measure/           looking at a Mixamo clip before using it (clip_lift.py, clip_head.py, clip_death.py)
  assets/            Xbot.glb, readyplayer.me.glb and clips/ (Mixamo FBX: Without Skin, In Place, FBX Binary)
  out/               renders and packing work, one folder per role
  venv/              Python 3.11 with bpy, numpy and pillow
```

## Setup (once)
`python -m venv venv`, `venv\Scripts\pip install bpy numpy pillow`, and put the models (`Xbot.glb` and `readyplayer.me.glb`, from the three.js repo's `examples/models/gltf/`) and the clips in `assets/`.

## Building a skin
```
tools\rig\build_skin.ps1 -Role guard -Godot "C:\path\to\Godot_console.exe"              # everything: over an hour
tools\rig\build_skin.ps1 -Role guard -Godot ... -Only torso_draw,legs_side_walk         # just these (a trailing * matches a prefix: torso_tr_*)
```
It writes `game/player/skin/<role>/`: the sheets, `sprites.json` (per sheet: frame layout, fps, offset, scale, the lamp's shoulder in every frame, where a fall ends) and the baked `<role>_frames.tres`, then Godot imports the sheets compressed (BC7). The skin scene reads those; see `game/player/skin/night_shift_character.gd`.

## The sheets
Every sheet is named `<layer>_<what>`. The layers are `legs` (bottom, turned in the game to run along the movement), `torso` (turned to the aim) and the falls (`death_*`, a whole body replacing both).

- **Gaits**: `legs_` and `torso_` + `walk`, `run`, `side_walk`, `side_run`, `back`, `back_run`. All are 12 frames, Mixamo clips from the locomotion pack timed so the lead foot comes down at the same point of the cycle (`LIFT` and `CLIPSPEC` in anim.py), so any two can be switched or blended at the same frame. A sideways step is to the right; the game mirrors it for the left. There is no backwards run clip: `back_run` is the walk with its swing pushed past the clip's own pose (`damp` 1.6). The legs' sideways sheets are a shuffle made with leg IK (`shuffle_pose`), not a clip, because none of the clips has one.
- **Standing**: `legs_idle`, `torso_idle` (holstered), `torso_idle_aim` (gun out), `torso_interact`, `torso_draw` (the right hand takes the gun from the holster and brings it to the aim; played backwards to holster), `legs_turn` (a turn on the spot).
- **Transitions** (blended pose by pose in Blender, 6 frames): `<layer>_tr_<from>_<to>_<frame>` between idle and every gait (legs and torso) and between neighbouring gaits (torso), from the stride frame `<frame>`; and `torso_flip_<walk|run>_<quarter>`, the torso swinging from a strafe to its mirror image. `_transitions()` and `_flip()` in anim.py.
- **Falls**: `death_front`, `death_front_right`, `death_right`, `death_back_right`, `death_back`, from three Mixamo clips (the two in between are blends), 18 frames, the clip's own movement kept. The game turns the body to land away from the shot. `end_pose.py` records where each ends up.

How a sheet is played (fps, looping) is in `pack/sheets.py`, with its drawn size (`GAIT_SCALE`: sideways steps 97%, backwards 105%) and the forward sheet each sideways and backwards torso's head is lined up with (`HEAD_REFERENCE`), so the head does not jump when the sheet changes. The transitions are moved and resized along with their frames.

## Changing things
- The look (colours, gear, weapon) is `ROLES` and `PAL` in anim.py; every frame re-renders in the new look.
- A gait's pose is its `CLIPSPEC` entry: `lift` (where in the clip the left foot is highest, from `measure/clip_lift.py`), `yaw_legs` / `yaw_torso` (squaring the sheet up; `measure/clip_head.py` for the torso), `damp` (a gentler or bigger swing than the clip).
- A new clip needs: Mixamo, FBX Binary, Without Skin, In Place, starting and ending standing. Put it in `assets/clips/`.
- `legs_turn` was rendered from `Right Turn.fbx`, which is no longer in `assets/clips/`; put it back to re-render that sheet.

Pictures and poses are 176 px per metre (`PPU`); the skin node is scaled 0.25, so the game shows 44. About 40 MB of video memory per role with the sheets compressed.
