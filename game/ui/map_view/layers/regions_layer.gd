class_name RegionsLayer
extends MapLayer

##The power regions: each region's rooms tinted in its colour, its outline (round its rooms and the walls between them, see FacilityMap.region_outline),
##and its name in the middle of its biggest room. With `show_power` (and a `grid`), the name has the power still free there under it, out of what the
##region could have, in points per second. Put it over the RoomsLayer.

const LABEL_RISE_PX : float = 30.0 #the region's tag sits this far (on screen) above the middle of its biggest room, clear of the room's name

@export var show_power : bool = true ## the power numbers under the names (the map screen turns them on for guards only)
@export var show_names : bool = true
@export_range(0.0, 1.0, 0.01) var tint : float = 0.12 ## how strongly the rooms are tinted in their region's colour

var grid : PowerGrid


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null or map.regions.is_empty():
		return
	for id : String in map.regions:
		var colour : Color = map.region_colour(id)
		if tint > 0.0:
			for room_id : String in map.regions[id]["rooms"]:
				for rect : Rect2 in map.room_rects_px(room_id):
					draw_rect(rect, Color(colour, tint))
		var outline : PackedVector2Array = map.region_outline(id)
		if not outline.is_empty():
			draw_multiline(outline, Color(Palette.VOID, 0.8), px(5.0))
			draw_multiline(outline, colour, px(2.5))
	if not show_names:
		return
	for id : String in map.regions:
		var centre : Vector2 = map.regions[id]["centre"] - Vector2(0.0, px(LABEL_RISE_PX)) #above the room's own name, which is in the middle of the room
		var colour : Color = map.region_colour(id)
		var powered : bool = show_power and grid != null
		var tag : Vector2 = Vector2(px(150.0), px(38.0 if powered else 22.0))
		draw_rect(Rect2(centre - tag / 2.0, tag), Color(Palette.VOID, 0.85))
		draw_rect(Rect2(centre - tag / 2.0, tag), colour, false, px(1.5))
		var name_at : Vector2 = centre - Vector2(0.0, px(9.0)) if powered else centre
		draw_label(name_at, String(map.regions[id]["name"]).to_upper(), 13, colour, 220.0)
		if powered:
			var free : float = grid.available(id)
			var short : bool = free + 0.0001 < grid.settings.cheapest_cost()
			draw_label(centre + Vector2(0.0, px(9.0)), "%d / %d pts/s" % [floori(free), roundi(grid.capacity(id))], 12, Palette.ALARM if short else Palette.TEXT, 220.0)
