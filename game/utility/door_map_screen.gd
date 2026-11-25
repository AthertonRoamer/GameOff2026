class_name DoorMapScreen
extends Control

##The door control screen: a map of the facility with every door on it (a FacilityMapView with rooms, doors and the player's dot; scroll and zoom it
##like any map). Click a door to open or close it. Locked doors cannot be changed. Click anywhere else in a room to switch its ceiling light (LightsLayer). Put it on a CanvasLayer (it covers the screen), set `facility`
##and `control`, call open() and listen for `closed`. A click does not change the door itself: it asks `control` (the lobby decides, then every
##peer switches the door on the same tick). A door whose change is on its way blinks. Without a control (a bare test) the click flips it locally.

signal closed

const BG_DIM : Color = Color(0.03, 0.04, 0.05, 0.78)
const PANEL : Color = Palette.PANEL
const LINE : Color = Palette.PANEL_LINE
const TEXT : Color = Palette.TEXT
const MUTED : Color = Palette.MUTED
const ACCENT : Color = Palette.BACKUP
const OPEN_COLOUR : Color = DoorsLayer.OPEN_COLOUR
const CLOSED_COLOUR : Color = DoorsLayer.CLOSED_COLOUR
const LOCKED_COLOUR : Color = DoorsLayer.LOCKED_COLOUR
const MARGIN : float = 36.0

var facility : FacilityMap
var control : FacilityControl
var player : Node2D #drawn as a dot on the map
var _close_rect : Rect2
var _panel_rect : Rect2
var _font : Font
var _refusal : String = "" #"NO POWER IN ...": the lobby refused a door, shown for a moment
var _refusal_left : float = 0.0

@onready var map : FacilityMapView = $Map
@onready var doors_layer : DoorsLayer = $Map/Doors
@onready var lights_layer : LightsLayer = $Map/Lights #the rooms' ceiling lights: click a room to switch its light
@onready var player_layer : PlayerDotLayer = $Map/Player
@onready var regions_layer : RegionsLayer = $Map/Regions #the power regions and the power free in each (doors cost power to keep shut)


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font() #the theme's (night_shift_theme.tres)


func open(tracked : Node2D = null) -> void:
	player = tracked
	visible = true
	_layout()
	doors_layer.control = control
	lights_layer.control = control
	regions_layer.grid = control.power if control != null else null
	if control != null and not control.door_refused.is_connected(_on_door_refused):
		control.door_refused.connect(_on_door_refused)
	if control != null and not control.light_refused.is_connected(_on_light_refused):
		control.light_refused.connect(_on_light_refused)
	player_layer.tracked = tracked
	if map.facility != facility:
		map.facility = facility
	if is_instance_valid(tracked):
		map.center_on(tracked.global_position) #where the player is: the console they are using
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


##Asks for a door to flip, the way a click does. Returns false for a locked door or one already switching.
func toggle_door(door : FacilityDoor) -> bool:
	doors_layer.control = control
	return doors_layer.toggle_door(door)


##Asks for a room's light to switch, the way a click on the room does. Returns false for no light or one already switching.
func toggle_light(index : int) -> bool:
	lights_layer.control = control
	return lights_layer.toggle_light(index)


##The door under a position on this screen, if any.
func door_at(screen_position : Vector2) -> FacilityDoor:
	return doors_layer.door_at(map.screen_to_world(screen_position - map.position))


##Where a door is on this screen (it may be scrolled out of the map's view).
func screen_position_of(door : FacilityDoor) -> Vector2:
	return map.position + map.world_to_screen(door.position)


func _process(delta : float) -> void:
	_refusal_left = maxf(0.0, _refusal_left - delta)
	if visible:
		queue_redraw() #the door counts change


func _on_door_refused(door : FacilityDoor, reason : String) -> void:
	if reason == "power":
		_refusal = "NO POWER IN %s TO CLOSE IT" % facility.region_name(facility.region_of_door(door)).to_upper()
		_refusal_left = 2.5


func _on_light_refused(index : int, reason : String) -> void:
	if reason == "power":
		_refusal = "NO POWER IN %s FOR THAT LIGHT" % facility.region_name(control.light_region(index)).to_upper()
		_refusal_left = 2.5


func _notification(what : int) -> void:
	if what == NOTIFICATION_RESIZED and visible and facility != null:
		_layout()


func _input(event : InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _gui_input(event : InputEvent) -> void: #clicks outside the map (the map takes its own)
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if _close_rect.has_point((event as InputEventMouseButton).position):
			close()
	accept_event()


func _layout() -> void:
	_panel_rect = Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)
	var map_area : Rect2 = Rect2(_panel_rect.position + Vector2(14.0, 56.0), _panel_rect.size - Vector2(28.0, 56.0 + 36.0))
	map.position = map_area.position
	map.size = map_area.size
	_close_rect = Rect2(_panel_rect.end.x - 92.0, _panel_rect.position.y + 12.0, 80.0, 28.0)


func _draw() -> void:
	if facility == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG_DIM)
	draw_rect(_panel_rect, PANEL)
	draw_rect(_panel_rect, LINE, false, 2.0)
	draw_rect(Rect2(_panel_rect.position, Vector2(6.0, 44.0)), ACCENT)
	draw_string(_font, _panel_rect.position + Vector2(20.0, 30.0), "DOORS & LIGHTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT)
	var open_count : int = 0
	var closed_count : int = 0
	for door in facility.doors:
		if door.state == FacilityDoor.State.OPEN:
			open_count += 1
		else:
			closed_count += 1
	var lit_count : int = 0
	if control != null:
		for index in control.light_count():
			if control.is_light_on(index):
				lit_count += 1
	draw_string(_font, _panel_rect.position + Vector2(200.0, 29.0), "%d open   %d closed   %d lit" % [open_count, closed_count, lit_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	if control != null and control.power != null:
		draw_string(_font, _panel_rect.position + Vector2(400.0, 29.0), "from its region: a shut door takes %s pts/s, a light %s pts/s" % [str(control.power.door_cost()), str(control.power.light_cost())], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	if _refusal_left > 0.0:
		draw_string(_font, _panel_rect.position + Vector2(20.0, 50.0), _refusal, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.ALARM)
	#close button
	var close_hover : bool = _close_rect.has_point(get_local_mouse_position())
	draw_rect(_close_rect, ACCENT if close_hover else LINE)
	draw_string(_font, _close_rect.position + Vector2(0.0, 19.0), "CLOSE", HORIZONTAL_ALIGNMENT_CENTER, _close_rect.size.x, 14, Palette.SHADOW if close_hover else TEXT)
	#the map's frame
	draw_rect(Rect2(map.position, map.size).grow(1.0), LINE, false, 1.0)
	#legend
	var y : float = _panel_rect.end.y - 18.0
	var x : float = _panel_rect.position.x + 20.0
	for entry : Array in [[OPEN_COLOUR, "open"], [CLOSED_COLOUR, "closed"], [LOCKED_COLOUR, "locked"], [Color(LightsLayer.ON_COLOUR, 0.6), "light on"]]:
		draw_rect(Rect2(x, y - 9.0, 12.0, 8.0), entry[0])
		draw_string(_font, Vector2(x + 18.0, y), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
		x += 86.0
	draw_string(_font, Vector2(x + 20.0, y), "click a door to open or close it, a room to switch its light   -   drag to scroll, wheel to zoom   -   E or Esc to leave", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
