class_name GeneratorsLayer
extends MapLayer

##The generators, as small squares coloured by state: grey off, amber running, red shot down. A whole-map generator has a ring round it. A portable generator
##put down on the floor (PowerGrid.portables) is a smaller amber square with a bolt-white dot. Needs `grid`.

@export var size_px : float = 11.0 ## a generator's square on screen
@export var portable_size_px : float = 8.0

var grid : PowerGrid


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null or grid == null:
		return
	for generator in grid.generators:
		if not is_instance_valid(generator):
			continue
		var at : Vector2 = map.to_local(generator.global_position)
		var colour : Color = Palette.MUTED
		match generator.state:
			Generator.State.RUNNING: colour = Palette.BACKUP
			Generator.State.DESTROYED: colour = Palette.ALARM
		var half : float = px(size_px) / 2.0
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0).grow(px(1.5)), Palette.VOID)
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), colour)
		if generator.scope == Generator.Scope.WHOLE_MAP:
			draw_arc(at, half * 1.9, 0.0, TAU, 24, colour, px(1.5))
	for key : String in grid.portables:
		var at : Vector2 = map.to_local(grid.portables[key]["at"])
		var half : float = px(portable_size_px) / 2.0
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0).grow(px(1.5)), Palette.VOID)
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), Palette.BACKUP)
		draw_circle(at, half * 0.4, Palette.FLASH)


func icon_label(world : Vector2) -> String:
	var map : FacilityMap = facility()
	if map == null or grid == null:
		return ""
	for key : String in grid.portables:
		if map.to_local(grid.portables[key]["at"]).distance_to(world) <= px(portable_size_px / 2.0 + 4.0):
			return "Portable generator: running (%s)" % _region_name(String(grid.portables[key]["region"]))
	for generator in grid.generators:
		if not is_instance_valid(generator) or map.to_local(generator.global_position).distance_to(world) > px(size_px / 2.0 + 4.0):
			continue
		var state : String = ["off", "running", "shot down"][generator.state]
		var powers : String = "whole facility" if generator.scope == Generator.Scope.WHOLE_MAP else _region_name(generator.region)
		return "Generator: %s (%s)" % [state, powers]
	return ""


func _region_name(region : String) -> String:
	if region == "":
		return "no region"
	return grid.facility.region_name(region) if grid.facility != null else region
