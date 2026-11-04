extends Node

##The pixel art look for sprites. Sprites that want it ask for a material (make_material) and show it while `enabled` is on; P turns it on and off for
##all of them at once (they listen to `toggled`). The shader is pixel_sprite.gdshader. It is an autoload (project settings), named PixelArt.
##Only sprites that have this material are changed: the characters and the doors. The tile map and anything drawn in code keep the smooth look.

signal toggled(on : bool)

const SHADER : Shader = preload("res://game/effects/pixel_sprite.gdshader")

@export var enabled : bool = true : set = set_enabled
@export var art_pixels_per_pixel : float = 8.0 #the size of one big pixel, in the sprite sheet's own pixels (176 per metre, so 8 is 5 cm)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func make_material() -> ShaderMaterial:
	var material : ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("art_pixels_per_pixel", art_pixels_per_pixel)
	return material


func _input(event : InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_P:
		enabled = not enabled


func set_enabled(value : bool) -> void:
	if enabled == value:
		return
	enabled = value
	toggled.emit(enabled)
