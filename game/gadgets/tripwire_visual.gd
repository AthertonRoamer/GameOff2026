class_name TripwireVisual
extends Node2D

##A tripwire's wire on the floor: a thin line between its two ends with a peg at each. A child of its Pickup, so it is seen as well as the pickup is.

const WIRE : Color = Color(0.82, 0.86, 0.9, 0.55)
const PEG : Color = Color(0.55, 0.58, 0.62, 0.9)

var ends : PackedVector2Array = PackedVector2Array() #world


func _ready() -> void:
	z_index = -1 #(under the device's icon)
	queue_redraw()


func _draw() -> void:
	if ends.size() < 2:
		return
	var a : Vector2 = to_local(ends[0])
	var b : Vector2 = to_local(ends[1])
	draw_line(a, b, WIRE, 1.0, true)
	for end : Vector2 in [a, b]:
		draw_circle(end, 2.5, PEG)
