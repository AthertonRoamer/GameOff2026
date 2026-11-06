@tool
class_name FacilityRoom
extends Node2D

##One room of the facility, placed in the editor under the map's Rooms node. A room is its node name (the id other code uses, like "door_control"),
##a few settings, and its floor: one or more FacilityRoomRect children, which you resize in the 2D view by dragging their handles (a corridor that goes
##round the building is one room with several rectangles). Rectangles and the room itself snap to the map's 0.25 m grid (11 px) by themselves.
##To add a room: add a FacilityRoom under Rooms, add a FacilityRoomRect under it, drag it to size, set `kind` (and `function` if it has a console).
##The map reads the rooms and the doors and builds the floor, the walls (every empty cell touching a floor cell, so rooms need a one cell gap
##between them), the soft shadows and the minimap from them, so resizing a room never touches any art.

enum Kind { CORRIDOR, UTILITY, ITEM, OFFICE, EXTERIOR_ROOM, OUTDOOR }
enum Function { NONE, CAMERAS, DOORS, LIGHTS, GENERATOR, TURRETS, POWER }

const KIND_NAMES : Array[String] = ["corridor", "utility", "item", "office", "exterior_room", "outdoor"]
const FUNCTION_NAMES : Array[String] = ["", "cameras", "doors", "lights", "generator", "turrets", "power"]
const KIND_COLOURS : Array[Color] = [Color("#8aa0b8"), Color("#6fd3e8"), Color("#c9a0ff"), Color("#9ad1a0"), Color("#f2b544"), Color("#7a7f88")]
const TILE : int = FacilityTileSet.TILE

@export var display_name : String = "" : set = _set_display_name
@export var kind : Kind = Kind.OFFICE : set = _set_kind
@export var function : Function = Function.NONE #what the room's console does, if it has one

var clash_with : String = "" #set by the map while two rooms share floor, so the editor can say so


func _ready() -> void:
	_redraw_rects()


func room_id() -> String:
	return String(name)


func kind_name() -> String:
	return KIND_NAMES[kind]


func function_name() -> String:
	return FUNCTION_NAMES[function]


func kind_colour() -> Color:
	return KIND_COLOURS[kind]


func rects() -> Array[FacilityRoomRect]:
	var result : Array[FacilityRoomRect] = []
	for child : Node in get_children():
		if child is FacilityRoomRect:
			result.append(child)
	return result


##The room's rectangles in cells, counted in the space of `space` (the map).
func cell_rects(space : Node2D) -> Array[Rect2i]:
	var result : Array[Rect2i] = []
	for rect : FacilityRoomRect in rects():
		result.append(rect.cell_rect(space))
	return result


func snap_to_grid() -> void:
	position = (position / TILE).round() * TILE
	for rect : FacilityRoomRect in rects():
		rect.snap_to_grid()


func set_clash(other : String) -> void:
	if other != clash_with:
		clash_with = other
		update_configuration_warnings()
		_redraw_rects()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	if rects().is_empty():
		warnings.append("This room has no floor. Add a FacilityRoomRect child and drag it to size.")
	if clash_with != "":
		warnings.append("This room overlaps %s. Rooms need a one cell gap between them." % clash_with)
	return warnings


func _set_display_name(value : String) -> void:
	display_name = value
	_redraw_rects()


func _set_kind(value : Kind) -> void:
	kind = value
	_redraw_rects()


func _redraw_rects() -> void:
	for child : Node in get_children():
		if child is FacilityRoomRect:
			(child as FacilityRoomRect).queue_redraw()


func _notification(what : int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		update_configuration_warnings()