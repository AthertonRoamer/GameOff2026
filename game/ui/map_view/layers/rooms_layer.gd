class_name RoomsLayer
extends MapLayer

##The facility's rooms: filled by kind, outlined, with the names of the rooms big enough to hold one. The base of every map.

const ROOM_FILL : Dictionary = {"corridor": Palette.FLOOR, "utility": Palette.WALL_TOP, "item": Palette.WALL, "office": Palette.LINE, "exterior_room": Palette.DEEP, "outdoor": Palette.SHADOW}
const NAME_MIN_WIDTH_PX : float = 70.0 #a room narrower than this on screen shows no name

@export var highlight_function : String = "" #rooms whose console works this (like "doors") get their name in the accent colour
@export var show_names : bool = true
@export var names_from_zoom : float = 0.18 ## no room names further out than this (the zone names are enough)


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null:
		return
	for id : String in map.rooms:
		var room : Dictionary = map.rooms[id]
		for rect : Rect2 in map.room_rects_px(id):
			draw_rect(rect, ROOM_FILL.get(room["kind"], Palette.LINE))
			draw_rect(rect, Palette.METAL if room["kind"] != "outdoor" else Palette.LINE, false, px(1.5))
	if not show_names or view.zoom < names_from_zoom:
		return
	for id : String in map.rooms:
		var room : Dictionary = map.rooms[id]
		if room["kind"] == "corridor" or room["kind"] == "outdoor":
			continue
		var rect : Rect2 = map.room_rects_px(id)[0]
		var width_px : float = rect.size.x * view.zoom
		if width_px < NAME_MIN_WIDTH_PX or view.get_theme_default_font().get_string_size(String(room["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x > width_px - 8.0:
			continue #(a name that would be cut off is left out)
		var colour : Color = Palette.BACKUP if highlight_function != "" and room["function"] == highlight_function else Palette.MUTED
		draw_label(rect.get_center(), String(room["name"]).to_upper(), 10, colour, width_px - 8.0)
