# Editing the map in the editor

The facility is a scene: `game/environment/facility_map.tscn`. Open it, look at the 2D view, and edit nodes. (It used to be built at runtime from
`facility_layout.json`; `tools/art/convert_layout_to_scene.gd` made the scene from that file once, and the JSON, `tools/art/check_layout.py` and
`convert_layout_to_quarter_metre.py` are only history now.)

## What is in the scene
| Node | What it is | How you edit it |
|---|---|---|
| `Rooms` > `FacilityRoom` | one room: the node **name is the room id** (`door_control`). Settings: `display_name`, `kind`, `function` (which console works there) | its floor is its `FacilityRoomRect` children (`Control` nodes, drawn as a coloured box with the room's name): click the room in the 2D view or the scene tree, select a rectangle and drag its corner and edge handles, or type position and size in the inspector. Several rectangles make an L-shaped or ring-shaped room. Everything snaps to the 11 px grid (0.25 m) by itself. To add a room: add a `FacilityRoom` under `Rooms`, add a `FacilityRoomRect` under it, drag it to size, set `kind`. Rooms can be renamed, split or deleted freely: the only thing that names a room is a map option's `spawn_room` (`game/match_setup/maps/`), and if it is empty or names a room that is gone, players start in the biggest corridor (`FacilityMap.start_room`). A room with no rectangle yet is ignored until it has one. A split room's pieces each need their `region` set again |
| `Rooms` > `FacilityRoom` with `kind` = Exit | an **exit zone** (`exit_north` and the rest, green in the 2D view). It is an area, not a room: no floor or wall is painted on it. It sits outside a room's wall, with the same one cell gap as between two rooms, and a door in that wall (`Door_pad_north_exit_north` and the rest) leads into it. Those are ordinary doors, worked from the door console like any other. It is ringed by invisible walls (collision only, no art), so players can step through the door into it but not wander off into the void. Each match `DesignatedExitChooser` (in `game.tscn`) picks one exit at random, and only that one counts: an attacker who stands in it carrying the target artifact wins (`ArtifactEscape`). Attackers see it on the map while they choose where to start. Whether a secretly attacking guard counts is `attacking_guards_win_by_escaping` on `MatchDirector` | like a room: drag its `FacilityRoomRect`. To add one: a `FacilityRoom` under `Rooms`, a `FacilityRoomRect` under it, `kind` = Exit, placed one cell outside a room, then drag a `facility_door.tscn` into the wall between them. An exit in or against a room's floor gets a warning |
| `Doors` > `facility_door.tscn` | a sliding gate, 4 cells (1 m) wide | drag into the wall between two rooms (the wall is the one cell gap between them). Tick `horizontal` off for a gate in a vertical wall. Which rooms it joins, and whether it leads outside, are worked out from what is on each side |
| `Vents` > `Marker2D` | vent position (top left of a 2 x 2 cell grille) | move the marker |
| `Props` | things that stand on the floor, y-sorted | drag in `game/utility/door_control_panel.tscn` (or any `ControlPanel` scene) |
| `ArtifactLocations` > `ArtifactLocation` | a spot where an artifact can be. `ArtifactPlacer` (in `game.tscn`) puts a different random artifact on each one every match | move the marker, or add another `ArtifactLocation` node. There must not be more of them than artifacts |
| `ItemRooms` (`FacilityItemRooms`) | the rooms where **items can be found lying about**, and the list of items (`items`) that can turn up. Each match, when it loads, every item room rolls its chance (`item_chance` on the room, 30% to start with); on a hit one item, picked at random from `items`, lies along one of the room's walls (1.5 cells in), never on or next to furniture, a console, a generator, a turret, a vent or a marker, and never in front of a door (`FacilityMap.item_spots`). Nothing turns up later. They are ordinary pickups (E takes, G drops), drawn only where the player can see (the view cone, or a room on a live camera on the door console). No map shows them | select `ItemRooms` (scene tree, or its badge above the top left of the map): item rooms light up with their chance, the rest dims. Click a room in the 2D view to make it an item room, again to stop (shift-click only adds, Ctrl+Z undoes). Set a room's chance in the inspector under *Item spawns* (select several rooms to set them all). A room can have its own list there too (`item_pool`, an armory finding weapons): an empty one uses the map's `items`. Item rooms show `ITEMS 30%` under their name, and `OWN LIST` when they have one. List an item twice to make it twice as likely. Never list a relic: relics have their own rules (`ArtifactLocations`) |
| `Spawns` > `GuardSpawn` / `IntruderSpawn` | makes the room it **stands on** a spawn room: guards (secretly attacking ones too) or intruders may choose to start there (the spawn selection phase). Only its position counts, not where it sits in the tree; it is also where players who pick that room appear, side by side. Spawn rooms show a dashed frame and a "GUARD SPAWN" / "INTRUDER SPAWN" badge in the 2D view (blue for guards, red for intruders, the same colours as on the spawn selection map, which shows both kinds to everyone) | drag the marker onto a room; the badge moves a moment later. To add one, add a `Marker2D` under `Spawns` and give it `guard_spawn.gd` or `intruder_spawn.gd`. A marker on a wall, in the void or on an exit zone gets a warning |
| `Actors` | where players are added at runtime | leave it |
| (`Floors`, `Walls`, `Shadows`) | tile layers the map **makes and fills in itself** from the rooms and doors, in the editor and in the game. They are not in the scene file, so you cannot select or paint them, and resizing a room never touches the art | a moment after you change a room or door they are rebuilt; the *Rebuild* button on the `FacilityMap` node forces it |

Rooms need a one cell gap between them: every empty cell touching a floor cell becomes a wall. The editor tells you when something is wrong: a room that overlaps another shows `overlaps <room>` in red and a warning triangle in the scene tree, and so does a door that is not in the wall between two different rooms.

## Consoles
A console is a `ControlPanel` scene (`game/utility/control_panel.tscn`; `door_control_panel.tscn` inherits it and sets `title`, `function = "doors"` and
`screen_scene`). Put one under `Props` inside the room whose `function` it works. `UtilityConsoles` finds every console under `Props` when the level
starts and gives it its screen; nothing is registered in code. A new kind of console: a screen scene (a `Control` with `open(player)`, `close()` and a
`closed` signal), plus an inherited `control_panel.tscn` pointing at it.

## Regions and power
The facility has lost power. Guards start backup generators, and everything the security system does costs power while it is on. Power is a flow, in
points per second (pts/s): generators give it, and closed doors and lights that are on (later cameras and turrets) take it. The code is in `game/power/`. `PowerGrid`
does the counting, and the lobby decides every change.

- **Regions** are `FacilityRegion` nodes under the map's `Regions` node. The node name is the region id; `display_name` and `colour` are its settings.
  Each one is drawn in the 2D view as a name badge, which the map moves to the middle of the region's biggest room.
  - **To see a region's rooms**, click its badge in the 2D view or select it in the scene tree. Its rooms light up in its colour, its outline is drawn
    and every other room is dimmed. The *Select its rooms* button in the inspector selects the rooms themselves.
  - **To add or remove rooms**, keep the region selected and click rooms in the 2D view. A click adds a room, or takes it out if it is already in.
    Shift-click only adds. A room is in one region at a time, so clicking a room of another region moves it here. Ctrl+Z undoes it. Ctrl- or
    Alt-click selects normally. This is the `addons/facility_editor` plugin; turn it on under Project Settings > Plugins if it is off.
  - The membership is stored on the rooms: each `FacilityRoom` has a `region` dropdown. Select several rooms and set it once to assign them all.
  - Each room shows a band in its region's colour, with the region's name under the room's name.
- **Generators**: drag `game/power/generator.tscn` under `Props`, standing in a room.
  - `scope` is *Region* (powers the region of the room it stands in) or *Whole map* (feeds a shared pool every region draws on).
  - Tick `starts_running` for one that is already running when the match starts. Otherwise a guard has to hold E on it.
  - The `*_override` numbers replace the defaults for that generator; -1 keeps the default.
  - They are solid. Shots damage them, and one shot down stops; a guard holds E longer to repair it.
  - A generator outside a room, or a region generator in a room with no region, gets a warning.
- **Doors** cost power to keep shut. The region that pays is the one of the room the door leads into, not the corridor it leads out of. Set
  `region_override` on the door to choose another.
- **Ceiling lights**: every room except an outdoor one has a light. There is nothing to place: it is sized from the room's `FacilityRoomRect`s every
  time the map builds, so resizing a room resizes its light.
  - Guards switch them on and off from the door console: click a door to work it, or anywhere else in a room to switch its light. All lights
    are off when a match starts.
  - A light that is on costs `light_cost` (1 pt/s) from its room's region.
  - The light fills the room, stops at walls and shut doors, and spills out through open doorways (`spill_m` on the level's `RoomLights` node).
  - Each room rectangle's lamp is a real `PointLight2D`, like the flashlight, so the art keeps its colours under it. Its colour and brightness
    are `color` and `energy` on the level's `RoomLights` node.
  - Each player sees a light only where they have a clear line of sight to it, in any direction. `PlayerSight` takes the light back off
    everywhere else, for that player only.
  - A player standing in a lit room counts as lit, like one in a flashlight beam.
  - Every lit room also has a **camera**, switched from the same console with a right click (`camera_cost` in `power_settings.tres`, 5 pts/s).
    A camera that is on shows its room live on the console's map (`game/ui/map_view/layers/cameras_layer.gd`); a dark room looks dark on camera.
  - Furniture (decor pieces, generators, consoles) casts shadows in flashlight beams but not in room lights, because the lamp is on the ceiling
    (`LightLayers.make_ceiling`: it takes the walls' shadows only). Each has a `height`, and its shadow falls only on lower things (see `LightLayers`).
    New furniture needs three things to behave the same: physics layer 5 (`FacilityTileSet.PROP_LAYER`) in its `collision_layer`, its picture's
    `light_mask` = `LightLayers.receiver_layer(tier)`, and a `LightOccluder2D` the size of its body with `occluder_light_mask` =
    `LightLayers.caster_layer(tier)`, where `tier` is `LightLayers.tier_of(height)`.
  - The code is in `game/lights/`.
- **`game/power/power_settings.tres`** holds the numbers: the cost per second of each kind of thing, generator output, health and hold times.
  - It also holds **`shed_order`**: when power runs short, the first category in the list is switched off first, then the next, until what is left
    fits. Drag the entries to reorder it. Within a category, the thing switched on last goes first.
  - A region that its own generators cover is never touched; only regions drawing on the pool lose things.
- **How a region's power works out:** a region uses its own generators first and takes the rest from the pool. The power free there is what its
  generators have left plus what the pool has left. A door can only be closed when its cost fits in that.
- **Who sees it:** guards get a readout on the HUD for the region they stand in. On the Caps Lock map everyone sees the region outlines, and guards
  also see each region's power and the generators. All guards see it, so a secret attacker among them is not given away.

## Player visuals
`game/player/skin/player_skin.tscn` is a real scene: `Legs`, `Torso` and `Full` have the guard's `SpriteFrames` (`guard/guard_frames.tres`) assigned, so every
animation can be previewed; `HitReaction` (flinch and blood) and `Death` (the fall) are nodes with their own settings; the `Flashlight` has `Cone` and `Halo`
`PointLight2D` children, the `Muzzle` has its `Light`, and the shoulder lamp and muzzle star are tool scripts that draw in the editor with colours you can change.
The sheets come from Blender: `tools/rig/build_skin.ps1` renders and packs them and has Godot bake `guard_frames.tres` (see `tools/rig/README.md`). Another role's
skin = another frames resource and `sprites.json`, assigned on the Skin node (`sprite_frames`, `sprite_data`).

## Tools (godot --headless --path . --script res://tools/art/<name>.gd)
- `bake_facility_tileset.gd`: rewrites `facility_tileset.tres` (the wall/floor/shadow tile set, with its collision and light occluders)
- `bake_skin_frames.gd [-- role]`: rewrites `<role>_frames.tres`
- `dump_facility.tscn` (run as a scene): prints a summary of the built map, to compare two versions of it
- `convert_layout_to_scene.gd`: the one-time JSON to scene conversion (do not run it again, it overwrites the scene)

## Checks
`tests/unit/test_facility_map.tscn` (in `tests/run_all.ps1`): no two rooms share a cell, every door joins two different rooms and sits on the grid, the
floor and wall layers match, every console stands in a room whose function it works and has a screen. Run it after editing the map.

## Maps on screens
Every screen that shows the facility uses one map: `FacilityMapView` (`game/ui/map_view/`). It scrolls (drag with the mouse, trackpad pan) and zooms in
and out (mouse wheel, trackpad pinch, the + / - buttons), so it stays readable however big the facility gets. What it shows is its **layers**: `MapLayer`
nodes placed under it in the screen's scene, drawn in order: `RoomsLayer`, `LightsLayer` (the rooms' lights, clickable), `RelicRoomsLayer` (rooms outlined in yellow), `DoorsLayer` (clickable or not), `ExitsLayer` (with `outline_only` the target exit is outlined in green, not filled), `SpawnLayer`, `PlayerDotLayer`.
The Caps Lock map (`map_screen.tscn`) outlines in yellow, for everyone, each treasure room (`kind` = Item) that had a relic in it when the match started.
The outline stays when the relic is carried off. It outlines the target exit in green for intruders only. A guard who is secretly attacking is told the
exit too (the spawn selection map shows it to every attacker), but the Caps Lock map does not show it to them.
The door console (`door_map_screen.tscn`) and the spawn selection (`spawn_select_phase.tscn`) are built this way. A new map screen (lights, cameras,
the full map on Tab) is a scene with a `FacilityMapView` and the layers it needs; something new to show on a map is a new `MapLayer` script that draws in
world pixels (use `px()` for sizes that should stay the same on screen, `draw_label()` for text) and overrides `map_click()` to take clicks.
