# Furniture

Everything that stands on the facility's floor and is only there to make a room look like a room: desks, crates, racks, lockers, plants.
The small map's furniture is in `game/environment/facility_map.tscn` under **Props / Furnishing**, one group per room (`Archive`, `BreakRoom`, `Office`...).

## Moving, adding and removing furniture (in the editor)

1. Open `facility_map.tscn`. Open `game/furniture/items/` in the FileSystem dock.
2. **Add:** drag an item (`desk_n.tscn`, `crate_wood.tscn`...) into the 2D view, or onto the room's group in the scene tree. Put it under the group of the room it is in
   (or make a new `Node2D` group). The pieces must be under **Props** (the lobby needs them near every player).
3. **Move:** drag it. When you let go its edges snap to the half cell grid (5.5 px) so a side sits exactly on a wall. Turn off `snap` on the piece to place it anywhere.
4. **Remove:** select it and delete it. **Copy:** Ctrl+D.
5. A piece tells you when it is wrong: its outline in the 2D view goes red and the scene tree shows a warning (sticks out of its room, covers a door's way, is on a spawn,
   an item location, a vent or a console, or overlaps another solid piece). Keep these clear, `tests/unit/test_furniture.tscn` fails on any of them.

### Which way a piece faces

Pieces with a front come in four turns: `desk_n` is a desk whose user looks north (up the screen), `desk_e` looks east, `desk_s` south, `desk_w` west. Against a north wall,
a cabinet or a couch faces south (`_s`); against a south wall, north (`_n`). The turns are drawn separately so the light still comes from the top left. Do not rotate a
piece with the rotate tool: use the turn you need (a rotated one keeps its highlights on the wrong side).

## What a piece does

A piece is one `Furniture` node (`furniture.gd`). The sprite, the collision and the light occluder are made from its settings when it loads, nothing else is saved:

| setting | |
|---|---|
| `texture` | the picture (176 px per metre, shown at 0.25) |
| `footprint` | **Rectangle** or **Circle**: what stops players and shots, throws a shadow from a flashlight and blocks the view. **None**: lies on the floor (a pallet), walked over |
| `footprint_size` | world pixels. The items are saved 2 px inside their picture, so what you see is what stops you |
| `height` | how tall it is in metres (chair 0.45, table 0.75, rack 2.3): it decides which shadows fall on it, see below |
| `snap` | edge snapping while you drag |

**Lighting and heights.** A piece's occluder only shades *behind* it (`CULL_COUNTER_CLOCKWISE`), so a flashlight lights its top like the floor and the shadow falls on the far
side. A shadow falls on something only when what throws it is **taller**: a chair's shadow lies on the floor but not on the table beside it, a rack's lies on the table, a
wall's on everything. `height` sorts a piece into a tier (`game/environment/light_layers.gd` has all of it): **low** under 0.6 m, **mid** under 1.5 m, **tall** above (a piece
with no footprint lies flat, like the floor). The top of a tall piece takes only 35% of a flashlight (`furniture_top.gdshader`), being out of the beam's reach.
It works with Godot's light layers: each tier's pictures and occluders are on their own layers, and the player's flashlight is four lights (made from the one in the scene by
`Flashlight`, see `LightLayers.add_height_cones`), each lighting one tier and taking the shadows of what is taller. A picture is lit by one of them, so lighting costs what one
beam does. A light of your own (a lamp, a screen's glow) should call `LightLayers.make_heightless(light)` to light furniture of every height and take every shadow.

## Performance

- A map's furniture is always there (the lobby needs the collision), but it costs little: a piece is a body, a sprite and an occluder, and pieces of one kind share their
  collision shape and occluder polygon. Pictures are trimmed to their silhouette and mipmapped.
- Flashlight shadows are what costs: one set of occluders per beam. The four height beams each take only the occluders taller than what they light, so the work is not four
  times one beam's. `tools/preview/furniture_preview.tscn` with `bench` times it (frames at five spots with no furniture, with furniture and one beam, with furniture and the real
  four beams).
- Streaming: `MapStreamer` keeps a piece's picture and shadow (`Furniture.set_shown`) in the tree only within 24 cells of the view. Its body is always there. Every shadowed light
  goes through every occluder in the tree each frame, so on the big map this took a match from about 30 to about 24 ms a frame (measure with `HARNESS_PERF=1` and
  `HARNESS_MATCH='{"map": 1}'` on `tests/harness/run_smoke.ps1 -SoakSeconds 30`).
- Only the local player's flashlight is a scene light (other players' beams are drawn by `PlayerSight`), so there are four beams in the scene, not four per player.
## Making a new piece

*Easiest:* in the editor, duplicate an item scene, change `texture` (a PNG facing the top of the screen, lit from the top left, 176 px/m) and `footprint_size`.

*Drawn in code* (like the existing ones): add a draw function to `tools/art/make_furniture.py` (it uses the helpers in `tools/art/make_props.py`) and a line in `ITEMS`, then

```
python tools/art/make_furniture.py
```

This draws every sprite with the characters' cel look (hard tone bands, 1 px ink, `Palette` colours), trims each to its silhouette, fits the footprint to it, writes
`game/furniture/art/<name>.png` and `game/furniture/items/<name>.tscn` (all four turns if you say so). Open the editor once afterwards so the new pictures are imported
(or run `Godot --headless --import`). `python tools/art/furniture_sheet.py out.png` draws a contact sheet of all of them.

## Notes

- `FacilityMap.random_floor_point()` (deathmatch respawns) and `FacilityMap.is_clear(point)` know about furniture: nobody comes back inside a desk.
- The big map (`facility_map_wings.tscn`) is furnished the same way (about 1900 pieces, grouped by room under Props/Furnishing); test it with `res://tests/unit/test_furniture.tscn -- res://game/environment/facility_map_wings.tscn` (add `big` to the preview tool's arguments to render it).
- `tools/preview/furniture_preview.tscn` renders the furnished map with the game's darkness and a flashlight, to look at lighting and shadows (needs a window).
