extends Node2D

##Art demo for the facility look: 44 px tiles (1 m), walls seen from the front, panelled floor, hazard stripes, vent grille, a door and
##a console, lit by amber lamps and a flashlight. It is a small hand-written map (see MAP), not the full facility.
##  WASD / arrows  move the camera       1, 2, 3  zoom       F  flashlight at the camera centre, aimed at the mouse
##  L  lamps on/off       R  door open/closed       B  1 m reference box
##Command line (after --):  --shot=<png> [--zoom=n] [--at=x,y] [--flash] [--angle=radians] [--lamps=off] [--doors=open]
##                          [--ref=<folder with legs_idle.png and torso_idle_aim.png> --ref_at=tileX,tileY]  (draws a character for scale)

const T : int = 44
const ART : String = "res://night_shift/environment/demo/art/"

### wall  . floor  D door (in a wall front)  C console on a wall front  V vent grille  h e s w floor with a hazard stripe on that edge
const MAP : PackedStringArray = [
	"########################",
	"#......................#",
	"#......................#",
	"#......................#",
	"######D#########C#######",
	"#....hhh...e####.......#",
	"#..V.......e##C#.......#",
	"#......................#",
	"########################",
]

const FLOOR_PANELS : int = 4
const FLOOR_VENT : int = 4
const HAZARD : Dictionary = {"h": 5, "e": 6, "s": 7, "w": 8}

@onready var camera : Camera2D = $Camera2D
@onready var floors : TileMapLayer = $Floors
@onready var decals : TileMapLayer = $Decals
@onready var walls : TileMapLayer = $Walls
@onready var doors : Node2D = $Doors
@onready var lamps : Node2D = $Lamps

var _flashlight : Flashlight
var _door_sprites : Array[Sprite2D] = []
var _door_occluders : Array[LightOccluder2D] = []
var _doors_open : bool = false
var _lamps_on : bool = true
var _shot_path : String = ""
var _shot_frames : int = 0
var _meter_box : bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#07090c"))
	var tile_set : TileSet = _build_tile_set()
	for layer : TileMapLayer in [floors, decals, walls]:
		layer.tile_set = tile_set
	_build_map()
	_flashlight = Flashlight.new()
	_flashlight.on = false
	add_child(_flashlight)
	for pos in [Vector2(12, 2.5), Vector2(6, 6.5), Vector2(19.5, 6.5)]:
		var lamp : FacilityLamp = FacilityLamp.new()
		lamp.radius_m = 7.0
		lamp.color = Color("#f2b544").lerp(Color.WHITE, 0.45) #pure amber turns the blue-grey floor olive, so the lamp is a paler amber
		lamp.position = pos * T
		lamps.add_child(lamp)
	var args : Dictionary = _parse_args()
	camera.zoom = Vector2.ONE * float(args.get("zoom", 1.0))
	camera.position = Vector2(MAP[0].length(), MAP.size()) * T / 2.0
	if args.has("at"):
		var parts : PackedStringArray = String(args["at"]).split(",")
		camera.position = Vector2(float(parts[0]), float(parts[1]))
	if args.has("ambient"): #--ambient=1 shows the art without the darkness, for judging the pixels themselves
		$Ambient.color = Color.WHITE.lerp($Ambient.color, 1.0 - float(args["ambient"]))
		if float(args["ambient"]) >= 1.0:
			_set_lamps(false)
	if args.has("lamps") and args["lamps"] == "off":
		_set_lamps(false)
	if args.has("flash"):
		_flashlight.on = true
		_flashlight.rotation = float(args.get("angle", 0.0))
	if args.has("doors") and args["doors"] == "open":
		_set_doors(true)
	if args.has("ref"):
		_add_reference_character(String(args["ref"]), String(args.get("ref_at", "9,6")))
	if args.has("shot"):
		_shot_path = args["shot"]


func _process(delta : float) -> void:
	var move : Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	camera.position += move * 420.0 * delta / camera.zoom.x
	_flashlight.global_position = camera.position
	if _shot_path == "":
		_flashlight.aim_at(get_global_mouse_position())
	else:
		_shot_frames += 1
		if _shot_frames == 6:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()
	queue_redraw()


func _unhandled_key_input(event : InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_1, KEY_2, KEY_3:
			camera.zoom = Vector2.ONE * float((event as InputEventKey).keycode - KEY_0)
		KEY_F:
			_flashlight.on = not _flashlight.on
		KEY_L:
			_set_lamps(not _lamps_on)
		KEY_R:
			_set_doors(not _doors_open)
		KEY_B:
			_meter_box = not _meter_box


func _draw() -> void:
	if _meter_box:
		draw_rect(Rect2(camera.position + Vector2(60, 40), Vector2(T, T)), Color("#4be38a"), false, 1.0)


func _cell(x : int, y : int) -> String:
	if y < 0 or y >= MAP.size() or x < 0 or x >= MAP[y].length():
		return " "
	return MAP[y][x]


func _is_wall(x : int, y : int) -> bool:
	return _cell(x, y) in ["#", "C"]


func _is_floor(x : int, y : int) -> bool:
	return _cell(x, y) in [".", "D", "V", "h", "e", "s", "w"]


func _build_map() -> void:
	for y in MAP.size():
		for x in MAP[y].length():
			var cell : Vector2i = Vector2i(x, y)
			var c : String = _cell(x, y)
			if _is_floor(x, y):
				var noise : int = (x * 73856093 ^ y * 19349663) & 0xFF
				floors.set_cell(cell, 0, Vector2i(FLOOR_VENT if c == "V" else noise % FLOOR_PANELS, 0))
				if HAZARD.has(c):
					decals.set_cell(cell, 0, Vector2i(HAZARD[c], 0))
				if c == "D":
					_add_door(cell)
			elif _is_wall(x, y):
				if _is_floor(x, y + 1): #floor to the south: we see the front of the wall
					var m : int = (1 if _is_floor(x, y - 1) else 0) | (2 if _is_floor(x + 1, y) else 0) | (4 if _is_floor(x - 1, y) else 0)
					var detail : int = 2 if c == "C" else (x * 5 + y * 3) % 2
					walls.set_cell(cell, 2, Vector2i(m, detail))
				else: #otherwise we see the roof; a rim on every side that borders floor
					var closed : int = (0 if _is_floor(x, y - 1) else 1) | (0 if _is_floor(x + 1, y) else 2) \
						| (0 if _is_floor(x, y + 1) else 4) | (0 if _is_floor(x - 1, y) else 8)
					walls.set_cell(cell, 1, Vector2i(closed % 4, closed / 4))


func _add_door(cell : Vector2i) -> void:
	var sprite : Sprite2D = Sprite2D.new()
	sprite.texture = load(ART + "door_closed.png")
	sprite.position = Vector2(cell * T) + Vector2(T, T) / 2.0
	doors.add_child(sprite)
	_door_sprites.append(sprite)
	var occluder : LightOccluder2D = LightOccluder2D.new()
	occluder.occluder = OccluderPolygon2D.new()
	occluder.occluder.polygon = PackedVector2Array([Vector2(-22, -22), Vector2(22, -22), Vector2(22, 22), Vector2(-22, 22)])
	sprite.add_child(occluder)
	_door_occluders.append(occluder)


func _set_doors(open : bool) -> void:
	_doors_open = open
	for i in _door_sprites.size():
		_door_sprites[i].texture = load(ART + ("door_open.png" if open else "door_closed.png"))
		_door_occluders[i].visible = not open


func _set_lamps(on : bool) -> void:
	_lamps_on = on
	for lamp : FacilityLamp in lamps.get_children():
		lamp.powered = on


func _add_reference_character(folder : String, tile : String) -> void:
	var parts : PackedStringArray = tile.split(",")
	for sheet in ["legs_idle.png", "torso_idle_aim.png"]:
		var image : Image = Image.load_from_file(folder.path_join(sheet))
		if image == null:
			push_warning("reference sprite %s not found" % folder.path_join(sheet))
			return
		var sprite : Sprite2D = Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, 64, 64)
		sprite.offset = Vector2(0, -5)
		sprite.position = Vector2((float(parts[0]) + 0.5) * T, (float(parts[1]) + 0.5) * T)
		add_child(sprite)


func _build_tile_set() -> TileSet:
	var tile_set : TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(T, T)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1 << 1)
	tile_set.set_physics_layer_collision_mask(0, 0)
	tile_set.add_occlusion_layer()
	_add_source(tile_set, 0, "floors.png", 9, 1, false)
	_add_source(tile_set, 1, "roofs.png", 4, 4, true)
	_add_source(tile_set, 2, "faces.png", 8, 3, true)
	return tile_set


func _add_source(tile_set : TileSet, id : int, file : String, columns : int, rows : int, solid : bool) -> void:
	var source : TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = load(ART + file)
	source.texture_region_size = Vector2i(T, T)
	for y in rows:
		for x in columns:
			source.create_tile(Vector2i(x, y))
	tile_set.add_source(source, id)
	if not solid:
		return
	var square : PackedVector2Array = PackedVector2Array([Vector2(-22, -22), Vector2(22, -22), Vector2(22, 22), Vector2(-22, 22)])
	for y in rows:
		for x in columns:
			var data : TileData = source.get_tile_data(Vector2i(x, y), 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)
			var occluder : OccluderPolygon2D = OccluderPolygon2D.new()
			occluder.polygon = square
			data.set_occluder(0, occluder)


func _parse_args() -> Dictionary:
	var result : Dictionary = {}
	for arg : String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts : PackedStringArray = arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1] if parts.size() > 1 else true
	return result
