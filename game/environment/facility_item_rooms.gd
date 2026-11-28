@tool
class_name FacilityItemRooms
extends Control

##Where items can be found lying about. Placed on the map as its ItemRooms node (one per map). It holds the list of items that can turn up; which rooms they can
##turn up in is set on the rooms themselves (FacilityRoom.spawns_items, and FacilityRoom.item_chance: the percent chance the room has one, 30 by default).
##When the match loads, the lobby gives each of those rooms its roll: on a hit, one item picked at random from `items` is put on the floor along one of the
##room's walls, clear of furniture, consoles and doorways (see ItemSpawner). Nothing turns up later in the match.
##
##In the editor:
##  - Select this node (in the scene tree, or click its badge in the 2D view) and the item rooms light up with their chance, the rest of the map dims.
##  - While it is selected, click a room in the 2D view to make it an item room, click it again to stop (shift-click only adds). Ctrl+Z undoes.
##    (The facility editor plugin, addons/facility_editor, does this.)
##  - Set a room's chance in the inspector (select several rooms to set them all at once).
##In the game it draws nothing and ignores the mouse.

const BADGE_SIZE : Vector2 = Vector2(220.0, 44.0)
const COLOUR : Color = Color("#f59e0b")

@export var items : Array[Item] = [] ## what can turn up: one of these, picked at random, in a room that rolls a hit. List one twice to make it twice as likely
@export var colour : Color = COLOUR : set = _set_colour
@export_tool_button("Select its rooms") var select_rooms_button : Callable = select_rooms_in_editor


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BADGE_SIZE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = BADGE_SIZE
	queue_redraw()


##The rooms of the map where items can turn up.
func member_rooms() -> Array[FacilityRoom]:
	var result : Array[FacilityRoom] = []
	var map : FacilityMap = facility_map()
	if map == null:
		return result
	for room : FacilityRoom in map.room_nodes():
		if room.spawns_items and not room.is_exit():
			result.append(room)
	return result


##Editor: selects the item rooms in the scene tree.
func select_rooms_in_editor() -> void:
	if not Engine.is_editor_hint():
		return
	var selection : Object = Engine.get_singleton("EditorInterface").get_selection() #(by name: EditorInterface does not exist in an exported game)
	selection.clear()
	for room : FacilityRoom in member_rooms():
		selection.add_node(room)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	if not Engine.is_editor_hint() or not is_inside_tree():
		return warnings
	if items.is_empty() or items.all(func(item : Item) -> bool: return item == null):
		warnings.append("No items to spawn. Add some to `items`.")
	if member_rooms().is_empty():
		warnings.append("No room can have items. Select this node and click rooms in the 2D view, or tick `spawns_items` on the rooms.")
	return warnings


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect : Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(Palette.VOID, 0.85))
	draw_rect(rect, colour, false, 3.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(8.0, size.y)), colour)
	draw_string(ThemeDB.fallback_font, Vector2(16.0, 29.0), "ITEM ROOMS  %d" % member_rooms().size(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, 18, colour)


func _set_colour(value : Color) -> void:
	colour = value
	queue_redraw()
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
