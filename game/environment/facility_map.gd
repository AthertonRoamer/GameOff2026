@tool
class_name FacilityMap
extends Node2D

##Facility 9. The map is a scene you edit in the editor, and this node is what the rest of the game asks about it.
##
##  Rooms   FacilityRoom nodes: each one's FacilityRoomRect children are its floor (select one and drag its handles, they snap to the 11 px grid)
##  Doors   FacilityDoor scenes dragged into the walls between rooms
##  Vents   Marker2D nodes: the top left corner of a 2 x 2 cell (0.5 m) grille
##  Props   anything that stands on the floor and matters to the game (control panels, things that block): always there, y-sorted
##  Decor   (optional) furniture and clutter that is only looked at: sprites and lights, no collision. Streamed: only what is near the view is in the tree
##  Spawns  GuardSpawn / IntruderSpawn markers: each makes the room it stands on a spawn room of its kind (see SpawnRoomMarker, spawn_rooms)
##  Actors  where players and other moving things are added, y-sorted
##  Regions (optional) FacilityRegion nodes: the power regions. A room joins one by its `region` (see FacilityRegion for the editor tools), and the
##          generators and everything that uses power belong to the region of the room they are in (see PowerGrid, regions, region_at, region_of_door)
##  A room of kind Exit is an exit zone: an area outside the walls with no floor or wall tiles of its own, reached through a door like a room and
##          ringed by invisible walls (see FacilityRoom.is_exit, exits, barrier_cells, is_in_exit)
##  Floors, Walls, Shadows   tile layers the map makes and fills in itself from the rooms and doors, in the editor as well as in the game: every cell of
##          a room is floor, every empty cell touching a floor cell is wall (so rooms need a one cell gap), and the floor beside a wall gets a soft
##          shadow. They are not part of the scene file, so resizing a room never touches the art. The Rebuild button below redoes them by hand.
##
##The map is big, so none of this is made all at once. What the game asks about (which room a point is in, where the walls are, where the doors are) is worked
##out from the rooms' rectangles in a moment. What is expensive is the tiles (a hundred thousand cells), and they are painted a chunk (16 x 16 cells, 4 m) at a
##time by the MapStreamer, only near the view, and erased again when the view leaves. Walls' collision and the doors are always there (they are cheap, and every
##player needs them whether or not this peer's camera is near). The Streaming settings below tune it.
##
##Physics layers: walls are on layer 2 (FacilityTileSet.WORLD_LAYER), closed doors on layer 4 (DOOR_LAYER). A player body should have
##a collision mask of 2 | 8 = 10 so walls and doors stop it, and a projectile's world mask should be 2 so only walls stop a bullet.

signal built

const TILE : int = FacilityTileSet.TILE
const CHUNK_SHIFT : int = 4 #a chunk is 1 << 4 = 16 cells on a side (176 px, 4 m)
const WALL_Z : int = 1 #z_index of the walls and gates: over the players, whose bodies can reach into the wall beside them
const FLOOR_Z : int = -20 #z_index of the floor and shadow layers; a dead body is at Player.DEAD_Z, above them and below everything else
const EDITOR_REBUILD_DELAY : float = 0.15 #seconds a room or door has to sit still in the editor before the tiles are rebuilt

@export var doors_start : FacilityDoor.State = FacilityDoor.State.CLOSED #the state every door has when the game starts, unless apply_doors_start is off
@export var apply_doors_start : bool = true #off: each door starts in the state it has in the scene
@export var void_color : Color = Color("#07090c") #what shows outside the building. Palette A "void"
@export_tool_button("Rebuild floors, walls and shadows") var rebuild_button : Callable = build
@export_group("Streaming")
@export var stream_tiles : bool = true ## paint the tiles only near the view (off: all of them at once, which takes seconds on a big map)
@export_range(0, 96, 1, "suffix:cells") var view_margin_cells : int = 32 ## tiles stay painted this far past the edge of the view (and are painted ahead of the player)
@export_range(0, 96, 1, "suffix:cells") var unload_extra_cells : int = 24 ## and are only erased once the view is this much further away, so a player at the edge does not flicker them
@export_range(0.5, 16.0, 0.5, "suffix:ms") var chunk_budget_ms : float = 3.0 ## how long each frame may be spent painting and erasing tiles
@export_range(0, 192, 1, "suffix:cells") var decor_margin_cells : int = 64 ## Decor within this far of the view is in the tree
@export_range(0, 48, 1, "suffix:cells") var editor_margin_cells : int = 8 ## the same margin, in the editor (it follows the 2D view)

var rooms : Dictionary = {} #room id -> {name, kind, function, region: String, rects: Array[Rect2i], exterior: bool, spawns: {SpawnRoomMarker.Kind: world point}}
var regions : Dictionary = {} #region id -> {name, colour, rooms: Array[String], centre: world point (the middle of its biggest room)}, in the order of the Regions node
var floor_rects : Array[Rect2i] = [] #every piece of floor, in cells: the rooms' rectangles, then the door cells
var wall_cells : Dictionary = {} #Vector2i -> true: every empty cell touching a floor cell
var exits : Dictionary = {} #exit id -> Array[Rect2i]: the rooms of kind Exit, which are zones rather than rooms (no floor, no walls), see FacilityRoom.is_exit. Not in `rooms`
var exit_cells : Dictionary = {} #Vector2i -> exit id
var barrier_cells : Dictionary = {} #Vector2i -> true: the invisible walls round the exit zones (collision, no tile), see _compute_walls
var doors : Array[FacilityDoor] = []
var vents : Array[Vector2i] = []
var light_rooms : Array[String] = [] #the rooms with a ceiling light (every room but outdoor ones), in scene order: a light's index names it on every peer, like door_index
var light_sources : Array[Dictionary] = [] #{light: int, room: String, rect: Rect2i}: one per rectangle of a lit room (an L-shaped room has two, sharing one switch)
var _light_of_room : Dictionary = {} #room id -> light index

var _floor_ids : PackedStringArray = [] #the room of each of floor_rects
var _floor_index : Dictionary = {} #chunk (Vector2i) -> Array of indexes into floor_rects that reach into it
var _wall_chunks : Dictionary = {} #chunk -> Array of the wall cells in it
var _painted : Dictionary = {} #chunk -> true: the chunks whose tiles are on the layers now
var _signature : int = 0 #editor: what the rooms and doors looked like when the tiles were last built
var _changed_for : float = 0.0
var _region_outlines : Dictionary = {} #region id -> PackedVector2Array (line pairs), worked out the first time it is asked for after a build

var floors : TileMapLayer #made in _ready (see _make_layers), not part of the scene file
var shadows : TileMapLayer
var walls : TileMapLayer
var wall_body : StaticBody2D #the walls' collision and occluders (the tiles only draw), see _build_wall_body
var streamer : MapStreamer #paints and erases the tiles near the view, and brings Decor in and out of the tree
@onready var rooms_node : Node2D = $Rooms
@onready var doors_node : Node2D = $Doors
@onready var vents_node : Node2D = $Vents
@onready var props_node : Node2D = $Props
@onready var actors : Node2D = $Actors
var regions_node : Node2D: #optional: a map without it has no regions (everything runs on whole-map power)
	get: return get_node_or_null("Regions") as Node2D


func _ready() -> void:
	_make_layers()
	doors_node.z_index = WALL_Z
	set_process(Engine.is_editor_hint()) #only the editor watches the rooms and doors for changes
	if not Engine.is_editor_hint():
		RenderingServer.set_default_clear_color(void_color) #the engine's default grey would show wherever there is no tile
	build()
	if not Engine.is_editor_hint() and apply_doors_start:
		for door : FacilityDoor in doors:
			door.state = doors_start


func _process(delta : float) -> void:
	if not Engine.is_editor_hint():
		return
	var now : int = _layout_signature()
	if now == _signature:
		_changed_for = 0.0
		return
	_changed_for += delta
	if _changed_for >= EDITOR_REBUILD_DELAY:
		_snap_to_grid()
		build()


##The three tile layers are made here, first among the children (so they draw under everything else), and are not given an owner, so they are never
##saved into the scene file and the editor does not let you select them. Any saved ones from an older version of the scene are replaced.
func _make_layers() -> void:
	var tile_set : TileSet = FacilityTileSet.shared() #loaded once per process (see WarmUp)
	var index : int = 0
	for layer_name : String in ["Floors", "Shadows", "Walls"]:
		var old : Node = get_node_or_null(layer_name)
		if old != null:
			remove_child(old)
			old.free()
		var layer : TileMapLayer = TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = tile_set
		layer.scale = Vector2.ONE * FacilityTileSet.ART_SCALE #the tiles are drawn at 4x resolution, like the character sprites
		layer.z_index = FLOOR_Z if layer_name != "Walls" else WALL_Z #the floor and its shadows are far below everything, so a body on the floor (Player.DEAD_Z) lies over them
		add_child(layer)
		move_child(layer, index)
		index += 1
		set(layer_name.to_lower(), layer)
	for stale : String in ["WallBodies", "Streamer"]:
		var old_node : Node = get_node_or_null(stale)
		if old_node != null:
			remove_child(old_node)
			old_node.free()
	wall_body = StaticBody2D.new() #the walls' collision and light occluders, see _build_wall_body
	wall_body.name = "WallBodies"
	wall_body.collision_layer = FacilityTileSet.WORLD_LAYER | FacilityTileSet.STRUCTURE_LAYER
	wall_body.collision_mask = 0
	add_child(wall_body)
	move_child(wall_body, index)
	streamer = MapStreamer.new()
	streamer.name = "Streamer"
	streamer.map = self
	add_child(streamer)


##Reads the rooms and doors, works out the walls and which rooms each door joins, and starts the tiles over (the streamer paints them as they come into view).
func build() -> void:
	_collect_rooms()
	_collect_regions()
	_collect_doors()
	_compute_walls()
	clear_tiles()
	_build_wall_body()
	_collect_vents()
	_collect_spawns()
	_signature = _layout_signature()
	built.emit()


# ------------------------------------------------------------------ asking about the map
##World position of the centre of a tile.
func cell_to_world(cell : Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


func world_to_cell(world : Vector2) -> Vector2i:
	return Vector2i((world / TILE).floor())


##Id of the room a world position is in, or "" for walls and empty space.
func room_at(world : Vector2) -> String:
	return room_of_cell(world_to_cell(world))


##Id of the room a cell is floor of (a door's cells belong to the room on its north or west side), or "".
func room_of_cell(cell : Vector2i) -> String:
	var list : Array = _floor_index.get(Vector2i(cell.x >> CHUNK_SHIFT, cell.y >> CHUNK_SHIFT), [])
	for i : int in list:
		if floor_rects[i].has_point(cell):
			return _floor_ids[i]
	return ""


func is_floor(cell : Vector2i) -> bool:
	var list : Array = _floor_index.get(Vector2i(cell.x >> CHUNK_SHIFT, cell.y >> CHUNK_SHIFT), [])
	for i : int in list:
		if floor_rects[i].has_point(cell):
			return true
	return false


##How many cells of floor there are (counted once each, so slowish on a big map: for tests and tools).
func floor_cell_count() -> int:
	var seen : Dictionary = {}
	for rect : Rect2i in floor_rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				seen[Vector2i(x, y)] = true
	return seen.size()


##Id of the exit zone a world position is in, or "".
func exit_at(world : Vector2) -> String:
	return exit_cells.get(world_to_cell(world), "")


func is_in_exit(world : Vector2) -> bool:
	return exit_cells.has(world_to_cell(world))


##Whether the map has a room (not an exit zone) by this id. Rooms are named in the editor and can be renamed, split or deleted, so code that names a
##room (a map option's spawn room, a test) should ask first, or use start_room().
func has_room(room_id : String) -> bool:
	return rooms.has(room_id)


##Bounding rectangles of a room in world pixels (a room can have several, like an L-shaped room). Empty for a room the map does not have.
func room_rects_px(room_id : String) -> Array[Rect2]:
	var result : Array[Rect2] = []
	if not rooms.has(room_id):
		return result
	for rect : Rect2i in rooms[room_id]["rects"]:
		result.append(Rect2(Vector2(rect.position * TILE), Vector2(rect.size * TILE)))
	return result


##The middle of a room's first rectangle. For a room the map does not have: the middle of start_room() (so a stale room name never crashes the game).
func room_center_px(room_id : String) -> Vector2:
	var rects : Array[Rect2] = room_rects_px(room_id)
	if not rects.is_empty():
		return rects[0].get_center()
	var fallback : String = start_room()
	return room_rects_px(fallback)[0].get_center() if fallback != "" else Vector2.ZERO


##The room players start in: `preferred` if the map has it; otherwise the biggest corridor, then the biggest room that is not outdoors, then any room.
##"" only for a map with no rooms at all. Whatever the rooms are called, and however many there are, this finds one.
func start_room(preferred : String = "") -> String:
	if rooms.has(preferred):
		return preferred
	var best : String = ""
	var best_score : float = -1.0
	for id : String in rooms:
		var area : int = 0
		for rect : Rect2i in rooms[id]["rects"]:
			area += rect.get_area()
		var rank : int = 2 if rooms[id]["kind"] == "corridor" else (1 if rooms[id]["kind"] != "outdoor" else 0)
		var score : float = rank * 1.0e9 + area
		if score > best_score:
			best_score = score
			best = id
	return best


##A random point on the floor of the facility, inside a room (not outdoors), in world pixels, with room for a player to stand (not in a piece of furniture). Rooms count by
##their size, so every part of the floor is as likely as any other.
func random_floor_point() -> Vector2:
	var point : Vector2 = _random_room_point()
	for attempt in 24:
		if is_clear(point):
			return point
		point = _random_room_point()
	return point


##Whether a player (a circle of this radius, in world pixels) fits at a point of the map: nothing solid (walls, furniture, shut doors) within reach.
func is_clear(point : Vector2, radius : float = 14.0) -> bool:
	if not is_inside_tree():
		return true
	var shape : CircleShape2D = CircleShape2D.new()
	shape.radius = radius
	var query : PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, to_global(point))
	query.collision_mask = FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _random_room_point() -> Vector2:
	var rects : Array[Rect2i] = []
	var cells : int = 0
	for id : String in rooms:
		if rooms[id]["kind"] == "outdoor":
			continue
		for rect : Rect2i in rooms[id]["rects"]:
			rects.append(rect)
			cells += rect.size.x * rect.size.y
	if cells == 0:
		return Vector2.ZERO
	var pick : int = randi() % cells
	for rect : Rect2i in rects:
		pick -= rect.size.x * rect.size.y
		if pick < 0:
			var inner : Rect2i = rect.grow(-1) if rect.size.x > 2 and rect.size.y > 2 else rect #(a cell in from the walls)
			return cell_to_world(inner.position + Vector2i(randi() % inner.size.x, randi() % inner.size.y))
	return Vector2.ZERO


##The rooms players of this kind may start in (SpawnRoomMarker.Kind), in scene order (the same on every peer).
func spawn_rooms(spawn_kind : int) -> Array[String]:
	var result : Array[String] = []
	for id : String in rooms:
		if rooms[id]["spawns"].has(spawn_kind):
			result.append(id)
	return result


##Where players of this kind who start in this room appear: its marker's position.
func spawn_point(room_id : String, spawn_kind : int) -> Vector2:
	if not rooms.has(room_id):
		return room_center_px(room_id)
	return rooms[room_id]["spawns"].get(spawn_kind, room_center_px(room_id))


func rooms_of_kind(kind : String) -> Array[String]:
	var result : Array[String] = []
	for id : String in rooms:
		if rooms[id]["kind"] == kind:
			result.append(id)
	return result


func doors_of_room(room_id : String) -> Array[FacilityDoor]:
	var result : Array[FacilityDoor] = []
	for door in doors:
		if door.room_a == room_id or door.room_b == room_id:
			result.append(door)
	return result


# ------------------------------------------------------------------ power regions
##The region a room is in, or "" (none, or not a room).
func region_of_room(room_id : String) -> String:
	return rooms[room_id]["region"] if rooms.has(room_id) else ""


##The region a world position is in, or "" (walls, empty space, exit zones and rooms in no region).
func region_at(world : Vector2) -> String:
	return region_of_room(room_at(world))


##The region that pays to keep a door shut: its region_override if set; otherwise the region of the room it leads into, not the corridor or the
##outdoor pad it leads out of (a door from the corridor into the vault is the vault's); between two rooms of the same sort, the north or west one.
func region_of_door(door : FacilityDoor) -> String:
	if door.region_override != &"":
		return String(door.region_override)
	var a_open : bool = rooms.has(door.room_a) and rooms[door.room_a]["kind"] in ["corridor", "outdoor"]
	var b_open : bool = rooms.has(door.room_b) and rooms[door.room_b]["kind"] in ["corridor", "outdoor"]
	if a_open and not b_open and rooms.has(door.room_b):
		return region_of_room(door.room_b)
	if rooms.has(door.room_a):
		return region_of_room(door.room_a)
	return region_of_room(door.room_b)


func region_name(region_id : String) -> String:
	return regions[region_id]["name"] if regions.has(region_id) else "No region"


func region_colour(region_id : String) -> Color:
	return regions[region_id]["colour"] if regions.has(region_id) else Palette.MUTED


##The outline of a region, in world pixels, as pairs of points for draw_multiline: round its rooms and the walls between them, so two regions that
##meet at a wall each have a line on their own side of it. Worked out once per build, when first asked for.
func region_outline(region_id : String) -> PackedVector2Array:
	if not _region_outlines.has(region_id):
		_region_outlines[region_id] = _compute_outline(region_id)
	return _region_outlines[region_id]


##The whole map, walls included, in cells.
func map_cell_bounds() -> Rect2i:
	var bounds : Rect2i = Rect2i()
	var first : bool = true
	for rect : Rect2i in floor_rects:
		bounds = rect.grow(1) if first else bounds.merge(rect.grow(1))
		first = false
	return bounds


func map_bounds_px() -> Rect2:
	var bounds : Rect2i = map_cell_bounds()
	return Rect2(Vector2(bounds.position * TILE), Vector2(bounds.size * TILE))


func chunk_of_cell(cell : Vector2i) -> Vector2i:
	return Vector2i(cell.x >> CHUNK_SHIFT, cell.y >> CHUNK_SHIFT)


func chunk_of_world(world : Vector2) -> Vector2i:
	return chunk_of_cell(world_to_cell(world))


##Whether there is anything in a chunk to paint (floor or wall).
func chunk_has_tiles(chunk : Vector2i) -> bool:
	return _floor_index.has(chunk) or _wall_chunks.has(chunk)


# ------------------------------------------------------------------ the tiles, a chunk at a time
##Paints one chunk: the floor, the soft shadow on the floor beside a wall, and the walls. The streamer calls this as a chunk comes into view.
func paint_chunk(chunk : Vector2i) -> void:
	if floors == null or _painted.has(chunk):
		return
	_painted[chunk] = true
	var area : Rect2i = Rect2i(chunk * (1 << CHUNK_SHIFT), Vector2i.ONE * (1 << CHUNK_SHIFT))
	for i : int in _floor_index.get(chunk, []):
		var whole : Rect2i = floor_rects[i]
		var part : Rect2i = whole.intersection(area)
		for y in range(part.position.y, part.end.y):
			var edge_row : bool = y == whole.position.y or y == whole.end.y - 1
			for x in range(part.position.x, part.end.x):
				var cell : Vector2i = Vector2i(x, y)
				floors.set_cell(cell, FacilityTileSet.SOURCE_FLOORS, Vector2i.ZERO)
				if edge_row or x == whole.position.x or x == whole.end.x - 1: #(only the floor along a room's edge has a wall next to it)
					var mask : int = FacilityTileSet.neighbour_mask(cell, wall_cells)
					if mask != 0:
						shadows.set_cell(cell, FacilityTileSet.SOURCE_SHADOWS, FacilityTileSet.mask_to_atlas(mask))
	for cell : Vector2i in _wall_chunks.get(chunk, []):
		walls.set_cell(cell, FacilityTileSet.SOURCE_WALLS, FacilityTileSet.mask_to_atlas(FacilityTileSet.neighbour_mask(cell, wall_cells)))


##Erases one chunk's tiles again.
func clear_chunk(chunk : Vector2i) -> void:
	if not _painted.erase(chunk):
		return
	for i : int in _floor_index.get(chunk, []):
		var part : Rect2i = floor_rects[i].intersection(Rect2i(chunk * (1 << CHUNK_SHIFT), Vector2i.ONE * (1 << CHUNK_SHIFT)))
		for y in range(part.position.y, part.end.y):
			for x in range(part.position.x, part.end.x):
				floors.erase_cell(Vector2i(x, y))
				shadows.erase_cell(Vector2i(x, y))
	for cell : Vector2i in _wall_chunks.get(chunk, []):
		walls.erase_cell(cell)


func is_chunk_painted(chunk : Vector2i) -> bool:
	return _painted.has(chunk)


func painted_chunks() -> Array:
	return _painted.keys()


##Paints the whole map now (tests and tools; the game never needs to).
func paint_all() -> void:
	var chunks : Dictionary = {}
	for chunk : Vector2i in _floor_index:
		chunks[chunk] = true
	for chunk : Vector2i in _wall_chunks:
		chunks[chunk] = true
	for chunk : Vector2i in chunks:
		paint_chunk(chunk)


func clear_tiles() -> void:
	_painted.clear()
	for layer : TileMapLayer in [floors, shadows, walls]:
		if layer != null:
			layer.clear()
	if streamer != null:
		streamer.refresh()


func room_nodes() -> Array[FacilityRoom]:
	var result : Array[FacilityRoom] = []
	var holder : Node = rooms_node if rooms_node != null else get_node_or_null("Rooms") #(a region asks before the map is ready)
	if holder == null:
		return result
	for child : Node in holder.get_children():
		if child is FacilityRoom:
			result.append(child)
	return result


func _door_nodes() -> Array[FacilityDoor]:
	var result : Array[FacilityDoor] = []
	for child : Node in doors_node.get_children():
		if child is FacilityDoor:
			result.append(child)
	return result


func _collect_rooms() -> void:
	rooms.clear()
	floor_rects.clear()
	_floor_ids.clear()
	exits.clear()
	exit_cells.clear()
	for room : FacilityRoom in room_nodes():
		var rects : Array[Rect2i] = room.cell_rects(self)
		if rects.is_empty(): #a room just added in the editor, before it has a FacilityRoomRect: no floor yet, so it is not a room yet
			continue
		if room.is_exit(): #a zone, not floor: no tiles of its own. It sits outside a room's wall, joined to the room by a door
			exits[room.room_id()] = rects
			for rect : Rect2i in rects:
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						exit_cells[Vector2i(x, y)] = room.room_id()
			continue
		for rect : Rect2i in rects:
			floor_rects.append(rect)
			_floor_ids.append(room.room_id())
		var label : String = room.display_name if room.display_name != "" else room.room_id().capitalize()
		rooms[room.room_id()] = {"name": label, "kind": room.kind_name(), "function": room.function_name(), "region": String(room.region), "rects": rects, "exterior": false, "spawns": {}}
	_collect_lights()
	_index_floor()
	if Engine.is_editor_hint(): #the editor says so on a room that overlaps another
		var clashes : Dictionary = {} #room id -> another room whose floor it shares
		for cell : Vector2i in exit_cells: #an exit needs the same one cell wall between it and a room as two rooms do, or it would cut a gap in the wall
			for offset in [Vector2i.ZERO] + FacilityTileSet.NEIGHBOURS:
				if is_floor(cell + offset):
					clashes[exit_cells[cell]] = room_of_cell(cell + offset)
		for i in floor_rects.size():
			for chunk : Vector2i in _chunks_of(floor_rects[i]):
				for j : int in _floor_index[chunk]:
					if j > i and _floor_ids[j] != _floor_ids[i] and floor_rects[i].intersects(floor_rects[j]):
						clashes[_floor_ids[i]] = _floor_ids[j]
						clashes[_floor_ids[j]] = _floor_ids[i]
		for room : FacilityRoom in room_nodes():
			room.set_clash(clashes.get(room.room_id(), ""))


##Every room but an outdoor one has a ceiling light, sized from its rectangles: one light source per rectangle (see RoomLightShapes, PlayerSight).
##Worked out on every build, so resizing a room in the editor resizes its light.
func _collect_lights() -> void:
	light_rooms.clear()
	light_sources.clear()
	_light_of_room.clear()
	for id : String in rooms:
		if rooms[id]["kind"] == "outdoor":
			continue
		var index : int = light_rooms.size()
		light_rooms.append(id)
		_light_of_room[id] = index
		for rect : Rect2i in rooms[id]["rects"]:
			light_sources.append({"light": index, "room": id, "rect": rect})


##The index of a room's light, or -1 (no such room, or an outdoor room).
func light_of_room(room_id : String) -> int:
	return _light_of_room.get(room_id, -1)


##A light source's rectangle in world pixels.
func light_source_rect_px(source : int) -> Rect2:
	var rect : Rect2i = light_sources[source]["rect"]
	return Rect2(Vector2(rect.position * TILE), Vector2(rect.size * TILE))


##The regions under the Regions node, with the rooms that say they are in each. The editor's region badges are put in the middle of their biggest room.
func _collect_regions() -> void:
	regions.clear()
	_region_outlines.clear()
	if regions_node == null:
		return
	for child : Node in regions_node.get_children():
		if child is FacilityRegion:
			var region : FacilityRegion = child
			regions[String(region.name)] = {"name": region.label(), "colour": region.colour, "rooms": [] as Array[String], "centre": Vector2.ZERO}
	var biggest : Dictionary = {} #region id -> the area of its biggest room so far
	for id : String in rooms:
		var region_id : String = rooms[id]["region"]
		if not regions.has(region_id):
			continue
		(regions[region_id]["rooms"] as Array[String]).append(id)
		var rect : Rect2 = room_rects_px(id)[0]
		if rect.get_area() > biggest.get(region_id, -1.0):
			biggest[region_id] = rect.get_area()
			regions[region_id]["centre"] = rect.get_center()
	if Engine.is_editor_hint():
		for child : Node in regions_node.get_children():
			if child is FacilityRegion:
				(child as FacilityRegion).set_badge_point(regions[String(child.name)]["centre"])
				child.update_configuration_warnings()


##A region's cells are its rooms' cells and the ring of wall round each (which fills the one cell walls between its rooms); the outline is every cell edge
##of that with no region cell on the other side, joined into long straight lines.
func _compute_outline(region_id : String) -> PackedVector2Array:
	var cells : Dictionary = {}
	if regions.has(region_id):
		for id : String in regions[region_id]["rooms"]:
			for rect : Rect2i in rooms[id]["rects"]:
				var ring : Rect2i = rect.grow(1)
				for y in range(ring.position.y, ring.end.y):
					for x in range(ring.position.x, ring.end.x):
						cells[Vector2i(x, y)] = true
	var across : Dictionary = {} #y of a horizontal edge -> the x of each cell it runs along
	var down : Dictionary = {} #x of a vertical edge -> the y of each cell it runs along
	for cell : Vector2i in cells:
		if not cells.has(cell + Vector2i.UP):
			_add_edge(across, cell.y, cell.x)
		if not cells.has(cell + Vector2i.DOWN):
			_add_edge(across, cell.y + 1, cell.x)
		if not cells.has(cell + Vector2i.LEFT):
			_add_edge(down, cell.x, cell.y)
		if not cells.has(cell + Vector2i.RIGHT):
			_add_edge(down, cell.x + 1, cell.y)
	var lines : PackedVector2Array = []
	for y : int in across:
		for run : Vector2i in _runs(across[y]):
			lines.append(Vector2(run.x * TILE, y * TILE))
			lines.append(Vector2((run.y + 1) * TILE, y * TILE))
	for x : int in down:
		for run : Vector2i in _runs(down[x]):
			lines.append(Vector2(x * TILE, run.x * TILE))
			lines.append(Vector2(x * TILE, (run.y + 1) * TILE))
	return lines


func _add_edge(lines : Dictionary, at : int, along : int) -> void:
	if not lines.has(at):
		lines[at] = []
	(lines[at] as Array).append(along)


##Sorted runs of consecutive numbers, as (first, last).
func _runs(values : Array) -> Array[Vector2i]:
	values.sort()
	var result : Array[Vector2i] = []
	var i : int = 0
	while i < values.size():
		var first : int = values[i]
		var last : int = first
		while i + 1 < values.size() and values[i + 1] <= last + 1:
			i += 1
			last = maxi(last, values[i])
		result.append(Vector2i(first, last))
		i += 1
	return result


##Each door's cells join the room on its north or west side (so the floor under the door matches), and the door learns both its rooms.
func _collect_doors() -> void:
	doors.clear()
	var index : int = 0
	var door_floor : Array[Rect2i] = []
	var door_floor_rooms : PackedStringArray = []
	for door : FacilityDoor in _door_nodes():
		var cells : Rect2i = door.cell_rect(self)
		var first : Vector2i
		var second : Vector2i
		if door.horizontal: #in the middle of the gate, one cell out on each side
			first = Vector2i(cells.position.x + 1, cells.position.y - 1)
			second = Vector2i(cells.position.x + 1, cells.end.y)
		else:
			first = Vector2i(cells.position.x - 1, cells.position.y + 1)
			second = Vector2i(cells.end.x, cells.position.y + 1)
		door.room_a = room_of_cell(first) if is_floor(first) else exit_cells.get(first, "") #(the rooms' own cells: no door cell has been added yet) a side can be an exit zone: the door out of the facility
		door.room_b = room_of_cell(second) if is_floor(second) else exit_cells.get(second, "")
		if Engine.is_editor_hint(): #the editor says so on a door that is not between two different rooms
			door.set_problem("" if door.room_a != "" and door.room_b != "" and door.room_a != door.room_b else "This door is not in the wall between two different rooms. Drag it onto the one cell gap between them.")
		door.door_index = index
		var outside : bool = false
		for side : String in [door.room_a, door.room_b]:
			if exits.has(side) or (rooms.has(side) and rooms[side]["kind"] == "outdoor"):
				outside = true
		door.exterior = outside
		if outside: #the room on the building side counts as an exterior room
			for side : String in [door.room_a, door.room_b]:
				if rooms.has(side) and rooms[side]["kind"] != "outdoor":
					rooms[side]["exterior"] = true
		door_floor.append(cells)
		door_floor_rooms.append(door.room_a if rooms.has(door.room_a) else door.room_b) #the floor under the door belongs to a room, never to an exit
		doors.append(door)
		index += 1
	floor_rects.append_array(door_floor)
	_floor_ids.append_array(door_floor_rooms)
	_index_floor()


func _index_floor() -> void:
	_floor_index.clear()
	for i in floor_rects.size():
		for chunk : Vector2i in _chunks_of(floor_rects[i]):
			if not _floor_index.has(chunk):
				_floor_index[chunk] = []
			(_floor_index[chunk] as Array).append(i)


func _chunks_of(rect : Rect2i) -> Array[Vector2i]:
	var result : Array[Vector2i] = []
	for cy in range(rect.position.y >> CHUNK_SHIFT, ((rect.end.y - 1) >> CHUNK_SHIFT) + 1):
		for cx in range(rect.position.x >> CHUNK_SHIFT, ((rect.end.x - 1) >> CHUNK_SHIFT) + 1):
			result.append(Vector2i(cx, cy))
	return result


##Every empty cell touching a floor cell is a wall: the ring round each piece of floor, without the cells that are floor of another and without an exit zone's own cells (so the doorway out
##to an exit stays clear). Every empty cell touching an exit is a barrier: an invisible wall, so a player who goes through the door into the exit stops at its edge instead of walking off into the void.
func _compute_walls() -> void:
	wall_cells.clear()
	barrier_cells.clear()
	_wall_chunks.clear()
	for rect : Rect2i in floor_rects:
		var ring : Rect2i = rect.grow(1)
		for x in range(ring.position.x, ring.end.x):
			_add_wall(Vector2i(x, ring.position.y))
			_add_wall(Vector2i(x, ring.end.y - 1))
		for y in range(rect.position.y, rect.end.y):
			_add_wall(Vector2i(ring.position.x, y))
			_add_wall(Vector2i(ring.end.x - 1, y))
	for cell : Vector2i in exit_cells:
		for offset in FacilityTileSet.NEIGHBOURS:
			var next : Vector2i = cell + offset
			if not is_floor(next) and not exit_cells.has(next) and not wall_cells.has(next):
				barrier_cells[next] = true


func _add_wall(cell : Vector2i) -> void:
	if wall_cells.has(cell) or is_floor(cell) or exit_cells.has(cell):
		return
	wall_cells[cell] = true
	var chunk : Vector2i = chunk_of_cell(cell)
	if not _wall_chunks.has(chunk):
		_wall_chunks[chunk] = []
	(_wall_chunks[chunk] as Array).append(cell)


## The walls' collision and light occluders: the wall cells joined into as few rectangles as possible, one shape and one occluder each. A tile per cell made about
## 1500 shapes and occluders, and every flashlight and every moving player paid for each of them; the rectangles are the same walls with a twentieth of the work
## (and no seams between cells for a player to catch on).
func _build_wall_body() -> void:
	for child : Node in wall_body.get_children():
		wall_body.remove_child(child)
		child.free()
	for rect : Rect2i in wall_rects():
		var world : Rect2 = Rect2(Vector2(rect.position * TILE), Vector2(rect.size * TILE))
		var shape : CollisionShape2D = CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		(shape.shape as RectangleShape2D).size = world.size
		shape.position = world.get_center()
		wall_body.add_child(shape)
		var occluder : LightOccluder2D = LightOccluder2D.new()
		occluder.occluder = OccluderPolygon2D.new()
		occluder.occluder.polygon = PackedVector2Array([world.position, Vector2(world.end.x, world.position.y), world.end, Vector2(world.position.x, world.end.y)])
		wall_body.add_child(occluder)
	for rect : Rect2i in cells_to_rects(barrier_cells): #the invisible walls round the exit zones: collision only, no tile and no occluder
		var world : Rect2 = Rect2(Vector2(rect.position * TILE), Vector2(rect.size * TILE))
		var shape : CollisionShape2D = CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		(shape.shape as RectangleShape2D).size = world.size
		shape.position = world.get_center()
		wall_body.add_child(shape)


func wall_rects() -> Array[Rect2i]:
	return cells_to_rects(wall_cells)


## Cells as rectangles (in cells) that cover them exactly: each row's runs of cells, with a run joined to the one above it when they span the same columns.
func cells_to_rects(cells : Dictionary) -> Array[Rect2i]:
	var rows : Dictionary = {} #y -> the x of every cell in that row
	for cell : Vector2i in cells:
		if not rows.has(cell.y):
			rows[cell.y] = []
		rows[cell.y].append(cell.x)
	var ys : Array = rows.keys()
	ys.sort()
	var rects : Array[Rect2i] = []
	var above : Dictionary = {} #(first x, last x) of a run in the row above -> its rectangle's index
	var last_y : int = 0
	for y : int in ys:
		if y != last_y + 1:
			above = {}
		last_y = y
		var xs : Array = rows[y]
		xs.sort()
		var current : Dictionary = {}
		var i : int = 0
		while i < xs.size():
			var first : int = xs[i]
			var last : int = first
			while i + 1 < xs.size() and xs[i + 1] == last + 1:
				i += 1
				last = xs[i]
			i += 1
			var span : Vector2i = Vector2i(first, last)
			var index : int = above.get(span, -1)
			if index >= 0:
				var taller : Rect2i = rects[index]
				taller.size.y += 1
				rects[index] = taller
			else:
				rects.append(Rect2i(first, y, last - first + 1, 1))
				index = rects.size() - 1
			current[span] = index
		above = current
	return rects


##Every SpawnRoomMarker in the map (wherever it is in the tree: only its position counts) makes the room under it a spawn room of its kind.
func _collect_spawns() -> void:
	var kinds_of : Dictionary = {} #room id -> the spawn kinds it has, for the editor's badges
	for marker : SpawnRoomMarker in spawn_markers():
		var at : Vector2 = to_local(marker.global_position)
		var room : String = room_at(at)
		marker.room_id = room
		var problem : String = ""
		if exit_at(at) != "":
			problem = "This spawn marker is on an exit zone. Drag it onto a room."
		elif room == "":
			problem = "This spawn marker is not on any room's floor. Drag it onto a room."
		elif not rooms[room]["spawns"].has(marker.kind):
			rooms[room]["spawns"][marker.kind] = at
			if not kinds_of.has(room):
				kinds_of[room] = []
			kinds_of[room].append(marker.kind)
		if Engine.is_editor_hint():
			marker.set_problem(problem)
		if problem != "":
			marker.room_id = ""
	if Engine.is_editor_hint():
		for node : FacilityRoom in room_nodes():
			node.set_spawn_kinds(kinds_of.get(node.room_id(), []))


func spawn_markers() -> Array[SpawnRoomMarker]:
	var result : Array[SpawnRoomMarker] = []
	for node : Node in find_children("*", "Marker2D", true, false):
		if node is SpawnRoomMarker:
			result.append(node)
	return result


func _collect_vents() -> void:
	#only the positions: there is no vent art in the smooth look
	vents.clear()
	for child : Node in vents_node.get_children():
		if child is Marker2D:
			vents.append(world_to_cell((child as Marker2D).position))


func _snap_to_grid() -> void:
	for room : FacilityRoom in room_nodes():
		room.snap_to_grid()
	for door : FacilityDoor in _door_nodes():
		door.snap_to_grid()
	for child : Node in vents_node.get_children():
		if child is Marker2D:
			(child as Marker2D).position = ((child as Marker2D).position / TILE).round() * TILE


##A number that changes when a room, door or vent is edited (editor only: tells _process when the tiles need rebuilding).
func _layout_signature() -> int:
	var parts : PackedStringArray = []
	for room : FacilityRoom in room_nodes():
		parts.append("%s %s %d %d %s" % [room.name, room.position, room.kind, room.function, room.region])
		for rect : FacilityRoomRect in room.rects():
			parts.append("%s %s" % [rect.position, rect.size])
	for door : FacilityDoor in _door_nodes():
		parts.append("%s %s %s" % [door.name, door.position, door.horizontal])
	for child : Node in vents_node.get_children():
		parts.append("%s" % (child as Node2D).position)
	for marker : SpawnRoomMarker in spawn_markers():
		parts.append("%s %d %s" % [marker.name, marker.kind, marker.global_position])
	if regions_node != null:
		for region : Node in regions_node.get_children():
			parts.append("region %s" % region.name)
	return "|".join(parts).hash()
