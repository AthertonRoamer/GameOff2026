class_name VentsLayer
extends MapLayer

##The vents of the facility as dots. The vent the player is at is ringed; the others can be clicked (picked), and the one under the mouse lights up.

signal picked(vent : Vent)

const CLICK_SLACK_PX : float = 14.0

var vents : Array[Vent] = []
var from : Vent
var _hover : Vent


func vent_at(world : Vector2) -> Vent:
	var best : Vent = null
	var best_distance : float = px(CLICK_SLACK_PX)
	for vent : Vent in vents:
		var distance : float = vent.global_position.distance_to(world)
		if vent != from and distance <= best_distance:
			best = vent
			best_distance = distance
	return best


func map_hover(world : Vector2) -> void:
	var now : Vent = vent_at(world)
	if now != _hover:
		_hover = now
		queue_redraw()


func map_click(world : Vector2) -> bool:
	var vent : Vent = vent_at(world)
	if vent == null:
		return false
	picked.emit(vent)
	return true


func _draw() -> void:
	for vent : Vent in vents:
		var at : Vector2 = vent.global_position
		if vent == from:
			draw_arc(at, px(10.0), 0.0, TAU, 24, Palette.BACKUP, px(2.0))
		draw_circle(at, px(7.0 if vent == _hover else 5.0), Palette.BACKUP if vent == _hover or vent == from else Palette.OK)
		draw_circle(at, px(2.0), Palette.VOID)
