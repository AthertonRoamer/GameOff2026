# The campus map

`game/environment/facility_map_wings.tscn` is a big, lopsided map to furnish in the editor: 166 x 144 m, **120 rooms, 328 doors, about 19,500 m2 of floor** (the old map is 30 x 14 m, about
1,000 m2 of floor with the pads). Open it like `facility_map.tscn` (see `editing_the_map.md`): rooms are `FacilityRoom` nodes, doors are `facility_door.tscn` in the walls.
The game still uses the old map; nothing points at this one yet. The picture of it is `docs/night_shift/map_wings_plan.png`.

`tools/art/generate_wings_map.py` made the scene once. **Do not run it again** once you have edited the scene: it overwrites it. It also prints the walking distances below.

## Shape
There are no courtyards: the whole footprint is rooms and corridors, with a small outdoor pad only where somebody comes in or goes out.
- A **Central Atrium** (30 x 22 m) with four wings of different lengths and shapes. Nothing is mirrored.
  - **North, Security**: a corridor up from the atrium ending in a concourse along the front: armory, evidence, interview rooms, cameras, turrets, a guard post.
  - **East, Power**: a 46 m corridor past a 24 x 17 m generator hall and the breakers, ending in a vertical concourse, the loading dock and a rail platform.
  - **South, Staff**: a corridor down to a concourse along the back: barracks, an 18 m cafeteria, infirmary, vehicle bay, fuel depot.
  - **West, Research**: a corridor with labs either side, vault, records and server room, ending in a vertical concourse and the service tunnel.
- **Four corner blocks**, each a branching network of 4 m corridors with rooms off every branch (the main corridors are 6 m):
  - **NW, Administration** (archive, offices, conference room): off the north and west corridors.
  - **SW, Warehouse** (receiving, cold storage, workshops): off the west and south corridors.
  - **NE, Aviation** (the helipad hangar, flight ops, crew rooms, stores): reached only from the east wing.
  - **SE, Rail and cargo** (freight bays, rail office, switch room, loco shed): reached only from the east wing.
- **Gap fillers** between them (service chase and utility core, link corridors, truck and wash bays, admin offices and comms room) so nothing is left empty, and a second route between
  most areas, so there are loops and not only dead ends.
- A wing meets the atrium through a **gate**, two doors side by side: close both and the wing is cut off. A branch corridor meets a main one the same way.

## Room names tell you what they are for
| Prefix | Meaning | Rooms |
|---|---|---|
| `spawn_*` | where guards can start, one in each wing, a few metres from the atrium | `spawn_north` Guard Post, `spawn_east` Crew Room, `spawn_south` Barracks, `spawn_west` Staff Lounge |
| `entrance_*` | the intruder's ways in (all touch the outside) | `entrance_north` Gatehouse and `entrance_garage` (north pad), `entrance_south` Cargo Garage and `entrance_service` (south pad), `entrance_west` Service Tunnel (west pad) |
| `extract_*` | the intruder's ways out | `extract_east` Loading Dock and `extract_rail` Rail Platform (east pad), `extract_helipad` Hangar (the helipad, north east) |
| `doors_*` | each wing's door control room, with its panel | `doors_north`, `doors_east`, `doors_south`, `doors_west` |

The ways in are in the west, north and south and the ways out in the east, and the corner blocks on the east are only reached through the east wing, so the long walk is built in.
Walking distances (door to door through the rooms): **entrance to extract 117 to 161 m** (26 to 36 s at walking pace), **spawn to the nearest extract 53 to 89 m**.

Other rooms: `*_corridor` the main corridors, `north_armory`, `north_cameras` (camera console), `north_turrets` (turret console), `east_generator` (generator), `east_breakers` (power),
`west_lights` (lights console), `west_vault`, `west_records`, `south_cafeteria`, the corner blocks' rooms (`nw_*`, `sw_*`, `ne_*`, `se_*`) and so on. Six **artifact spots**
(`ArtifactLocations`): armory, evidence room, generator hall, cafeteria, vault, records.

## Loading in and out
A map this size cannot be built whole every time, so it is streamed (`game/environment/map_streamer.gd`, made by the `FacilityMap`; settings under *Streaming* on the `FacilityMap` node):
- **Tiles** (floor, shadows, walls) are painted a chunk (16 x 16 cells, 4 m) at a time, only near the view, nearest first, a few milliseconds a frame, and erased once the view is
  further away. The game opens with the view's chunks already painted. In the editor the same thing follows the 2D view, so the editor stays fast on this map.
- **Decor**: a `Decor` node on the map (there is one, empty) is for furniture and clutter that is only looked at: sprites and lights, **no collision, nothing the game asks about**.
  Its children are taken out of the tree when the view is far (`decor_margin_cells`) and put back as it comes near. Anything that blocks a shot or a player, or that is a console,
  belongs under `Props` instead: it is always there, because the lobby needs it near every player and not only near this peer's camera.
- Always there, because they are cheap: the walls' collision and light occluders (594 rectangles), the doors, the rooms' data. A dedicated server paints nothing.
- Measured here: building the map takes 1.8 s, the sound grid 40 ms, and flying across the whole map at three times running speed gave a median frame of 16.7 ms and a worst of 33 ms.
  `tests/unit/test_map_streaming.tscn` covers it.
- `FacilityMap` no longer keeps a dictionary of every floor cell: it keeps the rooms' rectangles and answers `room_of_cell`, `is_floor` and `room_at` from them. `paint_all()` paints
  everything for a test or a tool.

## What this map does not do yet (code for later)
- **Spawn, entrance and extract choosing** is not coded. Level's `spawn_room` is `"ring"` (the old map), so pointing the level at this map means setting it to a room that exists here.
- **A door panel per wing**: the four panels are placed (one in each `doors_*` room) and all have `function = "doors"`. Today `UtilityConsoles.panel_for("doors")` expects one, and the
  door screen lists every door, so each panel opening only its own wing's doors needs code. The corner blocks' gates belong to the wing they attach to (NW and the link corridors to north
  and west, SW to west and south, NE and SE to east).
- **Vents** is empty. **Consoles** for cameras, turrets, lights, generator and power are not placed (their rooms are marked with the right `function`).
- Every room is empty floor: the furnishing is yours.
- The editor side of the streaming (following the 2D view) was written but only the game side was run here: if tiles do not appear in the editor, turn `stream_tiles` off on the
  `FacilityMap` (everything is painted at once, slowly) and tell me.
