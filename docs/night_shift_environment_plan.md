# Night Shift environment plan

Facility 9: map, tiles and gates for the heist game, drawn to sit with the cel-shaded characters of the sprite kit
(https://claude.ai/artifact/3vjw1tkGREJeaXT8mbr5Mc). The characters live in `game/player/skin/`.

## The look: smooth, top-down, no detail
- **Plain floor.** One flat olive-grey (`#22241f`), the same in every room, corridor and outdoor pad. No panels, bolts, seams, wear or variants.
- **Smooth walls.** A wall is one 0.25 m cell: a flat dark navy (`#16203a`) top with a rounded edge, a thin ink outline in `void` (the characters' outline) and
  smooth shading. No pipes, joints, rivets or caps.
- **Smooth gates.** One metre long and one wall thick: two rounded leaves that meet in the middle, a rounded post at each end with a small status light
  (cyan, red when locked), a soft shadow. Exterior gates are a slightly lighter blue. Open gates show only the posts. No ribs, hazard marking or lock bar.
- **Soft shadows** on the floor beside the walls make the flat shapes read as solid: a soft darkening where floor meets wall, and a soft shadow thrown
  toward the bottom right, away from the light. They are a separate tile layer (`Shadows`), so they can be switched off when real lighting arrives.
- No vent art, props or lighting.

## How it is made
Each piece is a height map seen from straight above (a top-down 3D picture), shaded with the sprite kit's light direction (up and to the left). The kit's
character renderer uses three hard bands; the environment uses the same light with a smooth ramp: a flat top gets the base colour, edges turning toward the
light go lighter, edges turning away go darker (the 0.62 and 1.22 tones of the kit's `tone()`). Resolution is 176 px per metre like the cel character sheets,
so a 0.25 m cell is 44 px; in the game everything visual is drawn at scale 0.25 (44 px per metre). `render/env_smooth.gd` computes the pictures and
`render/env_render.gd` writes them to `art/` (headless; the soft shadows take most of the time).
```
godot --headless --path . res://night_shift/environment/render/env_render.tscn -- [--only=floors,walls,shadows,doors]
godot --headless --path . --import        # then keep mipmaps on: mipmaps/generate=true in each art/*.png.import, and import again
```
The earlier detailed look (3D meshes with bevels, pipes, bolts, panel joints, hazard marking, floor wear) is in git history (see `render/env_pieces.gd` in commit
`db45d43`), in case any of it should come back.

## Scale
| Fact | Value |
|---|---|
| World scale | 44 px per metre (render 176 px per metre, drawn at 0.25) |
| Cell | 11 px world, 44 px in the image = 0.25 m (also the wall thickness) |
| Gate | 4 cells = 1 m long, one wall thick |
| Corridor | 8 cells = 2 m wide |
| Room | 7 to 12 m on a side |

## The facility
42 x 28 m, 21 rooms, 24 gates (`facility_layout.json`, checked by `py -3 tools/art/check_layout.py`; converted to the 0.25 m grid by
`tools/art/convert_layout_to_quarter_metre.py`).
- **Main Corridor**: a 2 m wide ring around the interior block.
- **Utility rooms** (the generator-power gameplay): Camera Room, Door Control, Lighting Control, Generator Room, Turret Control, Breaker Room.
  Each has a `function` in the layout (`cameras`, `doors`, `lights`, `generator`, `turrets`, `power`).
- **Item rooms**: Archive, Vault, Locker Room, Records. **Exterior rooms** (intruder entries and exits): Roof Stairwell, Loading Dock, Maintenance Bay, Cafeteria.
- **Offices**: Break Room, Offices. 13 vent positions are listed for the Vent Rat (no art).

Walls are not drawn by hand: every cell touching a floor cell becomes a wall and picks its tile from an 8-neighbour bitmask, so editing the rect list is the whole workflow.

## Files
| File | Job |
|---|---|
| `render/env_smooth.gd` | The pieces: plain floor tile, 256 wall tiles, 256 floor shadow tiles, the gates |
| `render/env_render.gd/.tscn` | Writes the images to `art/` |
| `facility_tileset.gd` | Builds the TileSet in code (floor, walls with collision on physics layer 2 and a light occluder, shadows) |
| `facility_map.gd/.tscn` | Reads the layout; paints floor, shadows and walls; places gates; room queries (`room_at`, `rooms_of_kind`, `doors_of_room`, `room_rects_px`) |
| `facility_door.gd` | Sliding gate, `State.OPEN / CLOSED / LOCKED`, blocks movement (physics layer 4) |
| `facility_test.tscn` | Fly-around viewer: WASD, 1/2/3 zoom, R gates, M overview, B 1 m box; `--ref=` draws a cel character for scale |
| `game/playground/playground_map.tscn` | Single-player playground: this map plus the player in the guard skin (see below) |

## Hooking up the player
- Add players under `FacilityMap/Actors` (y-sorted); the skin node is scaled 0.25.
- Player body collision mask: walls 2 and closed gates 8, plus 1 for other players: `11`, which the player scene already has.
- Projectile world mask: `2` (walls only).

## Playground map and the player skin
- `game/playground/playground_map.tscn` is a single-player test scene: the facility with one `Player` (the friend's scene) in the guard skin. netfox's clock is started
  offline, so the player's rollback tick, input and interpolation work as in a game. WASD moves, the mouse aims, E opens or closes the nearest gate.
  Checks from the command line: `godot --path . res://game/playground/playground_map.tscn -- --shot=out.png [--press=player_down --hold=1.4 --at=484,372 --open=1 --aim=1,0 --zoom=4]`.
- The skin is `game/player/skin/player_skin.tscn`: the kit's `night_shift_character.gd` (class `NightShiftCharacter`) with the smooth cel guard sheets from the kit's `cel/` folder
  (`pixel_art` off), scaled 0.25 to 44 px per metre, linear filtering with mipmaps, plus a soft drop shadow.
- Changes to the friend's player: the icon Sprite2D is replaced by the Skin; the body no longer rotates to face the mouse (the skin turns the legs to the movement and the torso to the
  aim); the collision shape is a 12 px circle (the old 64 px square could not pass a 1 m gate) and `collision_mask` is 11. `Player.interacting` plays the torso's interact animation,
  `died` plays the downed pose.
- Other roles: copy the role's `cel/<role>` folder next to `guard/` and set `role` on the skin node.

## Lighting
Removed for now: no lamps, flashlight or ambient darkness. The old setup (amber banded lamps, flashlight cone) is in git history at `4138938`. The baked floor shadows are the only
light-like thing in the art and live in their own layer.

## Next
1. Lighting, from scratch, once the art is settled (ambient, room lights, flashlights, alarm mode, per-room power).
2. Props (generator, panels, consoles, furniture), only when wanted: the smooth look needs them drawn as the same kind of simple rounded height shapes.
3. Detail, only when wanted and one element at a time.

## Shooting look
- **Shot animation** (the sprite sheets have none, so it is procedural): when a gun fires, Player.shot_fired plays NightShiftCharacter.play_shot(): the torso (and the flashlight on it) kicks back along the barrel and eases forward, and a MuzzleFlash (game/player/skin/muzzle_flash.gd, under the torso at the end of the barrel) shows an additive star for 0.07 s with a short burst of real light that lights the walls in the dark. It plays once per shot, even when a tick is resimulated, because ProjectileManager.spawn() returns false for a repeat. Bullets start at Player.muzzle_distance (28 px) from the player's middle, where the flash is.
- **Bullet art**: ProjectileManager draws each bullet as a small tracer: smooth radial halo, tapered fading streak, bright slug and white-hot tip, all drawn in code. adius (the hit size and the drawn size) went from 8 to 3 px. In the playground the manager sits on its own CanvasLayer so the darkness does not dim the bullets.
