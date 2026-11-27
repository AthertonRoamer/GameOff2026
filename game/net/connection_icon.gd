@tool
class_name ConnectionIcon
extends Control

## The connection symbol: three signal bars. A weak connection leaves one lit, amber; a lost one has them all dim with a red cross.

@export var state : ConnectionMonitor.State = ConnectionMonitor.State.WEAK :
	set(value):
		state = value
		queue_redraw()


func _draw() -> void:
	var lost : bool = state == ConnectionMonitor.State.LOST
	var colour : Color = Palette.ALARM if lost else Palette.BACKUP
	var width : float = size.x / 4.0
	for i in 3:
		var height : float = size.y * (0.4 + 0.3 * i)
		var bar : Rect2 = Rect2(i * (width * 1.5), size.y - height, width, height)
		var lit : bool = not lost and i == 0
		draw_rect(bar.grow(1.5), Palette.VOID)
		draw_rect(bar, colour if lit else Palette.METAL)
	if lost:
		var centre : Vector2 = Vector2(size.x * 0.78, size.y * 0.3)
		var arm : float = size.y * 0.24
		for way : Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
			draw_line(centre - way * arm, centre + way * arm, Palette.VOID, 6.0)
		for way : Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
			draw_line(centre - way * arm, centre + way * arm, colour, 3.0)
