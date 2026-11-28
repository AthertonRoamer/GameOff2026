@tool
extends EditorPlugin

## Editor tools for the facility map (game/environment/facility_map.gd).
##
## Power regions: select a FacilityRegion (in the scene tree, or click its name badge in the 2D view) and
##   - its rooms are filled in its colour and outlined, and every other room is dimmed;
##   - a click on a room in the 2D view adds the room to the region, or takes it out if it is already in (shift-click only adds, never takes out).
##     A room is in one region at a time, so clicking a room of another region moves it here. Ctrl+Z undoes it like any edit;
##   - a click with Ctrl or Alt held, or anywhere off the rooms, goes to the editor as usual (to select something else).
## Which rooms belong to a region is stored on the rooms (FacilityRoom.region), so this is only a quicker way of setting that.
##
## Item rooms: select the map's ItemRooms node (a FacilityItemRooms) and the rooms where items can be found light up, each with its chance; the same
##   clicks make a room an item room or stop it being one (FacilityRoom.spawns_items). A room's chance is set in the inspector (30% to start with).

const DIM : Color = Color(0.0, 0.0, 0.0, 0.45)

var _target : Control #the FacilityRegion or FacilityItemRooms being edited
var _hover_room : FacilityRoom
var _hint : Label


func _enter_tree() -> void:
	_hint = Label.new()
	_hint.visible = false
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _hint)


func _exit_tree() -> void:
	_disconnect_map()
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _hint)
	_hint.queue_free()


func _handles(object : Object) -> bool:
	return object is FacilityRegion or object is FacilityItemRooms


func _edit(object : Object) -> void:
	_disconnect_map()
	_target = object as Control
	_hover_room = null
	var map : FacilityMap = _map()
	if map != null and not map.built.is_connected(update_overlays):
		map.built.connect(update_overlays) #the outline is worked out again when the map rebuilds after a change
	_update_hint()
	update_overlays()


func _make_visible(visible : bool) -> void:
	if not visible:
		_disconnect_map()
		_target = null
		_hover_room = null
	_update_hint()
	update_overlays()


func _items_mode() -> bool:
	return _target is FacilityItemRooms


## Is this room one of the edited region's, or an item room?
func _is_member(room : FacilityRoom) -> bool:
	if _items_mode():
		return room.spawns_items
	return room.region == (_target as FacilityRegion).region_id()


func _colour() -> Color:
	return (_target as FacilityItemRooms).colour if _items_mode() else (_target as FacilityRegion).colour


func _label() -> String:
	return "the item rooms" if _items_mode() else (_target as FacilityRegion).label()


func _forward_canvas_gui_input(event : InputEvent) -> bool:
	var map : FacilityMap = _map()
	if map == null:
		return false
	if event is InputEventMouseMotion:
		var hover : FacilityRoom = _room_under((event as InputEventMouseMotion).position, map)
		if hover != _hover_room:
			_hover_room = hover
			update_overlays()
		return false
	if not (event is InputEventMouseButton):
		return false
	var button : InputEventMouseButton = event
	if button.button_index != MOUSE_BUTTON_LEFT or not button.pressed or button.ctrl_pressed or button.alt_pressed or button.meta_pressed:
		return false
	if Rect2(Vector2.ZERO, _target.size).has_point((_target.get_viewport_transform() * _target.get_global_transform()).affine_inverse() * button.position):
		return false #the badge: the editor selects (or drags) it as usual
	var room : FacilityRoom = _room_under(button.position, map)
	if room == null:
		return false
	var mine : bool = _is_member(room)
	if mine and button.shift_pressed:
		return true #shift only adds: nothing to do, but the click is still ours (it would select the room)
	var undo : EditorUndoRedoManager = get_undo_redo()
	if _items_mode():
		undo.create_action("%s room %s %s the item rooms" % ["Remove" if mine else "Add", room.name, "from" if mine else "to"], UndoRedo.MERGE_DISABLE, room)
		undo.add_do_property(room, &"spawns_items", not mine)
		undo.add_undo_property(room, &"spawns_items", room.spawns_items)
	else:
		var region : FacilityRegion = _target
		undo.create_action("%s room %s %s region %s" % ["Remove" if mine else "Add", room.name, "from" if mine else "to", region.name], UndoRedo.MERGE_DISABLE, room)
		undo.add_do_property(room, &"region", &"" if mine else region.region_id())
		undo.add_undo_property(room, &"region", room.region)
	undo.add_do_method(self, &"update_overlays")
	undo.add_undo_method(self, &"update_overlays")
	undo.commit_action()
	return true


func _forward_canvas_draw_over_viewport(overlay : Control) -> void:
	var map : FacilityMap = _map()
	if map == null:
		return
	var to_screen : Transform2D = (map.get_viewport_transform() * map.get_global_transform())
	var colour : Color = _colour()
	var font : Font = overlay.get_theme_default_font()
	for room : FacilityRoom in map.room_nodes():
		if _items_mode() and room.is_exit():
			continue
		var mine : bool = _is_member(room)
		var cell_rects : Array[Rect2i] = room.cell_rects(map)
		for cells : Rect2i in cell_rects:
			var rect : Rect2 = _screen_rect(to_screen, cells)
			if mine:
				overlay.draw_rect(rect, Color(colour, 0.32 if not _items_mode() else 0.12 + 0.4 * room.item_chance / 100.0)) #(item rooms: the likelier, the brighter)
				overlay.draw_rect(rect, colour, false, 2.0)
			else:
				overlay.draw_rect(rect, DIM)
		if _items_mode() and mine and not cell_rects.is_empty(): #its chance, big, in the middle of its first rectangle
			var middle : Vector2 = _screen_rect(to_screen, cell_rects[0]).get_center()
			var text : String = ("%d%%" % room.item_chance) + ("  own list" if room.has_own_pool() else "")
			var width : float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			overlay.draw_rect(Rect2(middle + Vector2(-width / 2.0 - 6.0, -20.0), Vector2(width + 12.0, 28.0)), Color(0.0, 0.0, 0.0, 0.7))
			overlay.draw_string(font, middle + Vector2(-width / 2.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, colour)
	if not _items_mode():
		var outline : PackedVector2Array = map.region_outline(String((_target as FacilityRegion).region_id()))
		if not outline.is_empty():
			var points : PackedVector2Array = []
			for point : Vector2 in outline:
				points.append(to_screen * point)
			overlay.draw_multiline(points, colour, 4.0)
	if _hover_room != null:
		var mine : bool = _is_member(_hover_room)
		for cells : Rect2i in _hover_room.cell_rects(map):
			overlay.draw_rect(_screen_rect(to_screen, cells), Color.WHITE, false, 3.0)
		var text : String = ("click: take %s out of %s" if mine else "click: add %s to %s") % [_hover_room.name, _label()]
		if not _items_mode() and not mine and _hover_room.region != &"":
			text += " (moves it from %s)" % _hover_room.region
		if _items_mode() and mine:
			text += " (chance %d%%, %s: set item_chance and item_pool in the inspector)" % [_hover_room.item_chance, "its own list" if _hover_room.has_own_pool() else "the map's list"]
		var at : Vector2 = overlay.get_local_mouse_position() + Vector2(16.0, -12.0)
		var width : float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		overlay.draw_rect(Rect2(at + Vector2(-6.0, -16.0), Vector2(width + 12.0, 22.0)), Color(0.0, 0.0, 0.0, 0.8))
		overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _room_under(screen_point : Vector2, map : FacilityMap) -> FacilityRoom:
	var local : Vector2 = (map.get_viewport_transform() * map.get_global_transform()).affine_inverse() * screen_point
	var cell : Vector2i = map.world_to_cell(local)
	for room : FacilityRoom in map.room_nodes(): #from the nodes, not the map's last build, so a room just changed is found where it is now
		if room.is_exit():
			continue
		for rect : Rect2i in room.cell_rects(map):
			if rect.has_point(cell):
				return room
	return null


func _screen_rect(to_screen : Transform2D, cells : Rect2i) -> Rect2:
	var tile : float = FacilityTileSet.TILE
	var a : Vector2 = to_screen * (Vector2(cells.position) * tile)
	var b : Vector2 = to_screen * (Vector2(cells.end) * tile)
	return Rect2(a, b - a).abs()


func _map() -> FacilityMap:
	if not is_instance_valid(_target) or not _target.is_inside_tree():
		return null
	return _target.call(&"facility_map") as FacilityMap


func _disconnect_map() -> void:
	var map : FacilityMap = _map()
	if map != null and map.built.is_connected(update_overlays):
		map.built.disconnect(update_overlays)


func _update_hint() -> void:
	if _hint == null:
		return
	_hint.visible = is_instance_valid(_target)
	if not _hint.visible:
		return
	if _items_mode():
		_hint.text = "  Item rooms: click rooms to let items spawn in them, or stop (shift: add only, ctrl: select). Chance per room: item_chance  "
	else:
		_hint.text = "  Region %s: click rooms to add or remove them (shift: add only, ctrl: select)  " % _label()
