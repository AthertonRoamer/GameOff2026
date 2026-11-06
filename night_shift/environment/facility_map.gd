@tool
class_name FacilityMap
extends Node2D

##Facility 9. The map is a scene you edit in the editor, and this node is what the rest of the game asks about it.
##
##  Rooms   FacilityRoom nodes: each one's FacilityRoomRect children are its floor (select one and drag its handles, they snap to the 11 px grid)
##  Doors   FacilityDoor scenes dragged into the walls between rooms
##  Vents   Marker2D nodes: the top left corner of a 2 x 2 cell (0.5 m) grille
##  Props   anything that stands on the floor (control panels), y-sorted
##  Actors  where players and other moving things are added, y-sorted
##  Floors, Walls, Shadows   tile layers the map makes and fills in itself from the rooms and doors, in the editor as well as in the game: every cell of
##          a room is floor, every empty cell touching a floor cell is wall (so rooms need a one cell gap), and the floor beside a wall gets a soft
##          shadow. They are not part of the scene file (they are made when it loads and rebuilt a moment after any room or door changes, and can
##          not be selected in the editor), so resizing a room never touches the art. The Rebuild button below redoes them by hand.
##
##Physics layers: walls are on layer 2 (FacilityTileSet.WORLD_LAYER), closed doors on layer 4 (DOOR_LAYER). A player body should have
##a collision mask of 2 | 8 = 10 so walls and doors stop it, and a projectile's world mask should be 2 so only walls stop a bullet.

signal built

const TILE : int = FacilityTileSet.TILE
const EDITOR_REBUILD_DELAY : float = 0.15 #seconds a room or door has to sit still in the editor before the tiles are rebuilt

@export var doors_start : FacilityDoor.State = FacilityDoor.State.CLOSED #the state every door has when the game starts, unless apply_doors_start is off
@export var apply_doors_start : bool = true #off: each door starts in the state it has in the scene
@export var void_color : Color = Color("#07090c") #what shows outside the building. Palette A "void"
@export_tool_button("Rebuild floors, walls and shadows") var rebuild_button : Callable = build

var rooms : Dictionary = {} #room id -> {name, kind, function, rects: Array[Rect2i], exterior: bool}
var floor_cells : Dictionary = {} #Vector2i -> room id
var wall_cells : Dictionary = {} #Vector2i -> true
var doors : Array[FacilityDoor] = []
var vents : Array[Vector2i] = []

var _signature : int = 0 #editor: what the rooms and doors looked like when the tiles were last built
var _changed_for : float = 0.0

var floors : TileMapLayer #made in _ready (see _make_layers), not part of the scene file
var shadows : TileMapLayer
var walls : TileMapLayer
@onready var rooms_node : Node2D = $Rooms
@onready var doors_node : Node2D = $Doors
@onready var vents_node : Node2D = $Vents
@onready var props_node : Node2D = $Props
@onready var actors : Node2D = $Actors


func _ready() -> void:
	_make_layers()
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
		add_child(layer)
		move_child(layer, index)
		index += 1
		set(layer_name.to_lower(), layer)


##Reads the rooms and doors, fills in the floor, wall and shadow layers, and works out which rooms each door joins.
func build() -> void:
	_collect_rooms()
	_collect_doors()
	_compute_walls()
	for layer : TileMapLayer in [floors, shadows, walls]:
		layer.clear()
	_paint_floors()
	_paint_walls()
	_collect_vents()
	_signature = _layout_signature()
	built.emit()


##World position of the centre of a tile.
func cell_to_world(cell : Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


func world_to_cell(world : Vector2) -> Vector2i:
	return Vector2i((world / TILE).floor())


##Id of the room a world position is in, or "" for walls and empty space.
func room_at(world : Vector2) -> String:
	return floor_cells.get(world_to_cell(world), "")


##Bounding rectangles of a room in world pixels (a room can have several, like the corridor ring).
func room_rects_px(room_id : String) -> Array[Rect2]:
	var result : Array[Rect2] = []
	for rect : Rect2i in rooms[room_id]["rects"]:
		result.append(Rect2(Vector2(rect.position * TILE), Vector2(rect.size * TILE)))
	return result


func room_center_px(room_id : String) -> Vector2:
	var rects : Array[Rect2] = room_rects_px(room_id)
	return rects[0].get_center()


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


func map_bounds_px() -> Rect2:
	var bounds : Rect2i
	var first : bool = true
	for cell : Vector2i in wall_cells:
		bounds = Rect2i(cell, Vector2i.ONE) if first else bounds.expand(cell).expand(cell + Vector2i.ONE)
		first = false
	return Rect2(Vector2(bounds.position * TILE), Vector2(bounds.size * TILE))


func _room_nodes() -> Array[FacilityRoom]:
	var result : Array[FacilityRoom] = []
	for child : Node in rooms_node.get_children():
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
	floor_cells.clear()
	var clashes : Dictionary = {} #room id -> another room whose floor it shares
	for room : FacilityRoom in _room_nodes():
		var rects : Array[Rect2i] = room.cell_rects(self)
		for rect : Rect2i in rects:
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var cell : Vector2i = Vector2i(x, y)
					if floor_cells.has(cell) and floor_cells[cell] != room.room_id():
						clashes[room.room_id()] = floor_cells[cell]
						clashes[floor_cells[cell]] = room.room_id()
					floor_cells[cell] = room.room_id()
		var label : String = room.display_name if room.display_name != "" else room.room_id().capitalize()
		rooms[room.room_id()] = {"name": label, "kind": room.kind_name(), "function": room.function_name(), "rects": rects, "exterior": false}
	if Engine.is_editor_hint(): #the editor says so on a room that overlaps another
		for room : FacilityRoom in _room_nodes():
			room.set_clash(clashes.get(room.room_id(), ""))


##Each door's cells join the room on its north or west side (so the floor under the door matches), and the door learns both its rooms.
func _collect_doors() -> void:
	doors.clear()
	var index : int = 0
	var room_cells : Dictionary = floor_cells.duplicate() #the rooms' own cells, before any door cell is added
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
		door.room_a = room_cells.get(first, "")
		door.room_b = room_cells.get(second, "")
		if Engine.is_editor_hint(): #the editor says so on a door that is not between two different rooms
			door.set_problem("" if door.room_a != "" and door.room_b != "" and door.room_a != door.room_b else "This door is not in the wall between two different rooms. Drag it onto the one cell gap between them.")
		door.door_index = index
		var outside : bool = false
		for side : String in [door.room_a, door.room_b]:
			if side != "" and rooms[side]["kind"] == "outdoor":
				outside = true
		door.exterior = outside
		if outside: #the room on the building side counts as an exterior room
			for side : String in [door.room_a, door.room_b]:
				if side != "" and rooms[side]["kind"] != "outdoor":
					rooms[side]["exterior"] = true
		var floor_room : String = door.room_a if door.room_a != "" else door.room_b
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				floor_cells[Vector2i(x, y)] = floor_room
		doors.append(door)
		index += 1


func _compute_walls() -> void:
	wall_cells.clear()
	for cell : Vector2i in floor_cells:
		for offset in FacilityTileSet.NEIGHBOURS:
			if not floor_cells.has(cell + offset):
				wall_cells[cell + offset] = true


func _paint_floors() -> void:
	#one plain floor everywhere; the shading comes from the soft shadows beside the walls
	for cell : Vector2i in floor_cells:
		floors.set_cell(cell, FacilityTileSet.SOURCE_FLOORS, Vector2i.ZERO)
		var mask : int = FacilityTileSet.neighbour_mask(cell, wall_cells)
		if mask != 0:
			shadows.set_cell(cell, FacilityTileSet.SOURCE_SHADOWS, FacilityTileSet.mask_to_atlas(mask))


func _paint_walls() -> void:
	for cell : Vector2i in wall_cells:
		walls.set_cell(cell, FacilityTileSet.SOURCE_WALLS, FacilityTileSet.mask_to_atlas(FacilityTileSet.neighbour_mask(cell, wall_cells)))


func _collect_vents() -> void:
	#only the positions: there is no vent art in the smooth look
	vents.clear()
	for child : Node in vents_node.get_children():
		if child is Marker2D:
			vents.append(world_to_cell((child as Marker2D).position))


func _snap_to_grid() -> void:
	for room : FacilityRoom in _room_nodes():
		room.snap_to_grid()
	for door : FacilityDoor in _door_nodes():
		door.snap_to_grid()
	for child : Node in vents_node.get_children():
		if child is Marker2D:
			(child as Marker2D).position = ((child as Marker2D).position / TILE).round() * TILE


##A number that changes when a room, door or vent is edited (editor only: tells _process when the tiles need rebuilding).
func _layout_signature() -> int:
	var parts : PackedStringArray = []
	for room : FacilityRoom in _room_nodes():
		parts.append("%s %s %d %d" % [room.name, room.position, room.kind, room.function])
		for rect : FacilityRoomRect in room.rects():
			parts.append("%s %s" % [rect.position, rect.size])
	for door : FacilityDoor in _door_nodes():
		parts.append("%s %s %s" % [door.name, door.position, door.horizontal])
	for child : Node in vents_node.get_children():
		parts.append("%s" % (child as Node2D).position)
	return "|".join(parts).hash()