class_name MuzzleFlash
extends Node2D

##The flash at the end of a gun when it fires: a small star of warm light pointing along the barrel, plus a short burst of real light that
##lights the walls and the shooter in the dark. It sits under the torso at the end of the barrel; the torso already turns to face the aim, so
##the flash points the way the gun does (local up, like the sprite sheets). Call flash() once per shot.

@export var length : float = 76.0 #in the skin's own pixels (the skin is scaled 0.25), so about 16 px in the world
@export var width : float = 52.0
@export var duration : float = 0.07
@export var light_radius_m : float = 3.0
@export var light_energy : float = 1.8
@export var color : Color = Color("#ffd07a")

static var _light_texture : GradientTexture2D

var _flash_left : float = 0.0
var _scale : float = 1.0
var _tilt : float = 0.0
var _light : PointLight2D


func _ready() -> void:
	_light = PointLight2D.new()
	_light.texture = _get_light_texture()
	var inherited : float = global_transform.get_scale().x
	_light.texture_scale = light_radius_m * 44.0 * 2.0 / _light.texture.get_width() / inherited
	_light.color = color
	_light.energy = light_energy
	_light.shadow_enabled = true
	_light.enabled = false
	add_child(_light)
	var additive : CanvasItemMaterial = CanvasItemMaterial.new() #the flash adds to what is behind it, so it still glows under the darkness
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	set_process(false)


func flash() -> void:
	_flash_left = duration
	_scale = randf_range(0.8, 1.2)
	_tilt = randf_range(-0.2, 0.2)
	_light.enabled = true
	set_process(true)
	queue_redraw()


func _process(delta : float) -> void:
	_flash_left -= delta
	if _flash_left <= 0.0:
		_light.enabled = false
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _flash_left <= 0.0:
		return
	var fade : float = clampf(_flash_left / duration, 0.0, 1.0)
	var l : float = length * _scale
	var w : float = width * _scale * 0.5
	#outer star, orange: a long point forward, short points to the sides and a little backward
	var outer : PackedVector2Array = PackedVector2Array([
		Vector2(0, -l), Vector2(w * 0.28, -l * 0.34), Vector2(w, -l * 0.18), Vector2(w * 0.36, -l * 0.04),
		Vector2(w * 0.5, l * 0.16), Vector2(0, l * 0.04), Vector2(-w * 0.5, l * 0.16), Vector2(-w * 0.36, -l * 0.04),
		Vector2(-w, -l * 0.18), Vector2(-w * 0.28, -l * 0.34)])
	var tilt : Transform2D = Transform2D(_tilt, Vector2.ZERO)
	draw_colored_polygon(tilt * outer, Color(color.r, color.g * 0.8, color.b * 0.5, 0.85 * fade))
	#inner star, pale yellow, and a white core
	draw_colored_polygon(tilt * (Transform2D(0.0, Vector2(0.55, 0.62), 0.0, Vector2.ZERO) * outer), Color(1.0, 0.95, 0.7, 0.95 * fade))
	draw_circle(Vector2.ZERO, w * 0.32, Color(1, 1, 1, fade))


static func _get_light_texture() -> GradientTexture2D:
	if _light_texture == null:
		var gradient : Gradient = Gradient.new()
		gradient.colors = PackedColorArray([Color.WHITE, Color.BLACK])
		_light_texture = GradientTexture2D.new()
		_light_texture.gradient = gradient
		_light_texture.fill = GradientTexture2D.FILL_RADIAL
		_light_texture.fill_from = Vector2(0.5, 0.5)
		_light_texture.fill_to = Vector2(1.0, 0.5)
		_light_texture.width = 128
		_light_texture.height = 128
	return _light_texture
