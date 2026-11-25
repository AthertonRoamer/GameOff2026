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
	for id : String in rooms:
		for rect : Rect2 in room_rects(id):
			draw_rect(rect, COLOUR, false, px(width_px))
