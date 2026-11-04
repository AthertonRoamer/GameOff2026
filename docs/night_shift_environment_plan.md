# Night Shift environment plan

Facility 9: map, tileset, props and lighting for the heist game. Everything here is built to the sprite kit's scale and Palette A
(https://claude.ai/artifact/3vjw1tkGREJeaXT8mbr5Mc). Characters and the player scene are not part of this work.

## Scale, from the sprite kit
| Fact | Value |
|---|---|
| Pixels per metre | 44 (the kit measures 44.1) |
| Character frame | 64 px (88 px for the gunner), shoulders about 22 px wide |
| **Tile** | **22 px = 0.5 m** |
| Wall thickness | 1 tile = 0.5 m |
| Door | 2 tiles = 1 m wide |
| Corridor | 4 tiles = 2 m wide (two players can pass with a flashlight each) |
| Room | 7 to 12 m on a side |
| Camera zoom | whole numbers only (2x recommended: a 1152 x 648 view then shows 13 x 7.4 m) |

A 44 px tile would also be one metre, but a 22 px grid lets walls be thin and doors one metre wide without exceptions.
Change `T` in `tools/art/make_facility_art.py` and `TILE` in `facility_tileset.gd` together if a different grid is wanted.

## Palette mapping
| Surface | Palette A colour |
|---|---|
| Void, outside the building | `void` #07090c |
| Outdoor asphalt, vault steel | `deep` #151920 |
| Corridor concrete, room tile (dark) | `floor` #1a1f27 |
| Room tile (light), utility plate | `tile` #222833 |
| Wall face | `wall` #2a313d |
| Wall edge lit from the top left | `wall_top` #3a4352 |
| Door panel, vent bolts | `metal` #5a6475 |
| Lamps, unlocked door lights, hazard stripes | `backup` #f2b544 |
| Generator room lamp | `warm` #e07b2a |
| Locked door light, alarms | `alarm` #e5484d |
| Flashlight | `flashlight` #fff3c4 |

All environment pixels come from these colours; the generator is deterministic. The light stays at the kit's fixed top-left direction:
walls throw a long contact shadow to their bottom right and a thin one to their top left. 1 px ink outline (`void`) on every open wall edge.

## The facility
42 x 28 m, 21 rooms, 24 doors (`night_shift/environment/facility_layout.json`, checked by `py -3 tools/art/check_layout.py`).

- **Main Corridor**: a 2 m wide ring around the interior block.
- **Utility rooms** (the generator-power gameplay): Camera Room, Door Control, Lighting Control, Generator Room, Turret Control, Breaker Room.
  Each has a `function` in the layout so game code can find it (`cameras`, `doors`, `lights`, `generator`, `turrets`, `power`).
- **Item rooms** (what the intruder steals): Archive, Vault, Locker Room, Records.
- **Exterior rooms** (intruder entries and exits): Roof Stairwell (north), Loading Dock (south), Maintenance Bay (west), Cafeteria (east).
  Each has a heavy exterior door onto a small outdoor pad.
- **Offices**: Break Room, Offices. 13 vent grates are listed for the Vent Rat.

Walls are not drawn by hand: every cell touching a floor cell becomes a wall and picks its tile from an 8-neighbour bitmask, so
editing the rect list is the whole workflow.

## How it is built
| File | Job |
|---|---|
| `tools/art/make_facility_art.py` | Draws floors (5 kinds x 4 variants), walls (256 neighbour masks), contact shadows, 6 door sheets x 2 orientations, vent grate, banded light textures into `night_shift/environment/art/` |
| `facility_tileset.gd` | Builds the TileSet in code: floors, walls (collision layer 2 and light occluder), shadows |
| `facility_map.gd/.tscn` | Reads the layout; paints floors, walls, shadows; places doors, vents and lamps; room queries (`room_at`, `rooms_of_kind`, `doors_of_room`, `room_rects_px`) |
| `facility_door.gd` | Sliding door, `State.OPEN / CLOSED / LOCKED`, blocks movement (layer 4) and light |
| `facility_lamp.gd` | Amber banded ceiling lamp with shadows, `set_powered()`, optional flicker |
| `flashlight.gd` | Banded 56 degree cone, 11.6 m, plus a small halo; add to a player and rotate to aim |
| `facility_test.tscn` | Fly-around viewer: WASD, 1/2/3 zoom, F flashlight, L lamps, R doors, M overview, B 1 m reference box |

## Hooking up the player (for whoever builds the player scene)
- Add players under `FacilityMap/Actors` (y-sorted).
- Player body collision mask: `2 | 8 = 10` (walls and closed doors).
- Projectile world mask: `2` (walls only), the same value the rollback demo already uses.
- `Flashlight` goes under the player node, `flashlight.aim_at(world_point)` or `rotation = aim.angle()`.
- Drop shadow under the character, as the kit asks.

## Lighting
Mains power is out, so the world is dark and lit only by what the generator feeds.
- `Ambient` (CanvasModulate, `#4d5775`-ish) keeps layout readable; lit areas show the true palette colours.
- Ceiling lamps: amber, one per 7 m, four flat brightness steps to match the cel shading, hard shadows so no light crosses a wall.
  Generator room is orange (`warm`).
- Flashlights: warm white cone, shadows from walls and closed doors.
- All lamp and flashlight textures are banded (no smooth falloff). Everything uses nearest-neighbour filtering (set on the map root).

## Status
Done in the first slice: scale decisions, art generator, tileset, layout and checker, map builder, doors, vent grates, lamps,
flashlight, fly-around viewer, screenshots (`docs/night_shift/`).

Next, in this order:
1. **Utility-room props**: generator (2 x 1 m, with a power gauge that can show amber or red), breaker panel (wall), camera monitor desk,
   door/light/turret control consoles, server racks, turret mount, wall-mounted camera. Same generator pipeline, 22 px grid, 1 px ink outline.
2. **Item-room props**: archive shelves, vault safe, lockers, records cabinets, desks, crates, cafeteria tables, break-room couch and
   vending machine, loading-dock pallets. Solid props get collision (layer 2) and a light occluder; low cover gets layer 3 (blocks bodies, not bullets).
3. **Lighting states**: alarm mode (flashing `alarm` red), per-room power (`set_powered` from the light control room), dark rooms by default,
   light-switch props. Optional palette-snap post-process so lit colours stay inside Palette A.
4. **Vents**: the vent network the Vent Rat travels (needs a decision on how it is drawn and navigated).
5. **Hand polish**: the generated art is deliberately simple and consistent; swap in hand-drawn tiles over the same atlas layout whenever wanted.

## Decisions to confirm
- 22 px tile (recommended) versus 44 px.
- Camera zoom 2x with the template's 1152 x 648 viewport, or a different base resolution.
- Project-wide nearest filtering (`rendering/textures/canvas_textures/default_texture_filter`). Not changed yet, so the character
  teammate's work is untouched; the map sets nearest on its own root node.
- Map size and room list above (it is a first pass, the layout file makes changes cheap).
