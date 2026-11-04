class_name FacilityMap
extends Node2D

##Facility 9, built at runtime from facility_layout.json: floors, walls (derived from the floors), doors, vents and
##ceiling lamps. Edit the layout file and run the scene, there is nothing to repaint.
##
##Nodes in facility_map.tscn: Floors, Walls (tile layers), Doors, Props, Lamps, and Actors, the node players and other moving
##things are added to (y-sorted). Ambient is the CanvasModulate that makes everything dark except where a lamp or flashlight reaches.
##
##Physics layers: walls are on layer 2 (FacilityTileSet.WORLD_LAYER), closed doors on layer 4 (DOOR_LAYER). A player body should have
##a collision mask of 2 | 8 = 10 so walls and doors stop it, and a projectile's world mask should be 2 so only walls stop a bullet.

signal built

const LAYOUT_PATH : String = "res://night_shift/environment/facility_layout.json"
const VENT_TEXTURE : String = "res://night_shift/environment/art/vent_grate.png"
const TILE : int = FacilityTileSet.TILE

@export_file("*.json") var layout_path : String = LAYOUT_PATH
@export var build_on_ready : bool = true
@export var doors_start : FacilityDoor.State = FacilityDoor.State.CLOSED
@export var lamps_enabled : bool = true
@export var void_color : Color = Color("#07090c") #what shows outside the building. Palette A "void"

var rooms : Dictionary = {} #room id -> {name, kind, function, floor, lamp, rects: Array[Rect2i], exterior: bool}
var floor_cells : Dictionary = {} #Vector2i -> room id
var wall_cells : Dictionary = {} #Vector2i -> true
var doors : Array[FacilityDoor] = []
var vents : Array[Vector2i] = []

@onready var floors : TileMapLayer = $Floors
@onready var walls : TileMapLayer = $Walls
@onready var doors_node : Node2D = $Doors
@onready var props_node : Node2D = $Props
@onready var lamps_node : Node2D = $Lamps
@onready var actors : Node2D = $Actors
@onready var ambient : CanvasModulate = $Ambient


func _ready() -> void:
	RenderingServer.set_default_clear_color(void_color) #the engine's default grey would show wherever there is no tile
	if build_on_ready:
		build()


func build() -> void:
	var layout : Dictionary = _load_layout()
	if layout.is_empty():
		return
	var tile_set : TileSet = FacilityTileSet.build()
	for layer : TileMapLayer in [floors, walls]:
		layer.tile_set = tile_set
		layer.scale = Vector2.ONE * FacilityTileSet.ART_SCALE #the tiles are drawn at 4x resolution, like the character sprites
		layer.clear()
	_read_rooms(layout)
	_read_doors(layout)
	_compute_walls()
	_paint_floors()
	_paint_walls()
	_place_doors(layout)
	_place_vents(layout)
	if lamps_enabled:
		_place_lamps()
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


func _load_layout() -> Dictionary:
	var file : FileAccess = FileAccess.open(layout_path, FileAccess.READ)
	if file == null:
		push_error("FacilityMap cannot open the layout at %s" % layout_path)
		return {}
	var parsed : Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("FacilityMap: %s is not a valid layout" % layout_path)
		return {}
	return parsed


func _read_rooms(layout : Dictionary) -> void:
	rooms.clear()
	floor_cells.clear()
	for room : Dictionary in layout["rooms"]:
		var rects : Array[Rect2i] = []
		for r : Array in room["rects"]:
			var rect : Rect2i = Rect2i(int(r[0]), int(r[1]), int(r[2]) - int(r[0]) + 1, int(r[3]) - int(r[1]) + 1)
			rects.append(rect)
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					floor_cells[Vector2i(x, y)] = room["id"]
		rooms[room["id"]] = {"name": room["name"], "kind": room["kind"], "function": room.get("function", ""),
			"floor": room["floor"], "lamp": room.get("lamp", ""), "rects": rects, "exterior": false}


func _read_doors(layout : Dictionary) -> void:
	for door : Dictionary in layout["doors"]:
		var r : Array = door["rect"]
		for y in range(int(r[1]), int(r[3]) + 1):
			for x in range(int(r[0]), int(r[2]) + 1):
				#a door cell is floor of the room it belongs to, so the floor under the door matches
				floor_cells[Vector2i(x, y)] = door["a"]
		if door.get("exterior", false):
			rooms[door["a"]]["exterior"] = true


func _compute_walls() -> void:
	wall_cells.clear()
	for cell : Vector2i in floor_cells:
		for offset in FacilityTileSet.NEIGHBOURS:
			if not floor_cells.has(cell + offset):
				wall_cells[cell + offset] = true


func _paint_floors() -> void:
	for cell : Vector2i in floor_cells:
		var kind : String = rooms[floor_cells[cell]]["floor"]
		var row : int = FacilityTileSet.FLOOR_KINDS.find(kind)
		var noise : int = (cell.x * 73856093 ^ cell.y * 19349663) & 0xFF
		var variant : int
		if kind == "room":
			variant = (cell.x + cell.y) % 2 + 2 * (noise % 2) #the checker needs the parity, the rest is noise
		else:
			variant = 3 if noise % 14 == 0 else noise % 3 #variant 3 is the rare cracked tile
		floors.set_cell(cell, FacilityTileSet.SOURCE_FLOORS, Vector2i(variant, row))


func _paint_walls() -> void:
	for cell : Vector2i in wall_cells:
		walls.set_cell(cell, FacilityTileSet.SOURCE_WALLS, FacilityTileSet.mask_to_atlas(FacilityTileSet.neighbour_mask(cell, wall_cells)))


func _place_doors(layout : Dictionary) -> void:
	for node in doors_node.get_children():
		node.queue_free()
	doors.clear()
	var index : int = 0
	for door_data : Dictionary in layout["doors"]:
		var r : Array = door_data["rect"]
		var cell_min : Vector2i = Vector2i(int(r[0]), int(r[1]))
		var cell_size : Vector2i = Vector2i(int(r[2]) - int(r[0]) + 1, int(r[3]) - int(r[1]) + 1)
		var door : FacilityDoor = FacilityDoor.new()
		door.horizontal = cell_size.x >= cell_size.y
		door.exterior = door_data.get("exterior", false)
		door.state = doors_start
		door.door_index = index
		door.room_a = door_data["a"]
		door.room_b = door_data["b"]
		door.name = "Door%d_%s_%s" % [index, door.room_a, door.room_b]
		door.position = Vector2(cell_min * TILE) + Vector2(cell_size * TILE) / 2.0
		doors_node.add_child(door)
		doors.append(door)
		index += 1


func _place_vents(layout : Dictionary) -> void:
	vents.clear()
	var texture : Texture2D = load(VENT_TEXTURE)
	for v : Array in layout.get("vents", []):
		var cell : Vector2i = Vector2i(int(v[0]), int(v[1]))
		vents.append(cell)
		var sprite : Sprite2D = Sprite2D.new()
		sprite.texture = texture
		sprite.position = cell_to_world(cell)
		sprite.scale = Vector2.ONE * FacilityTileSet.ART_SCALE
		sprite.name = "Vent_%d_%d" % [cell.x, cell.y]
		props_node.add_child(sprite)


func _place_lamps() -> void:
	for node in lamps_node.get_children():
		node.queue_free()
	for id : String in rooms:
		var room : Dictionary = rooms[id]
		if room["lamp"] == "":
			continue
		var color : Color = Color("#e07b2a") if room["lamp"] == "warm" else Color("#f2b544")
		var rect_index : int = 0
		for rect : Rect2i in room["rects"]:
			#one lamp per 7 m of room, spread evenly; a long corridor gets a lamp every few metres
			var nx : int = maxi(1, roundi(rect.size.x / 14.0))
			var ny : int = maxi(1, roundi(rect.size.y / 14.0))
			for iy in ny:
				for ix in nx:
					var cell : Vector2 = Vector2(rect.position) + Vector2((ix + 0.5) * rect.size.x / nx, (iy + 0.5) * rect.size.y / ny)
					var lamp : FacilityLamp = FacilityLamp.new()
					lamp.color = color
					lamp.radius_m = clampf(maxf(rect.size.x / nx, rect.size.y / ny) * 0.5 * 0.5 + 2.0, 4.0, 8.0)
					lamp.position = cell * TILE
					lamp.name = "Lamp_%s_%d_%d_%d" % [id, rect_index, ix, iy]
					lamps_node.add_child(lamp)
			rect_index += 1
