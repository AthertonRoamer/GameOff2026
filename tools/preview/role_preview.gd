extends Node2D

## A test render of every role in a pose that shows what it does, for planning the role reveal's intro animations. Not part of the game.
##   Godot.exe --path . res://tools/preview/role_preview.tscn -- <output.png>
## Each figure is the real skin (PlayerSkin + the role's sheets), driven the way Player drives it, so what shows is what the sheets can do now. Poses the sheets do not have
## (reviving, a vent, a console) are suggested with a prop beside the figure.

const WARMUP_FRAMES : int = 150
const SPACING : float = 130.0
const ROW_HEIGHT : float = 160.0
const COLUMNS : int = 4
const ZOOM : float = 1.9
const SKIN_SCENE : PackedScene = preload("res://game/player/skin/player_skin.tscn")

## role, the pose (what update_visual is given), the line under the name
const POSES : Array[Dictionary] = [
	{"role": "res://game/roles/guard.tres", "aim": Vector2(0.35, -1), "gun": true, "line": "pistol drawn"},
	{"role": "res://game/roles/gunner.tres", "aim": Vector2(0.35, -1), "gun": true, "line": "shotgun drawn"},
	{"role": "res://game/roles/shade.tres", "aim": Vector2(0, -1), "move": Vector2(0, -1), "run": true, "line": "runs quietly"},
	{"role": "res://game/roles/medic.tres", "aim": Vector2(1, 0.15), "console": "body", "line": "bends over a fallen player"},
	{"role": "res://game/roles/technician.tres", "aim": Vector2(0, -1), "console": "panel", "line": "works a panel"},
	{"role": "res://game/roles/ventrat.tres", "aim": Vector2(0, -1), "vent": true, "line": "slips into a vent"},
	{"role": "res://game/roles/infiltrator.tres", "aim": Vector2(-0.35, -1), "gun": true, "line": "attacker, pistol drawn"},
]

var _skins : Array = [] # {"skin", "pose"}
var _frame : int = 0
var _output : String = ""


func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	_output = args[0] if not args.is_empty() else "role_preview.png"
	var viewport_size : Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var floor_rect : ColorRect = ColorRect.new()
	floor_rect.color = Color("#1b2128")
	floor_rect.size = Vector2(4000, 2000)
	floor_rect.position = Vector2(-2000, -1000)
	floor_rect.z_index = -20
	add_child(floor_rect)
	var camera : Camera2D = Camera2D.new()
	camera.zoom = Vector2.ONE * ZOOM
	add_child(camera)
	var layer : CanvasLayer = CanvasLayer.new()
	add_child(layer)
	for i in POSES.size():
		var pose : Dictionary = POSES[i]
		var role : Role = load(pose["role"])
		var in_row : int = mini(COLUMNS, POSES.size() - (i / COLUMNS) * COLUMNS)
		var centre : Vector2 = Vector2((i % COLUMNS - (in_row - 1) / 2.0) * SPACING, (i / COLUMNS - 0.5) * ROW_HEIGHT)
		_add_prop(pose, centre)
		var skin : Node2D = SKIN_SCENE.instantiate()
		skin.position = centre
		add_child(skin)
		skin.use_skin(role.skin, role.legs_tint)
		_skins.append({"skin": skin, "pose": pose})
		var label : Label = Label.new()
		label.text = "%s\n%s" % [role.role_name.to_upper(), pose["line"]]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", role.color.lerp(Color.WHITE, 0.35))
		label.size = Vector2(SPACING * ZOOM, 60)
		label.position = viewport_size / 2.0 + centre * ZOOM + Vector2(-SPACING * ZOOM / 2.0, 52 * ZOOM)
		layer.add_child(label)
		if pose.get("console") == "body": #the fallen player the medic bends over
			var fallen : Node2D = SKIN_SCENE.instantiate()
			fallen.position = centre + Vector2(34, 6)
			add_child(fallen)
			fallen.use_skin("guard")
			_skins.append({"skin": fallen, "pose": {"fallen": true}})


func _add_prop(pose : Dictionary, centre : Vector2) -> void:
	var prop : Node2D = Node2D.new()
	prop.position = centre
	prop.z_index = -10
	prop.set_script(load("res://tools/preview/role_preview_prop.gd"))
	prop.set("kind", String(pose.get("console", "vent" if pose.get("vent", false) else "")))
	add_child(prop)


func _process(_delta : float) -> void:
	_frame += 1
	for entry : Dictionary in _skins:
		var skin : Node2D = entry["skin"]
		var pose : Dictionary = entry["pose"]
		if pose.get("fallen", false):
			if _frame == 2:
				skin.die(0.0)
			continue
		var velocity : Vector2 = pose.get("move", Vector2.ZERO) * 380.0
		skin.update_visual(velocity, pose["aim"], pose.get("gun", false), pose.get("run", false), pose.has("console"), 0, 0.0)
	if _frame == WARMUP_FRAMES:
		var image : Image = get_viewport().get_texture().get_image()
		image.save_png(_output)
		print("RENDERED ", _output, " ", image.get_size())
		get_tree().quit()
