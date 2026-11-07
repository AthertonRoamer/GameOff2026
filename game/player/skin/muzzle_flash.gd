@tool
class_name MuzzleFlash
extends Node2D

##The flash at the end of a gun when it fires: a small star of warm light pointing along the barrel, plus a short burst of real light that
##lights the walls and the shooter in the dark. It sits under the torso at the end of the barrel; the torso already turns to face the aim, so the
##flash points the way the gun does (local up, like the sprite sheets). Call flash() once per shot.
##
##The burst of light is the PointLight2D child "Light" and the additive blending is this node's material, both set up in player_skin.tscn, so how
##the flash lights the room is edited there (colour, energy, size, shadows). The star is drawn here; it is a tool script, so the editor shows it
##at full strength while `preview` is on. Its sizes are in the skin's own pixels (the skin is scaled 0.25).

@export var length : float = 76.0 : set = _set_shape #about 16 px in the world
@export var width : float = 52.0 : set = _set_shape
@export var duration : float = 0.07
@export var color : Color = Color("#ffd07a") : set = _set_colour
@export var preview : bool = true : set = _set_colour #editor only: draws the star so it can be seen and adjusted

var _flash_left : float = 0.0
var _scale : float = 1.0
var _tilt : float = 0.0

@onready var _light : PointLight2D = $Light


func _ready() -> void:
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


func _set_shape(_value = null) -> void:
	queue_redraw()


func _set_colour(_value = null) -> void:
	queue_redraw()


func _draw() -> void:
	var editing : bool = Engine.is_editor_hint()
	if _flash_left <= 0.0 and not (editing and preview):
		return
	var fade : float = 1.0 if editing else clampf(_flash_left / duration, 0.0, 1.0)
	var scale_now : float = 1.0 if editing else _scale
	var tilt_now : float = 0.0 if editing else _tilt
	var l : float = length * scale_now
	var w : float = width * scale_now * 0.5
	#outer star, orange: a long point forward, short points to the sides and a little backward
	var outer : PackedVector2Array = PackedVector2Array([
		Vector2(0, -l), Vector2(w * 0.28, -l * 0.34), Vector2(w, -l * 0.18), Vector2(w * 0.36, -l * 0.04),
		Vector2(w * 0.5, l * 0.16), Vector2(0, l * 0.04), Vector2(-w * 0.5, l * 0.16), Vector2(-w * 0.36, -l * 0.04),
		Vector2(-w, -l * 0.18), Vector2(-w * 0.28, -l * 0.34)])
	var tilt : Transform2D = Transform2D(tilt_now, Vector2.ZERO)
	draw_colored_polygon(tilt * outer, Color(color.r, color.g * 0.8, color.b * 0.5, 0.85 * fade))
	#inner star, pale yellow, and a white core
	draw_colored_polygon(tilt * (Transform2D(0.0, Vector2(0.55, 0.62), 0.0, Vector2.ZERO) * outer), Color(1.0, 0.95, 0.7, 0.95 * fade))
	draw_circle(Vector2.ZERO, w * 0.32, Color(1, 1, 1, fade))
