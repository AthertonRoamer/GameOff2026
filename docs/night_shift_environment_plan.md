# Night Shift environment plan

Facility 9: map, tileset, props and lighting for the heist game, drawn to match the cel-shaded characters of the sprite kit
(https://claude.ai/artifact/3vjw1tkGREJeaXT8mbr5Mc). The characters and the player scene are the teammate's work and are not in this repo yet.

## The look: true top-down, cel shaded, made in 3D
The characters were modelled in 3D and photographed from straight above with three flat shading bands and an ink outline (`source/anim.py`
in the kit). The environment is made the same way, so it cannot drift from them:
- Every piece is a 3D model (`render/env_mesh.gd` blocks, `render/env_pieces.gd` pieces) photographed by an orthographic camera looking straight
  down (`render/env_render.gd`). Pure top-down: a wall shows its top, never its front.
- **Same cel material** as the characters (`render/cel.gdshader`): shade = dot(world normal, light), cut into shadow / base / highlight at
  0.38 and 0.9, with the kit's light direction (up and to the left of the picture). Shadow and highlight tones are derived from the base
  colour with the same `tone()` (0.62 and 1.22). Bevels are tilted (28 degrees on lit sides, 47 on shaded sides) so they land in the highlight
  and shadow bands the way the characters' curved forms do.
- **Ink outline** in `void` #07090c, 1 px at 176 px per metre, drawn where a surface steps up from the one beside it (found from a height pass),
  so props outline against the floor and a wall block against open ground.
- **176 px per metre**, the same as the cel character sheets (their `px_per_m` is 176.55). In the game both are drawn at scale 0.25, so the
  world is 44 px per metre. Tile layers are scaled 0.25 and use linear filtering with mipmaps (the images have mipmaps turned on).
- No pixel pass. If one is wanted later it is a post-process on the finished picture, as `pixelate.py` is for the characters.

Rendering is done with Godot, not Blender: there is no Blender here and `bpy` has no build for Python 3.14. The pieces are Godot meshes and
primitives, so Blender models could be dropped in later without changing the cel material or the ink.

## Characters: reverting the pixel look
The kit's pixel sheets are the cel renders run through `pixelate_all.py` (shrink 4x, snap to palette, 1 px outline). To go back to the smooth
cel look: use the kit's `cel/` folder instead of `pixel/` (256 px frames, `px_per_m` 176.55, same `sprites.json` layout) and set
`pixel_art = false` on 
ight_shift_character.gd` (that only controls nearest-neighbour filtering). Scale the character node by 0.25 to get
44 px per metre, and use linear filtering with mipmaps. The characters are not imported in this repo yet, so nothing needed reverting here.

## Scale
| Fact | Value |
|---|---|
| World scale | 44 px per metre (render 176 px per metre, drawn at 0.25) |
| Tile | 22 px world, 88 px in the image = 0.5 m |
| Wall | 1 tile = 0.5 m thick |
| Door | 2 tiles = 1 m wide |
| Corridor | 4 tiles = 2 m wide |
| Room | 7 to 12 m on a side |
| Camera zoom | 2x suggested: a 1152 x 648 view then shows 13 x 7.4 m |

## Palette
All piece colours are Palette A names (`env_mesh.gd` `PAL`, copied from the kit): floors `floor` #1a1f27 / `tile` #222833 / `deep` #151920,
walls `wall` #2a313d with a plain `wall_top` #3a4352 cap, door leaves `uniform` #2b3a55 (`armor` #3c4a63 for exterior doors), door lights `item` #6fd3e8 or
`alarm` #e5484d, hazard stripes `backup` #f2b544. Screens and lights are flat colours with no shading. Because the cel bands are derived from
the base colour (as for the characters), the finished pixels sit slightly outside the 25 named colours.

## The facility
42 x 28 m, 21 rooms, 24 doors (
ight_shift/environment/facility_layout.json`, checked by `py -3 tools/art/check_layout.py`).
- **Main Corridor**: a 2 m wide ring around the interior block.
- **Utility rooms** (the generator-power gameplay): Camera Room, Door Control, Lighting Control, Generator Room, Turret Control, Breaker Room.
  Each has a `function` in the layout (`cameras`, `doors`, `lights`, `generator`, `turrets`, `power`).
- **Item rooms** (what the intruder steals): Archive, Vault, Locker Room, Records.
- **Exterior rooms** (intruder entries and exits): Roof Stairwell, Loading Dock, Maintenance Bay, Cafeteria, each with a heavy exterior door.
- **Offices**: Break Room, Offices. 13 vent grates are listed for the Vent Rat.

Walls are not drawn by hand: every cell touching a floor cell becomes a wall and picks its tile from an 8-neighbour bitmask, so
editing the rect list is the whole workflow.

## How it is built
| File | Job |
|---|---|
| `render/env_render.gd/.tscn` | Photographs the pieces from above and writes the images to `art/` (needs a window). Rendering everything takes about 20 s |
| `render/env_pieces.gd` | The pieces: floor kinds (5 x 4 variants), vent grille, 256 wall tiles, doors (interior / exterior x closed / locked / open x horizontal / vertical), console |
| `render/env_mesh.gd` | Building blocks: beveled plates, studs, flat quads, cel and flat materials |
| `render/*.gdshader` | `cel` (the character material), `flat` (glowing parts), `height` (for the ink) |
| `facility_tileset.gd` | Builds the TileSet in code from `floors.png` and `walls.png`; walls get collision (layer 2) and a light occluder |
| `facility_map.gd/.tscn` | Reads the layout; paints floors and walls; places doors and vents; room queries (`room_at`, `rooms_of_kind`, `doors_of_room`, `room_rects_px`) |
| `facility_door.gd` | Sliding door, `State.OPEN / CLOSED / LOCKED`, blocks movement (layer 4) and light |
| `facility_test.tscn` | Fly-around viewer: WASD, 1/2/3 zoom, R doors, M overview, B 1 m box; `--ref=` draws a cel character for scale |

Re-render after changing a piece:
```
godot --path . res://night_shift/environment/render/env_render.tscn -- [--only=floors,walls,doors,console]
godot --headless --path . --import        # then keep mipmaps on: mipmaps/generate=true in each art/*.png.import
```

## Hooking up the player (for whoever builds the player scene)
- Add players under `FacilityMap/Actors` (y-sorted); scale the character node by 0.25.
- Player body collision mask: `2 | 8 = 10` (walls and closed doors). Projectile world mask: `2` (walls only).
- Drop shadow under the character, as the kit asks.

## Lighting
Removed for now: no lamps, flashlight, ambient darkness or light textures, so the art shows as drawn. Walls and doors still carry light occluders (inert until lights exist). Lighting is the next thing to do, after the art is settled; the old setup (amber banded lamps, flashlight cone) is in git history at `4138938`.

## Status
Done: renderer, simple floors (steel panels, plate, dark steel, asphalt, vent grille), plain walls, doors, console, tileset and map builder on the new art, viewer, screenshots in
`docs/night_shift/`. Replaced: the first flat tiles and the oblique demo, both abandoned.

Next, in this order (each is one more piece in `env_pieces.gd`):
1. **Utility-room props**: generator (2 x 1 m, power gauge), breaker panel, camera monitor desk, door/light/turret consoles, server racks,
   turret mount, wall camera.
2. **Item-room props**: archive shelves, vault safe, lockers, records cabinets, desks, crates, cafeteria tables, vending machine, pallets.
   Solid props get collision (layer 2) and a light occluder; low cover gets layer 3 (blocks bodies, not bullets).
3. **Lighting**: from scratch, once the art is settled (ambient, room lights, flashlights, alarm mode, per-room power).
4. **Vents**: the vent network the Vent Rat travels.
5. **Wall and floor detail**: add back only what is wanted (seams, hazard plates), one element at a time.
