@tool
class_name FacilityRoom
extends Node2D

##One room of the facility, placed in the editor under the map's Rooms node. A room is its node name (the id other code uses, like "door_control"),
##a few settings, and its floor: one or more FacilityRoomRect children, which you resize in the 2D view by dragging their handles (a corridor that goes
##round the building is one room with several rectangles). Rectangles and the room itself snap to the map's 0.25 m grid (11 px) by themselves.
##To add a room: add a FacilityRoom under Rooms, add a FacilityRoomRect under it, drag it to size, set `kind` (and `function` if it has a console).
##The map reads the rooms and the doors and builds the floor, the walls (every empty cell touching a floor cell, so rooms need a one cell gap
##between them), the soft shadows and the minimap from them, so resizing a room never touches any art.
##A room of kind Exit is an exit zone, not a room: see is_exit().
##`region` is the power region it belongs to (a FacilityRegion under the map's Regions node, see PowerGrid): a dropdown of the map's regions. Select several
##rooms to set it on all of them at once, or select the region and click rooms in the 2D view (addons/facility_editor).
##`spawns_items` makes it a room where an item can be found lying along a wall when the match starts, with an `item_chance` percent chance, picked from
##`item_pool` (or, when that is empty, the map's list) (see
##FacilityItemRooms: select the map's ItemRooms node and click rooms in the 2D view to set it).

enum Kind { CORRIDOR, UTILITY, ITEM, OFFICE, EXTERIOR_ROOM, OUTDOOR, EXIT }
enum Function { NONE, CAMERAS, DOORS, LIGHTS, GENERATOR, TURRETS, POWER }

const KIND_NAMES : Array[String] = ["corridor", "utility", "item", "office", "exterior_room", "outdoor", "exit"]
const FUNCTION_NAMES : Array[String] = ["", "cameras", "doors", "lights", "generator", "turrets", "power"]
const KIND_COLOURS : Array[Color] = [Color("#8aa0b8"), Color("#6fd3e8"), Color("#c9a0ff"), Color("#9ad1a0"), Color("#f2b544"), Color("#7a7f88"), Color("#4ade80")]
const TILE : int = FacilityTileSet.TILE

@export var display_name : String = "" : set = _set_display_name
@export var kind : Kind = Kind.OFFICE : set = _set_kind
@export var function : Function = Function.NONE #what the room's console does, if it has one
@export var region : StringName = &"" : set = _set_region #the power region it is in (a FacilityRegion's node name), empty for none
@export_group("Item spawns")
@export var spawns_items : bool = false : set = _set_spawns_items ## an item may be found here when the match starts (see FacilityItemRooms)
@export_range(0, 100, 1, "suffix:%") var item_chance : int = 30 : set = _set_item_chance ## how likely it is that this room has an item, each match
@export var item_pool : Array[Item] = [] : set = _set_item_pool ## what can turn up in this room. Empty: the map's list (ItemRooms.items). List one twice to make it twice as likely
@export_group("")

var clash_with : String = "" #set by the map while two rooms share floor, so the editor can say so
var spawn_kinds : Array = [] #SpawnRoomMarker.Kind of every spawn marker standing in this room, set by the map in the editor (shown as badges)


func _ready() -> void:
	_redraw_rects()


func room_id() -> String:
	return String(name)


##The FacilityRegion this room is in, or null (none set, or the name matches no region of the map).
func region_node() -> FacilityRegion:
	var map : Node = get_parent().get_parent() if get_parent() != null else null
	if region == &"" or map == null:
		return null
	return map.get_node_or_null(NodePath("Regions/" + String(region))) as FacilityRegion


func redraw() -> void:
	_redraw_rects()


##An exit zone is an area, not a room: the map paints no floor or wall on it. It goes outside a room's wall, with the same one cell gap as between
##two rooms, and a door in that wall leads into it. It is ringed by invisible walls (collision only), so players can step into it but not wander
##off into the void. An attacker who stands in one carrying the target artifact wins the match, see ArtifactEscape.
func is_exit() -> bool:
	return kind == Kind.EXIT


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


func set_spawn_kinds(kinds : Array) -> void:
	if kinds != spawn_kinds:
		spawn_kinds = kinds.duplicate()
		_redraw_rects()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	if rects().is_empty():
		warnings.append("This room has no floor. Add a FacilityRoomRect child and drag it to size.")
	if clash_with != "" and is_exit():
		warnings.append("This exit is in or against %s. Leave a one cell wall between them and put a door in it." % clash_with)
	elif clash_with != "":
		warnings.append("This room overlaps %s. Rooms need a one cell gap between them." % clash_with)
	if region != &"" and is_inside_tree() and region_node() == null:
		warnings.append("This room's region \"%s\" is not one of the map's regions (under Regions)." % region)
	return warnings


func _set_display_name(value : String) -> void:
	display_name = value
	_redraw_rects()


func _set_region(value : StringName) -> void:
	region = value
	_redraw_rects()
	if is_inside_tree():
		update_configuration_warnings()


##`region` is a dropdown of the map's regions (a name can still be typed; one that matches no region gets a warning).
func _validate_property(property : Dictionary) -> void:
	if property["name"] != "region":
		return
	var map : Node = get_parent().get_parent() if get_parent() != null else null
	var regions_node : Node = map.get_node_or_null("Regions") if map != null else null
	var names : PackedStringArray = [""]
	if regions_node != null:
		for child : Node in regions_node.get_children():
			if child is FacilityRegion:
				names.append(String(child.name))
	property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
	property["hint_string"] = ",".join(names)


func _set_spawns_items(value : bool) -> void:
	spawns_items = value
	_redraw_rects()
	_update_item_rooms_badge()


func _set_item_chance(value : int) -> void:
	item_chance = clampi(value, 0, 100)
	_redraw_rects()


func _set_item_pool(value : Array[Item]) -> void:
	item_pool = value
	_redraw_rects()


## Whether this room has a list of items of its own (otherwise the map's list is used).
func has_own_pool() -> bool:
	return item_pool.any(func(item : Item) -> bool: return item != null)


## The chance this room has an item each match, 0 to 1 (0 when it is not an item room).
func item_probability() -> float:
	return item_chance / 100.0 if spawns_items and not is_exit() else 0.0


func _update_item_rooms_badge() -> void:
	var map : Node = get_parent().get_parent() if get_parent() != null else null
	var node : Node = map.get_node_or_null("ItemRooms") if map != null and map.is_inside_tree() else null
	if node is FacilityItemRooms:
		node.queue_redraw()
		node.update_configuration_warnings()


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
