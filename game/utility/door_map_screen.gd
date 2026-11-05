class_name DoorMapScreen
extends Control

##The door control screen: a minimap of the whole facility with every door on it. Click a door to open or close it. Locked doors cannot be changed.
##It is drawn entirely in code in Palette A. Put it on a CanvasLayer (it covers the screen), set `facility` and `control`, call open() and listen
##for `closed`. A click does not change the door itself: it asks `control` (the lobby decides, then every peer switches the door on the same tick).
##A door whose change is on its way blinks. Without a control (a bare test) the click flips the door locally.

signal closed

const BG_DIM : Color = Color(0.03, 0.04, 0.05, 0.78)
const PANEL : Color = Color("#10131a")
const LINE : Color = Color("#262c36")
const TEXT : Color = Color("#e7e3d8")
const MUTED : Color = Color("#a9a495")
const ACCENT : Color = Color("#f2b544")
const OPEN_COLOUR : Color = Color("#4be38a")
const CLOSED_COLOUR : Color = Color("#e5484d")
const LOCKED_COLOUR : Color = Color("#f2b544")
const ROOM_FILL : Dictionary = {"corridor": Color("#1a1f27"), "utility": Color("#223a4a"), "item": Color("#26303f"), "office": Color("#1f2733"),
	"exterior_room": Color("#2a2d33"), "outdoor": Color("#12151a")}
const MARGIN : float = 36.0

var facility : FacilityMap
var control : FacilityControl
var player : Node2D #drawn as a dot on the map
var _hover : FacilityDoor
var _scale : float = 1.0
var _origin : Vector2 = Vector2.ZERO #screen position of the map's top-left corner
var _bounds : Rect2
var _close_rect : Rect2
var _panel_rect : Rect2
var _font : Font


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font


func open(tracked : Node2D = null) -> void:
	player = tracked
	_hover = null
	visible = true
	_layout()
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


##Asks for a door to flip, the way a click does. Returns false for a locked door or one already switching.
func toggle_door(door : FacilityDoor) -> bool:
	if door.state == FacilityDoor.State.LOCKED or (control != null and control.is_pending(door)):
		return false
	var target : FacilityDoor.State = FacilityDoor.State.OPEN if door.state == FacilityDoor.State.CLOSED else FacilityDoor.State.CLOSED
	if control != null:
		control.request_door(door, target)
	else:
		door.state = target
	queue_redraw()
	return true


##The door under a screen position, if any (doors are drawn thin, so the click area is a bit bigger).
func door_at(screen_position : Vector2) -> FacilityDoor:
	var best : FacilityDoor = null
	var best_distance : float = INF
	for door in facility.doors:
		var rect : Rect2 = _door_rect(door)
		if not rect.grow(7.0).has_point(screen_position):
			continue
		var distance : float = rect.get_center().distance_to(screen_position)
		if distance < best_distance:
			best = door
			best_distance = distance
	return best


func screen_position_of(door : FacilityDoor) -> Vector2:
	return _door_rect(door).get_center()


func _process(_delta : float) -> void:
	if visible:
		queue_redraw() #the player's dot moves, doors change


func _notification(what : int) -> void:
	if what == NOTIFICATION_RESIZED and visible and facility != null:
		_layout()


func _input(event : InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _gui_input(event : InputEvent) -> void:
	if not visible or facility == null:
		return
	if event is InputEventMouseMotion:
		_hover = door_at((event as InputEventMouse).position)
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var at : Vector2 = (event as InputEventMouseButton).position
		if _close_rect.has_point(at):
			close()
			return
		var door : FacilityDoor = door_at(at)
		if door != null:
			toggle_door(door)
	accept_event()


func _layout() -> void:
	_bounds = facility.map_bounds_px()
	for id : String in facility.rooms: #outdoor pads have no walls of their own, so the bounds are widened to take them in
		for rect : Rect2 in facility.room_rects_px(id):
			_bounds = _bounds.merge(rect)
	_bounds = _bounds.grow(14.0)
	_panel_rect = Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)
	var map_area : Rect2 = Rect2(_panel_rect.position + Vector2(14.0, 56.0), _panel_rect.size - Vector2(28.0, 56.0 + 36.0))
	_scale = minf(map_area.size.x / _bounds.size.x, map_area.size.y / _bounds.size.y)
	_origin = map_area.position + (map_area.size - _bounds.size * _scale) / 2.0
	_close_rect = Rect2(_panel_rect.end.x - 92.0, _panel_rect.position.y + 12.0, 80.0, 28.0)


func _to_screen(world : Vector2) -> Vector2:
	return _origin + (world - _bounds.position) * _scale


func _door_rect(door : FacilityDoor) -> Rect2:
	var length : float = FacilityDoor.LENGTH_PX * _scale
	var thickness : float = maxf(5.0, FacilityTileSet.TILE * _scale * 2.0)
	var size_px : Vector2 = Vector2(maxf(length, 12.0), thickness) if door.horizontal else Vector2(thickness, maxf(length, 12.0))
	return Rect2(_to_screen(door.position) - size_px / 2.0, size_px)


func _draw() -> void:
	if facility == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG_DIM)
	draw_rect(_panel_rect, PANEL)
	draw_rect(_panel_rect, LINE, false, 2.0)
	draw_rect(Rect2(_panel_rect.position, Vector2(6.0, 44.0)), ACCENT)
	draw_string(_font, _panel_rect.position + Vector2(20.0, 30.0), "DOOR CONTROL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT)
	var open_count : int = 0
	var closed_count : int = 0
	for door in facility.doors:
		if door.state == FacilityDoor.State.OPEN:
			open_count += 1
		else:
			closed_count += 1
	draw_string(_font, _panel_rect.position + Vector2(190.0, 29.0), "%d open   %d closed" % [open_count, closed_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	#close button
	var close_hover : bool = _close_rect.has_point(get_local_mouse_position())
	draw_rect(_close_rect, ACCENT if close_hover else LINE)
	draw_string(_font, _close_rect.position + Vector2(0.0, 19.0), "CLOSE", HORIZONTAL_ALIGNMENT_CENTER, _close_rect.size.x, 14, Color("#0c0e12") if close_hover else TEXT)
	#rooms
	for id : String in facility.rooms:
		var room : Dictionary = facility.rooms[id]
		var fill : Color = ROOM_FILL.get(room["kind"], LINE)
		for rect : Rect2 in facility.room_rects_px(id):
			var top_left : Vector2 = _to_screen(rect.position)
			var screen_rect : Rect2 = Rect2(top_left, rect.size * _scale)
			draw_rect(screen_rect, fill)
			draw_rect(screen_rect, Color("#4a5568") if room["kind"] != "outdoor" else Color("#222833"), false, 1.5)
	for id : String in facility.rooms: #names over the rooms, big enough ones only
		var room : Dictionary = facility.rooms[id]
		if room["kind"] == "corridor" or room["kind"] == "outdoor":
			continue
		var rects : Array[Rect2] = facility.room_rects_px(id)
		var centre : Vector2 = _to_screen(rects[0].get_center())
		var label_colour : Color = ACCENT if room["function"] == "doors" else MUTED
		draw_string(_font, centre + Vector2(-60.0, 4.0), String(room["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120.0, 9, label_colour)
	#doors
	for door in facility.doors:
		var rect : Rect2 = _door_rect(door)
		var colour : Color = [OPEN_COLOUR, CLOSED_COLOUR, LOCKED_COLOUR][door.state]
		if control != null and control.is_pending(door): #switching: blink while the change is on its way
			colour = colour.lerp(TEXT, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0))
		var hovered : bool = door == _hover
		if hovered:
			draw_rect(rect.grow(4.0), Color(colour, 0.35))
		draw_rect(rect.grow(1.5), Color("#06080c"))
		draw_rect(rect, colour)
	#the player
	if player != null:
		var at : Vector2 = _to_screen(player.global_position)
		draw_circle(at, 6.0, Color(ACCENT, 0.3))
		draw_circle(at, 3.5, Color("#6fd3e8"))
	#legend
	var y : float = _panel_rect.end.y - 18.0
	var x : float = _panel_rect.position.x + 20.0
	for entry : Array in [[OPEN_COLOUR, "open"], [CLOSED_COLOUR, "closed"], [LOCKED_COLOUR, "locked"]]:
		draw_rect(Rect2(x, y - 9.0, 12.0, 8.0), entry[0])
		draw_string(_font, Vector2(x + 18.0, y), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
		x += 86.0
	draw_string(_font, Vector2(x + 20.0, y), "click a door to open or close it   -   E or Esc to leave", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
