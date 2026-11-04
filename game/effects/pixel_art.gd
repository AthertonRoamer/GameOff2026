extends CanvasLayer

##A pixel art pass over the whole picture (see pixel_art.gdshader). It is an autoload, so it covers every scene; press P to turn it on and off.
##It sits above the game world but below `ui_layer` and up: canvas layers numbered `ui_layer` or more (menus, HUD, the door screen) stay sharp, so
##their text stays readable. Set `affect_ui` to true to put it over those too.

const SHADER : Shader = preload("res://game/effects/pixel_art.gdshader")

@export var enabled : bool = true : set = set_enabled
@export var pixel_size : float = 4.0 : set = set_pixel_size
@export var levels : float = 24.0
@export var dither_strength : float = 0.6
@export var edge_strength : float = 0.35
@export var ui_layer : int = 20 #canvas layers from here up are not pixelated
@export var affect_ui : bool = false

var _rect : ColorRect
var _material : ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = ui_layer - 1 if not affect_ui else 100
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_apply()


func _input(event : InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_P:
		enabled = not enabled


func set_enabled(value : bool) -> void:
	enabled = value
	if _rect != null:
		_apply()


func set_pixel_size(value : float) -> void:
	pixel_size = value
	if _rect != null:
		_apply()


func _apply() -> void:
	_rect.visible = enabled
	_material.set_shader_parameter("pixel_size", pixel_size)
	_material.set_shader_parameter("levels", levels)
	_material.set_shader_parameter("dither_strength", dither_strength)
	_material.set_shader_parameter("edge_strength", edge_strength)
