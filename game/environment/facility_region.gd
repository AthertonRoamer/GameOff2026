@tool
class_name FacilityRegion
extends Control

##A power region of the facility: a group of rooms that share their region generators (see PowerGrid). Placed under the map's Regions node; the node
##name is the region id. Which rooms belong to it is set on the rooms themselves (FacilityRoom.region), so a room is never in two regions.
##
##In the editor:
##  - Select a region (in the scene tree, or click its name badge in the 2D view) and its rooms light up in its colour, the rest of the map dims.
##  - While it is selected, click a room in the 2D view to add it to the region, click it again to take it out (shift-click only adds). Ctrl+Z undoes.
##    (The facility editor plugin, addons/facility_editor, does this.)
##  - Or select several rooms and set their `region` in the inspector, all at once.
##The node is its name badge, which the map moves to the middle of the region's biggest room whenever it rebuilds, so there is no need to drag it.
##In the game it draws nothing and ignores the mouse.

const BADGE_SIZE : Vector2 = Vector2(220.0, 44.0)

@export var display_name : String = "" : set = _set_display_name
@export var colour : Color = Color("#f2b544") : set = _set_colour
@export_tool_button("Select its rooms") var select_rooms_button : Callable = select_rooms_in_editor


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BADGE_SIZE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = BADGE_SIZE
	queue_redraw()


func region_id() -> StringName:
	return StringName(name)


func label() -> String:
	return display_name if display_name != "" else String(name).capitalize()


##The rooms of the map that say they are in this region.
func member_rooms() -> Array[FacilityRoom]:
	var result : Array[FacilityRoom] = []
	var map : FacilityMap = facility_map()
	if map == null:
		return result
	for room : FacilityRoom in map.room_nodes():
		if room.region == region_id():
			result.append(room)
	return result


##Editor: selects this region's rooms in the scene tree.
func select_rooms_in_editor() -> void:
	if not Engine.is_editor_hint():
		return
	var selection : Object = Engine.get_singleton("EditorInterface").get_selection() #(by name: EditorInterface does not exist in an exported game)
	selection.clear()
	for room : FacilityRoom in member_rooms():
		selection.add_node(room)


##Called by the map when it builds in the editor: puts the badge in the middle of the region's rooms (a point in the map's space).
func set_badge_point(map_point : Vector2) -> void:
	var map : FacilityMap = facility_map()
	var holder : CanvasItem = get_parent() as CanvasItem
	if map == null or holder == null:
		return
	var at : Vector2 = (holder.get_global_transform().affine_inverse() * map.get_global_transform() * map_point - BADGE_SIZE / 2.0).round()
	if not position.is_equal_approx(at):
		position = at
	if not size.is_equal_approx(BADGE_SIZE):
		size = BADGE_SIZE


func _get_configuration_warnings() -> PackedStringArray:
	if Engine.is_editor_hint() and is_inside_tree() and member_rooms().is_empty():
		return PackedStringArray(["This region has no rooms. Select it and click rooms in the 2D view, or set `region` on the rooms."])
	return PackedStringArray()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect : Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(Palette.VOID, 0.85))
	draw_rect(rect, colour, false, 3.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(8.0, size.y)), colour)
	draw_string(ThemeDB.fallback_font, Vector2(16.0, 29.0), "REGION  " + label().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, 18, colour)


func _set_display_name(value : String) -> void:
	display_name = value
	queue_redraw()
	_redraw_rooms()


func _set_colour(value : Color) -> void:
	colour = value
	queue_redraw()
	_redraw_rooms()


func _redraw_rooms() -> void:
	if is_inside_tree():
		for room : FacilityRoom in member_rooms():
			room.redraw()


func facility_map() -> FacilityMap:
	var node : Node = get_parent()
	while node != null and not node is FacilityMap:
		node = node.get_parent()
	return node as FacilityMap


func _notification(what : int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_PARENTED:
		update_configuration_warnings()
