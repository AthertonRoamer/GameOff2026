extends Node2D

##Fly-around viewer for the facility, so the art and scale can be checked without a player scene.
##  WASD / arrows  move the camera (hold Shift for fast)      1, 2, 3  camera zoom      M  map overview
##  R  all doors open / closed       B  show a 1 m reference box
##Command line (after --):  --shot=<png> [--at=x,y] [--zoom=n] [--room=<id>] [--doors=open]
##  [--ref=<folder with the cel legs_idle.png and torso_idle_aim.png> --ref_at=x,y]  saves a screenshot and quits.

const SPEED : float = 420.0

@onready var facility : FacilityMap = $FacilityMap
@onready var camera : Camera2D = $Camera2D

var _doors_open : bool = false
var _overview : bool = false
var _last_zoom : float = 2.0
var _shot_path : String = ""
var _shot_frames : int = 0
var _meter_box : bool = false


func _ready() -> void:
	var args : Dictionary = _parse_args()
	camera.position = facility.map_bounds_px().get_center()
	camera.zoom = Vector2.ONE * float(args.get("zoom", 2.0))
	_last_zoom = camera.zoom.x
	await get_tree().process_frame
	if args.has("room"):
		camera.position = facility.room_center_px(args["room"])
	if args.has("at"):
		var parts : PackedStringArray = String(args["at"]).split(",")
		camera.position = Vector2(float(parts[0]), float(parts[1]))
	if args.has("doors") and args["doors"] == "open":
		_set_doors(true)
	if args.has("ref"): #a character drawn for scale
		_add_reference_character(String(args["ref"]), String(args.get("ref_at", "400,400")))
	if args.has("shot"):
		_shot_path = args["shot"]


func _process(delta : float) -> void:
	var move : Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	camera.position += move * SPEED * delta / camera.zoom.x * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if _shot_path != "":
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
			_overview = false
			camera.zoom = Vector2.ONE * float((event as InputEventKey).keycode - KEY_0)
			_last_zoom = camera.zoom.x
		KEY_M:
			_overview = not _overview
			camera.zoom = Vector2.ONE * (0.5 if _overview else _last_zoom)
			if _overview:
				camera.position = facility.map_bounds_px().get_center()
		KEY_R:
			_set_doors(not _doors_open)
		KEY_B:
			_meter_box = not _meter_box


func _draw() -> void:
	if _meter_box: #a 1 m x 1 m square and a half metre one, for judging scale against the kit's characters
		var origin : Vector2 = camera.position
		draw_rect(Rect2(origin + Vector2(40, 40), Vector2(44, 44)), Color("#4be38a"), false, 1.0)
		draw_rect(Rect2(origin + Vector2(100, 40), Vector2(22, 22)), Color("#6fd3e8"), false, 1.0)


func _add_reference_character(folder : String, at : String) -> void:
	var parts : PackedStringArray = at.split(",")
	for sheet in ["legs_idle.png", "torso_idle_aim.png"]:
		var image : Image = Image.load_from_file(folder.path_join(sheet))
		if image == null:
			push_warning("reference sprite %s not found" % folder.path_join(sheet))
			return
		var sprite : Sprite2D = Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, 256, 256) #first frame of the 256 px cel sheet
		sprite.offset = Vector2(0, -21.2) #godot_offset from the sheet's sprites.json: puts the hips on the origin
		sprite.scale = Vector2.ONE * 0.25 #176 px per metre down to the world's 44
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.position = Vector2(float(parts[0]), float(parts[1]))
		facility.actors.add_child(sprite)


func _set_doors(open : bool) -> void:
	_doors_open = open
	for door in facility.doors:
		door.state = FacilityDoor.State.OPEN if open else FacilityDoor.State.CLOSED


func _parse_args() -> Dictionary:
	var result : Dictionary = {}
	for arg : String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts : PackedStringArray = arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1] if parts.size() > 1 else true
	return result
