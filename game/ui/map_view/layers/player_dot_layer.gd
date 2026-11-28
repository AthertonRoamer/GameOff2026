class_name PlayerDotLayer
extends MapLayer

##A dot where a player (or any node) is. Set `tracked`; the view must be `live` for the dot to follow it.

var tracked : Node2D


func _draw() -> void:
	if not is_instance_valid(tracked):
		return
	draw_circle(tracked.global_position, px(6.0), Color(Palette.BACKUP, 0.3))
	draw_circle(tracked.global_position, px(3.5), Palette.ITEM)


func icon_label(world : Vector2) -> String:
	return "You" if is_instance_valid(tracked) and tracked.global_position.distance_to(world) <= px(7.0) else ""
