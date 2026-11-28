class_name RelicRoomsLayer
extends MapLayer

##The treasure rooms that held a relic when the match started, outlined in bright yellow. The list is set once (`rooms`, see MapScreen.mark_relic_rooms)
##and is not changed when a relic is carried off, so the outline still shows where the relics were.

const COLOUR : Color = Color("#ffe14d")

@export var width_px : float = 2.5 ## the outline's width on screen

var rooms : Array[String] = [] : set = set_rooms ## the room ids to outline


func set_rooms(value : Array[String]) -> void:
	rooms = value
	queue_redraw()


func _draw() -> void:
	if facility() == null:
		return
	var shown : Array[String] = rooms.duplicate()
	for id : String in facility().rooms_of_kind("item"): #(every treasure room, whether or not a relic started in it)
		if not shown.has(id):
			shown.append(id)
	var spots : Node = facility().get_node_or_null("ArtifactLocations") #(and every room with a place for a relic, whatever its kind)
	if spots != null:
		for spot : Node in spots.get_children():
			var id : String = facility().room_at((spot as Node2D).position)
			if id != "" and not shown.has(id):
				shown.append(id)
	for id : String in shown:
		for rect : Rect2 in room_rects(id):
			draw_rect(rect, Color(COLOUR, 0.22))
			draw_rect(rect, COLOUR, false, px(width_px))


func icon_label(world : Vector2) -> String:
	if facility() == null:
		return ""
	var id : String = facility().room_at(world)
	if id == "":
		return ""
	if rooms.has(id) or facility().rooms_of_kind("item").has(id):
		return "Relic room"
	return ""


##Its labels name whole rooms (see MapLayer.labels_areas).
func labels_areas() -> bool:
	return true
