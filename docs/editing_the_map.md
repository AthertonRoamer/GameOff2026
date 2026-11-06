# Editing the map in the editor

The facility is a scene: `night_shift/environment/facility_map.tscn`. Open it, look at the 2D view, and edit nodes. (It used to be built at runtime from
`facility_layout.json`; `tools/art/convert_layout_to_scene.gd` made the scene from that file once, and the JSON, `tools/art/check_layout.py` and
`convert_layout_to_quarter_metre.py` are only history now.)

## What is in the scene
| Node | What it is | How you edit it |
|---|---|---|
| `Rooms` > `FacilityRoom` | one room: the node **name is the room id** (`door_control`). Settings: `display_name`, `kind`, `function` (which console works there) | its floor is its `FacilityRoomRect` children (`Control` nodes, drawn as a coloured box with the room's name): click the room in the 2D view or the scene tree, select a rectangle and drag its corner and edge handles, or type position and size in the inspector. Several rectangles make an L-shaped or ring-shaped room. Everything snaps to the 11 px grid (0.25 m) by itself. To add a room: add a `FacilityRoom` under `Rooms`, add a `FacilityRoomRect` under it, drag it to size, set `kind` |
| `Doors` > `facility_door.tscn` | a sliding gate, 4 cells (1 m) wide | drag into the wall between two rooms (the wall is the one cell gap between them). Tick `horizontal` off for a gate in a vertical wall. Which rooms it joins, and whether it leads outside, are worked out from what is on each side |
| `Vents` > `Marker2D` | vent position (top left of a 2 x 2 cell grille) | move the marker |
| `Props` | things that stand on the floor, y-sorted | drag in `game/utility/door_control_panel.tscn` (or any `ControlPanel` scene) |
| `Actors` | where players are added at runtime | leave it |
| (`Floors`, `Walls`, `Shadows`) | tile layers the map **makes and fills in itself** from the rooms and doors, in the editor and in the game. They are not in the scene file, so you cannot select or paint them, and resizing a room never touches the art | a moment after you change a room or door they are rebuilt; the *Rebuild* button on the `FacilityMap` node forces it |

Rooms need a one cell gap between them: every empty cell touching a floor cell becomes a wall. The editor tells you when something is wrong: a room that overlaps another shows `overlaps <room>` in red and a warning triangle in the scene tree, and so does a door that is not in the wall between two different rooms.

## Consoles
A console is a `ControlPanel` scene (`game/utility/control_panel.tscn`; `door_control_panel.tscn` inherits it and sets `title`, `function = "doors"` and
`screen_scene`). Put one under `Props` inside the room whose `function` it works. `UtilityConsoles` finds every console under `Props` when the level
starts and gives it its screen; nothing is registered in code. A new kind of console: a screen scene (a `Control` with `open(player)`, `close()` and a
`closed` signal), plus an inherited `control_panel.tscn` pointing at it.

## Player visuals
`game/player/skin/player_skin.tscn` is a real scene now: `Legs`, `Torso` and `Full` have the guard's `SpriteFrames` (`guard/guard_frames.tres`) assigned, so
every animation can be previewed; the `Flashlight` has `Cone` and `Halo` `PointLight2D` children, the `Muzzle` has its `Light`, and the shoulder lamp and
muzzle star are tool scripts that draw in the editor with colours you can change. After the sheets or `sprites.json` change (`tools/rig`), re-run
`godot --headless --script res://tools/art/bake_skin_frames.gd` to rebuild `guard_frames.tres`. Another role's skin = another frames resource and
`sprites.json`, assigned on the Skin node (`sprite_frames`, `sprite_data`).

## Tools (godot --headless --path . --script res://tools/art/<name>.gd)
- `bake_facility_tileset.gd`: rewrites `facility_tileset.tres` (the wall/floor/shadow tile set, with its collision and light occluders)
- `bake_skin_frames.gd [-- role]`: rewrites `<role>_frames.tres`
- `dump_facility.tscn` (run as a scene): prints a summary of the built map, to compare two versions of it
- `convert_layout_to_scene.gd`: the one-time JSON to scene conversion (do not run it again, it overwrites the scene)

## Checks
`tests/unit/test_facility_map.tscn` (in `tests/run_all.ps1`): no two rooms share a cell, every door joins two different rooms and sits on the grid, the
floor and wall layers match, every console stands in a room whose function it works and has a screen. Run it after editing the map.