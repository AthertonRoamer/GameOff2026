class_name VentsLayer
extends MapLayer

##The vents of the facility, as little grilles. On the vent map (interactive) the vent the player is at is ringed, the others can be clicked (picked), and the one under the mouse lights up.

signal picked(vent : Vent)

const CLICK_SLACK_PX : float = 14.0

@export var interactive : bool = true
@export var size_px : float = 12.0 ## the symbol's size on screen

var vents : Array[Vent] = []
var from : Vent
var _hover : Vent


func vent_at(world : Vector2) -> Vent:
	var best : Vent = null
	var best_distance : float = px(CLICK_SLACK_PX)
	for vent : Vent in vents:
		var distance : float = vent.centre().distance_to(world)
		if vent != from and distance <= best_distance:
			best = vent
			best_distance = distance
	return best


func map_hover(world : Vector2) -> void:
	var now : Vent = vent_at(world) if interactive else null
	if now != _hover:
		_hover = now
		queue_redraw()


func map_click(world : Vector2) -> bool:
	var vent : Vent = vent_at(world) if interactive else null
	if vent == null:
		return false
	picked.emit(vent)
	return true


func _draw() -> void:
	for vent : Vent in vents:
		if not is_instance_valid(vent):
			continue
		var at : Vector2 = vent.centre()
		if vent == from:
			draw_arc(at, px(size_px * 0.9), 0.0, TAU, 24, Palette.BACKUP, px(2.0))
		var half : float = px(size_px * (0.65 if vent == _hover else 0.5))
		var box : Rect2 = Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_rect(box.grow(px(1.5)), Palette.VOID)
		draw_rect(box, Palette.BACKUP if vent == _hover or vent == from else Palette.OK)
		for slat : int in 3: #the grille's slots
			draw_rect(Rect2(box.position + Vector2(box.size.x * 0.18, box.size.y * (0.2 + 0.25 * slat)), Vector2(box.size.x * 0.64, box.size.y * 0.11)), Palette.VOID)


func icon_label(world : Vector2) -> String:
	for vent : Vent in vents:
		if is_instance_valid(vent) and vent.centre().distance_to(world) <= px(size_px / 2.0 + 4.0):
			return "Vent (you are here)" if vent == from else "Vent"
	return ""
