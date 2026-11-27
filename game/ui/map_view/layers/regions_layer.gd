class_name RegionsLayer
extends MapLayer

##The power regions: each region's rooms tinted in its colour, its outline (round its rooms and the walls between them, see FacilityMap.region_outline),
##and its name in the middle of its biggest room (drawn by a RegionNamesLayer over
##everything else, where the map has one). With `show_power` (and a `grid`), the name has the power still free there under it, out of what the
##region could have, in points per second. Put it over the RoomsLayer.

const LABEL_RISE_PX : float = 30.0 #the region's tag sits this far (on screen) above the middle of its biggest room, clear of the room's name

@export var show_power : bool = true ## the power numbers under the names (the map screen turns them on for guards only)
@export var show_names : bool = true
@export var power_for_everyone : bool = false ## the door console: whoever is using it sees the power (MapIntel leaves show_power alone)
@export_range(0.0, 1.0, 0.01) var tint : float = 0.12 ## how strongly the rooms are tinted in their region's colour

var grid : PowerGrid
var names_on_top : bool = false #a RegionNamesLayer draws the names, over the other icons


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null or map.regions.is_empty():
		return
	var thin : float = clampf(view.zoom / 0.2, 0.45, 1.0) #thinner lines far out
	for id : String in map.regions:
		var colour : Color = map.region_colour(id)
		if tint > 0.0:
			for room_id : String in map.regions[id]["rooms"]:
				for rect : Rect2 in map.room_rects_px(room_id):
					draw_rect(rect, Color(colour, tint))
		var outline : PackedVector2Array = map.region_outline(id)
		if not outline.is_empty():
			draw_multiline(outline, Color(Palette.VOID, 0.8), px(5.0 * thin))
			draw_multiline(outline, colour, px(2.5 * thin))
	if not names_on_top:
		draw_names(self)


## Where each region's name tag goes (world rectangles): above the middle of its biggest room, moved down past any it would cover.
func name_tags(canvas : MapLayer) -> Dictionary:
	var map : FacilityMap = facility()
	var tags : Dictionary = {}
	if map == null or not show_names:
		return tags
	var font : Font = view.get_theme_default_font()
	var powered : bool = show_power and grid != null
	var wanted : Array = []
	for id : String in map.regions:
		var width : float = font.get_string_size(String(map.regions[id]["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if powered:
			width = maxf(width, font.get_string_size(_power_text(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
		var tag : Vector2 = Vector2(canvas.px(width + 18.0), canvas.px(38.0 if powered else 22.0))
		var centre : Vector2 = map.regions[id]["centre"] - Vector2(0.0, canvas.px(LABEL_RISE_PX)) #above the room's own name, which is in the middle of the room
		var rect : Rect2 = Rect2(centre - tag / 2.0, tag)
		var low : Vector2 = view.screen_to_world(Vector2.ONE * 2.0)
		var high : Vector2 = view.screen_to_world(view.size - Vector2.ONE * 2.0) - tag
		if Rect2(low, high + tag - low).has_point(map.regions[id]["centre"]) and high.x > low.x and high.y > low.y:
			rect.position = rect.position.clamp(low, high) #a zone in view keeps its whole name in view
		wanted.append([id, rect])
	wanted.sort_custom(func(a : Array, b : Array) -> bool: return (a[1] as Rect2).position.y < (b[1] as Rect2).position.y)
	for entry : Array in wanted:
		var rect : Rect2 = entry[1]
		var moved : bool = true
		while moved:
			moved = false
			for other : Rect2 in tags.values():
				if rect.intersects(other):
					rect.position.y = other.end.y + canvas.px(2.0)
					moved = true
		tags[entry[0]] = rect
	return tags


func draw_names(canvas : MapLayer) -> void:
	var map : FacilityMap = facility()
	if map == null:
		return
	var tags : Dictionary = name_tags(canvas)
	var powered : bool = show_power and grid != null
	for id : String in tags:
		var rect : Rect2 = tags[id]
		var colour : Color = map.region_colour(id)
		var centre : Vector2 = rect.get_center()
		canvas.draw_rect(rect, Color(Palette.VOID, 0.92))
		canvas.draw_rect(rect, colour, false, canvas.px(1.5))
		var name_at : Vector2 = centre - Vector2(0.0, canvas.px(9.0)) if powered else centre
		canvas.draw_label(name_at, String(map.regions[id]["name"]).to_upper(), 13, colour, 220.0)
		if powered:
			var short : bool = grid.available(id) + 0.0001 < grid.settings.cheapest_cost()
			canvas.draw_label(centre + Vector2(0.0, canvas.px(9.0)), _power_text(id), 12, Palette.ALARM if short else Palette.TEXT, 220.0)


func _power_text(id : String) -> String:
	return "%d / %d pts/s" % [floori(grid.available(id)), roundi(grid.capacity(id))]
