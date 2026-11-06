@tool
class_name ShoulderLamp
extends Node2D

##The flashlight as a thing on the character: a small, black, shoulder-mounted lamp, drawn in code in the same cel style as the character (flat tones
##with hard edges, no gradients: a base tone, one shaded band, one lit band, a thin ink outline). It sits under the torso at the right shoulder and
##points forward (local up, like the sprite sheets). The Flashlight node is its child, at the lens, so the beam comes out of the lamp. The skin moves
##the lamp along the shoulder as the animation plays (night_shift_character.gd). The colours and size are exports, and the lamp is a tool script, so it
##shows in the editor and can be restyled there. Sizes are in the skin's own pixels (the skin is scaled 0.25).

@export var ink : Color = Color("#06080c") : set = _set_colour
@export var base : Color = Color("#161b23") : set = _set_colour
@export var shade : Color = Color("#0c0f15") : set = _set_colour #the cel shadow band, on the side away from the light
@export var lit : Color = Color("#313a49") : set = _set_colour #the cel highlight band, on the lit side and the top edge
@export var lens_off : Color = Color("#232b37") : set = _set_colour
@export var lens_on : Color = Color("#e9dcae") : set = _set_colour
@export var draw_scale : float = 0.5 : set = _set_scale #drawn at a comfortable size, then shrunk to sit quietly on a shoulder
@export var preview_lens_on : bool = false : set = _set_colour #editor only: shows the lens lit

@onready var flashlight : Node = $Flashlight #a Flashlight; untyped so the lamp can also run in the editor, where scripts that are not tools are only placeholders

var _was_on : bool = false


func _process(_delta : float) -> void:
	if Engine.is_editor_hint():
		return
	if flashlight.on != _was_on:
		_was_on = flashlight.on
		queue_redraw()


func _set_colour(_value = null) -> void:
	queue_redraw()


func _set_scale(value : float) -> void:
	draw_scale = value
	queue_redraw()


func _draw() -> void:
	var lens_is_on : bool = _was_on or (Engine.is_editor_hint() and preview_lens_on)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * draw_scale)
	var body : Rect2 = Rect2(-8.0, -11.0, 16.0, 26.0)
	var shape : PackedVector2Array = _rounded_rect(body, 6.0)
	draw_colored_polygon(_rounded_rect(body.grow(2.5), 8.0), ink) #ink outline
	draw_colored_polygon(shape, base)
	_draw_clipped(shape, Rect2(2.0, -11.0, 6.0, 26.0), shade) #the shaded side
	_draw_clipped(shape, Rect2(-8.0, -11.0, 4.0, 26.0), lit) #the lit side
	_draw_clipped(shape, Rect2(-8.0, -11.0, 16.0, 3.0), lit) #the top edge catches the light
	_draw_clipped(shape, Rect2(-8.0, 10.0, 16.0, 5.0), shade) #the shaded back
	draw_colored_polygon(_rounded_rect(Rect2(-6.5, -14.5, 13.0, 5.0), 2.0), ink)
	draw_colored_polygon(_rounded_rect(Rect2(-5.0, -13.5, 10.0, 3.0), 1.2), lens_on if lens_is_on else lens_off) #the lens: a plain lit strip, no glow around it


##A band of flat tone, cut to the lamp's rounded outline so it follows the corners.
func _draw_clipped(outline : PackedVector2Array, band : Rect2, color : Color) -> void:
	var band_polygon : PackedVector2Array = PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)])
	for piece : PackedVector2Array in Geometry2D.intersect_polygons(outline, band_polygon):
		draw_colored_polygon(piece, color)


static func _rounded_rect(rect : Rect2, radius : float, steps : int = 6) -> PackedVector2Array:
	var points : PackedVector2Array = PackedVector2Array()
	var corners : Array[Vector2] = [Vector2(rect.end.x - radius, rect.position.y + radius), Vector2(rect.end.x - radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.end.y - radius), Vector2(rect.position.x + radius, rect.position.y + radius)]
	for i in 4:
		for s in steps + 1:
			points.append(corners[i] + Vector2.from_angle((i - 1) * PI / 2.0 + s * PI / 2.0 / steps) * radius)
	return points
