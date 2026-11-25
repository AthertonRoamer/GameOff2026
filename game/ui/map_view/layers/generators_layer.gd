class_name GeneratorsLayer
extends MapLayer

##The generators, as small squares coloured by state: grey off, amber running, red shot down. A whole-map generator has a ring round it. Needs `grid`.

const SIZE_PX : float = 11.0

var grid : PowerGrid


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null or grid == null:
		return
	for generator : Generator in grid.generators:
		if not is_instance_valid(generator):
			continue
		var at : Vector2 = map.to_local(generator.global_position)
		var colour : Color = Palette.MUTED
		match generator.state:
			Generator.State.RUNNING: colour = Palette.BACKUP
			Generator.State.DESTROYED: colour = Palette.ALARM
		var half : float = px(SIZE_PX) / 2.0
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0).grow(px(1.5)), Palette.VOID)
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), colour)
		if generator.scope == Generator.Scope.WHOLE_MAP:
			draw_arc(at, half * 1.9, 0.0, TAU, 24, colour, px(1.5))
