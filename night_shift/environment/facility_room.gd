@tool
class_name FacilityRoom
extends Area2D

##One room of the facility, placed in the editor under the map's Rooms node. A room is its node name (the id other code uses, like "door_control")
##plus a few settings, and its floor: one or more CollisionShape2D children with a RectangleShape2D, which you drag to the size you want (a corridor
##that goes round the building is one room with several rectangles). Positions and sizes snap to the map's 0.25 m grid (11 px) by themselves.
##The map reads the rooms and the doors and builds the floor, the walls (every empty cell touching a floor cell, so rooms need a one cell gap
##between them), the soft shadows and the minimap from them. Nothing here is physics: the Area2D only gives the shapes a home with editor handles.

enum Kind { CORRIDOR, UTILITY, ITEM, OFFICE, EXTERIOR_ROOM, OUTDOOR }
enum Function { NONE, CAMERAS, DOORS, LIGHTS, GENERATOR, TURRETS, POWER }

const KIND_NAMES : Array[String] = ["corridor", "utility", "item", "office", "exterior_room", "outdoor"]
const FUNCTION_NAMES : Array[String] = ["", "cameras", "doors", "lights", "generator", "turrets", "power"]
const KIND_COLOURS : Array[Color] = [Color("#8aa0b8"), Color("#6fd3e8"), Color("#c9a0ff"), Color("#9ad1a0"), Color("#f2b544"), Color("#7a7f88")]

@export var display_name : String = "" : set = _set_display_name
@export var kind : Kind = Kind.OFFICE : set = _set_kind
@export var function : Function = Function.NONE : set = _set_function #what the room's console does, if it has one

const TILE : int = FacilityTileSet.TILE


func _init() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false


func _ready() -> void:
	queue_redraw()


func room_id() -> String:
	return String(name)


func kind_name() -> String:
	return KIND_NAMES[kind]


func function_name() -> String:
	return FUNCTION_NAMES[function]


##The room's rectangles in cells (x0, y0, size), in the space of `space` (the map), from its rectangle shapes.
func cell_rects(space : Node2D) -> Array[Rect2i]:
	var result : Array[Rect2i] = []
	for child : Node in get_children():
		var shape_node : CollisionShape2D = child as CollisionShape2D
		if shape_node == null or not shape_node.shape is RectangleShape2D or shape_node.disabled:
			continue
		var size : Vector2 = (shape_node.shape as RectangleShape2D).size
		var top_left : Vector2 = space.to_local(shape_node.global_position) - size / 2.0
		result.append(Rect2i(roundi(top_left.x / TILE), roundi(top_left.y / TILE), maxi(1, roundi(size.x / TILE)), maxi(1, roundi(size.y / TILE))))
	return result


##Moves and sizes the rectangles onto the 11 px grid. Only writes what is off the grid, so dragging a handle is not fought over.
func snap_to_grid() -> void:
	position = (position / TILE).round() * TILE
	for child : Node in get_children():
		var shape_node : CollisionShape2D = child as CollisionShape2D
		if shape_node == null or not shape_node.shape is RectangleShape2D:
			continue
		var shape : RectangleShape2D = shape_node.shape
		var size : Vector2 = (shape.size / TILE).round().max(Vector2.ONE) * TILE
		var top_left : Vector2 = ((shape_node.position - size / 2.0) / TILE).round() * TILE
		if not size.is_equal_approx(shape.size):
			shape.size = size
		if not shape_node.position.is_equal_approx(top_left + size / 2.0):
			shape_node.position = top_left + size / 2.0


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var label : String = display_name if display_name != "" else String(name)
	for child : Node in get_children():
		var shape_node : CollisionShape2D = child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var rect : Rect2 = Rect2(shape_node.position - (shape_node.shape as RectangleShape2D).size / 2.0, (shape_node.shape as RectangleShape2D).size)
			draw_rect(rect, Color(KIND_COLOURS[kind], 0.18))
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(8.0, 20.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(KIND_COLOURS[kind], 0.9))
			return #the name is written once, in the first rectangle


func _set_display_name(value : String) -> void:
	display_name = value
	queue_redraw()


func _set_kind(value : Kind) -> void:
	kind = value
	queue_redraw()


func _set_function(value : Function) -> void:
	function = value
	queue_redraw()