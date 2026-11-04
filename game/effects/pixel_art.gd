extends CanvasLayer

##The pixel art shader (pixel_sprite.gdshader) over the whole game: the finished picture, HUD and menus included, is redrawn in big square pixels.
##It is an autoload (project settings, named PixelArt), so it covers every scene. P turns it on and off.

const SHADER : Shader = preload("res://game/effects/pixel_sprite.gdshader")

signal toggled(on : bool)

@export var enabled : bool = true : set = set_enabled
@export var pixel_size : float = 3.0 : set = set_pixel_size #one big pixel, in screen pixels

var _rect : ColorRect
var _material : ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100 #above every other canvas layer, so everything is pixelated
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
	if enabled == value:
		return
	enabled = value
	if _rect != null:
		_apply()
	toggled.emit(enabled)


func set_pixel_size(value : float) -> void:
	pixel_size = value
	if _rect != null:
		_apply()


func _apply() -> void:
	_rect.visible = enabled
	_material.set_shader_parameter("pixel_size", pixel_size)
