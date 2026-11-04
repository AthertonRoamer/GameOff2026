class_name ShoulderLamp
extends Node2D

##The flashlight as a thing on the character: a small, black, shoulder-mounted lamp, drawn in code in the same cel style as the character (flat tones
##with hard edges, no gradients: a base tone, one shaded band, one lit band, a thin ink outline). It sits under the torso at the right shoulder and
##points forward (local up, like the sprite sheets). The Flashlight node is its child, at the lens, so the beam comes out of the lamp. The skin slides
##the lamp between a holstered and a drawn position. Sizes are in the skin's own pixels (the skin is scaled 0.25).

const INK : Color = Color("#06080c")
const BASE : Color = Color("#161b23")
const SHADE : Color = Color("#0c0f15") #the cel shadow band, on the side away from the light
const LIT : Color = Color("#313a49") #the cel highlight band, on the lit side and the top edge
const LENS_OFF : Color = Color("#232b37")
const LENS_ON : Color = Color("#e9dcae")

@onready var flashlight : Flashlight = $Flashlight

var _was_on : bool = false


func _process(_delta : float) -> void:
	if flashlight.on != _was_on:
		_was_on = flashlight.on
		queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * 0.5) #drawn at a comfortable size, then shrunk to sit quietly on a shoulder
	var body : Rect2 = Rect2(-8.0, -11.0, 16.0, 26.0)
	var shape : PackedVector2Array = _rounded_rect(body, 6.0)
	draw_colored_polygon(_rounded_rect(body.grow(2.5), 8.0), INK) #ink outline
	draw_colored_polygon(shape, BASE)
	_draw_clipped(shape, Rect2(2.0, -11.0, 6.0, 26.0), SHADE) #the shaded side
	_draw_clipped(shape, Rect2(-8.0, -11.0, 4.0, 26.0), LIT) #the lit side
	_draw_clipped(shape, Rect2(-8.0, -11.0, 16.0, 3.0), LIT) #the top edge catches the light
	_draw_clipped(shape, Rect2(-8.0, 10.0, 16.0, 5.0), SHADE) #the shaded back
	draw_colored_polygon(_rounded_rect(Rect2(-6.5, -14.5, 13.0, 5.0), 2.0), INK)
	draw_colored_polygon(_rounded_rect(Rect2(-5.0, -13.5, 10.0, 3.0), 1.2), LENS_ON if _was_on else LENS_OFF) #the lens: a plain lit strip, no glow around it


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
