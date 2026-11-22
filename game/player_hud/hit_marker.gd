class_name HitMarker
extends Control

## A small X over the mouse for a moment when the player's shot hit someone (see PlayerHud.bind_hitscan).

const SECONDS : float = 0.22

var _left : float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func flash() -> void:
	_left = SECONDS
	set_process(true)


func _process(delta : float) -> void:
	_left -= delta
	if _left <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _left <= 0.0:
		return
	var at : Vector2 = get_local_mouse_position()
	var colour : Color = Color(Palette.TEXT, _left / SECONDS)
	for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		draw_line(at + corner * 5.0, at + corner * 11.0, colour, 2.0)