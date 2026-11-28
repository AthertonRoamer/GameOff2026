class_name FacilityMapView
extends Control

##A map of the facility that you can scroll and zoom (a middle click that does not drag places a ping, see PingControl): drag with the left or middle mouse button (or pan with a trackpad) to scroll, the mouse wheel
##(or a trackpad pinch, or the + / - buttons) to zoom in and out. Every screen with a map uses one: the door console, the spawn choice, and later
##lights, cameras and the full map on Tab.
##
##What it shows is up to its layers: MapLayer nodes placed directly under it in the screen's scene (RoomsLayer, DoorsLayer, SpawnLayer...), drawn
##in that order, the first at the bottom. They draw in world pixels; this node gives them all the same scroll and zoom transform. A click that is not a drag goes to the
##layers from the top down until one takes it (MapLayer.map_click); a right click the same way (MapLayer.map_right_click). Set `facility` before showing it, then call reset_view() or center_on().

signal view_changed #scrolled or zoomed

const DRAG_THRESHOLD_PX : float = 4.0 #a press that moves further than this is a drag, not a click
const PAN_GESTURE_SPEED : float = 24.0 #screen pixels a trackpad pan moves the map per unit of its delta

@export var default_zoom : float = 0.8 #screen pixels per world pixel when the view opens: readable however big the map gets
@export var max_zoom : float = 3.0
@export var zoom_step : float = 1.2 #how much one wheel notch or button press zooms
@export var scroll_margin_px : float = 60.0 #how far past the map's edge it can be scrolled, in screen pixels
@export var live : bool = true #redraw every frame (moving dots, blinking doors). Off: only when the view or the layers ask
@export var show_zoom_buttons : bool = true
@export var redraw_hz : float = 0.0 ## how often a live map redraws. 0: every frame, and on every scroll (a map that only follows the player can redraw far less often)
@export var show_tooltips : bool = true ## a little label by the mouse naming the icon under it (a door, a generator, a vent...): see MapLayer.icon_label

var facility : FacilityMap : set = set_facility
var zoom : float = 1.0 #screen pixels per world pixel

var _center : Vector2 = Vector2.ZERO #the world point in the middle of the view
var _pressing : bool = false
var _dragging : bool = false
var _press_at : Vector2 = Vector2.ZERO
var _right_press_at : Vector2 = Vector2.ZERO
var _zoom_buttons : HBoxContainer
var _redraw_in : float = 0.0
var _tooltip : PanelContainer
var _tooltip_label : Label

const TOOLTIP_OFFSET : Vector2 = Vector2(16.0, 14.0) #from the mouse to the label's corner


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	for layer : MapLayer in layers():
		layer.view = self
	if show_zoom_buttons:
		_add_zoom_buttons()
	if show_tooltips:
		_add_tooltip()
	if facility != null:
		reset_view()


func set_facility(value : FacilityMap) -> void:
	facility = value
	if is_node_ready():
		reset_view()


func layers() -> Array[MapLayer]:
	var result : Array[MapLayer] = []
	for child : Node in get_children():
		if child is MapLayer:
			result.append(child)
	return result


##The part of the world worth showing: every wall and every room (outdoor pads and exit zones have no walls of their own).
func map_bounds() -> Rect2:
	if facility == null:
		return Rect2()
	var bounds : Rect2 = facility.map_bounds_px()
	for id : String in facility.rooms:
		for rect : Rect2 in facility.room_rects_px(id):
			bounds = bounds.merge(rect)
	for id : String in facility.exits:
		for rect : Rect2i in facility.exits[id]:
			bounds = bounds.merge(Rect2(Vector2(rect.position * FacilityTileSet.TILE), Vector2(rect.size * FacilityTileSet.TILE)))
	return bounds


##The furthest out it zooms: the whole map fits.
func min_zoom() -> float:
	var bounds : Rect2 = map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 0.05
	return minf(minf(size.x / bounds.size.x, size.y / bounds.size.y), max_zoom)


##Back to the opening zoom, centred on the middle of the map.
func reset_view() -> void:
	zoom = clampf(default_zoom, min_zoom(), max_zoom)
	_center = map_bounds().get_center()
	_apply()


##Zoomed all the way out: the whole map fits.
func fit_all() -> void:
	zoom = min_zoom()
	_center = map_bounds().get_center()
	_apply()


func center_on(world : Vector2) -> void:
	_center = world
	_apply(redraw_hz <= 0.0) #(scrolling only moves what the layers have already drawn)


func set_zoom(value : float) -> void:
	zoom_at(size / 2.0, value / zoom)


##Zooms by `factor` keeping the world point under `screen_point` where it is.
func zoom_at(screen_point : Vector2, factor : float) -> void:
	var world : Vector2 = screen_to_world(screen_point)
	zoom = clampf(zoom * factor, min_zoom(), max_zoom)
	_center = world - (screen_point - size / 2.0) / zoom
	_apply()


##Scrolls by a distance in screen pixels (positive moves the view right and down over the map).
func scroll_by(screen_delta : Vector2) -> void:
	_center += screen_delta / zoom
	_apply()


##A point in this control (its local coordinates) to the world, and back.
func screen_to_world(screen_point : Vector2) -> Vector2:
	return _center + (screen_point - size / 2.0) / zoom


func world_to_screen(world : Vector2) -> Vector2:
	return size / 2.0 + (world - _center) * zoom


func center() -> Vector2:
	return _center


func redraw_layers() -> void:
	for layer : MapLayer in layers():
		layer.queue_redraw()


func _apply(redraw : bool = true) -> void:
	_clamp_center()
	for layer : MapLayer in layers(): #every layer gets the same transform, so they all draw in world pixels
		layer.scale = Vector2.ONE * zoom
		layer.position = size / 2.0 - _center * zoom
		layer.modulate.a = layer.zoom_alpha(zoom)
	if redraw:
		redraw_layers()
	view_changed.emit()


func _clamp_center() -> void:
	var allowed : Rect2 = map_bounds().grow(scroll_margin_px / zoom)
	var half : Vector2 = size / 2.0 / zoom
	for axis in 2:
		if allowed.size[axis] <= half[axis] * 2.0:
			_center[axis] = allowed.get_center()[axis]
		else:
			_center[axis] = clampf(_center[axis], allowed.position[axis] + half[axis], allowed.end[axis] - half[axis])


func _process(delta : float) -> void:
	if not is_visible_in_tree():
		if _tooltip != null:
			_tooltip.visible = false
		return
	_update_tooltip()
	var intel : Node = _intel()
	if intel != null:
		intel.apply(self) #the same icons on every map
	if not live:
		return
	_redraw_in -= delta
	if redraw_hz <= 0.0 or _redraw_in <= 0.0:
		_redraw_in = 1.0 / redraw_hz if redraw_hz > 0.0 else 0.0
		redraw_layers()


func _notification(what : int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and facility != null:
		zoom = clampf(zoom, min_zoom(), max_zoom)
		_apply()


func _gui_input(event : InputEvent) -> void:
	if facility == null:
		return
	if event is InputEventMouseButton:
		var button : InputEventMouseButton = event
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			zoom_at(button.position, zoom_step if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_step)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				_pressing = true
				_dragging = false
				_press_at = button.position
			else:
				if _pressing and not _dragging and button.button_index == MOUSE_BUTTON_LEFT:
					click(button.position)
				elif _pressing and not _dragging: #a middle click that did not drag places a ping
					_ping(button.position)
				_pressing = false
				_dragging = false
			accept_event()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed:
				_right_press_at = button.position
			elif button.position.distance_to(_right_press_at) <= DRAG_THRESHOLD_PX:
				right_click(button.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var motion : InputEventMouseMotion = event
		if _pressing and not _dragging and motion.position.distance_to(_press_at) > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			scroll_by(-motion.relative)
		else:
			var world : Vector2 = screen_to_world(motion.position)
			for layer : MapLayer in layers():
				if layer.visible:
					layer.map_hover(world)
		accept_event()
	elif event is InputEventPanGesture:
		scroll_by((event as InputEventPanGesture).delta * PAN_GESTURE_SPEED)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at((event as InputEventMagnifyGesture).position, (event as InputEventMagnifyGesture).factor)
		accept_event()


## The game's MapIntel, if there is one. Found and called by group, not by its class: every scene with a map loads this script, and naming MapIntel here would
## have each of them load most of the game with it, round in a circle.
func _intel() -> Node:
	return get_tree().get_first_node_in_group(&"map_intel")


func _ping(screen_point : Vector2) -> void:
	var intel : Node = _intel()
	if intel != null:
		intel.request_ping(facility.to_global(screen_to_world(screen_point)), get_global_transform() * screen_point)


##A click at a point in this control: offered to the layers from the top down until one takes it. Returns whether one did.
func click(screen_point : Vector2) -> bool:
	var world : Vector2 = screen_to_world(screen_point)
	var all : Array[MapLayer] = layers()
	for i in range(all.size() - 1, -1, -1):
		if all[i].visible and all[i].map_click(world):
			return true
	return false


##A right click at a point in this control: offered to the layers from the top down like click().
func right_click(screen_point : Vector2) -> bool:
	var world : Vector2 = screen_to_world(screen_point)
	var all : Array[MapLayer] = layers()
	for i in range(all.size() - 1, -1, -1):
		if all[i].visible and all[i].map_right_click(world):
			return true
	return false


func _add_zoom_buttons() -> void:
	_zoom_buttons = HBoxContainer.new()
	_zoom_buttons.name = "ZoomButtons"
	_zoom_buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	_zoom_buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_zoom_buttons)
	for entry : Array in [["-", 1.0 / zoom_step], ["+", zoom_step]]:
		var button : Button = Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(32, 32)
		button.focus_mode = Control.FOCUS_NONE
		var factor : float = entry[1]
		button.pressed.connect(func() -> void: zoom_at(size / 2.0, factor))
		_zoom_buttons.add_child(button)


# ------------------------------------------------------------------ the label for the icon under the mouse
##What the icon under this point of the view is (the top layer that has one there wins), or "" for none.
func icon_label_at(screen_point : Vector2) -> String:
	if facility == null:
		return ""
	var world : Vector2 = screen_to_world(screen_point)
	var all : Array[MapLayer] = layers()
	for areas : bool in [false, true]: #the small icons first, then the layers that label whole rooms and zones (MapLayer.labels_areas)
		for i in range(all.size() - 1, -1, -1):
			if all[i].visible and all[i].modulate.a > 0.05 and all[i].labels_areas() == areas:
				var text : String = all[i].icon_label(world)
				if text != "":
					return text
	return ""


func _add_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.name = "Tooltip"
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip.z_index = 10
	var style : StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(Palette.PANEL, 0.94)
	style.border_color = Palette.METAL
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 3.0
	_tooltip.add_theme_stylebox_override("panel", style)
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 12)
	_tooltip_label.add_theme_color_override("font_color", Palette.TEXT)
	_tooltip.add_child(_tooltip_label)
	add_child(_tooltip)


##Shows the label for the icon under the mouse, beside the mouse and kept inside the view. A view that takes the mouse shows it only while the mouse is over it (not
##over something covering it); one that does not (the minimap) only while the mouse is over nothing else of the interface.
func _update_tooltip() -> void:
	if _tooltip == null:
		return
	var mouse : Vector2 = get_local_mouse_position()
	var text : String = ""
	if Rect2(Vector2.ZERO, size).has_point(mouse) and not _dragging and _mouse_is_here():
		text = icon_label_at(mouse)
	if text == "":
		_tooltip.visible = false
		return
	if _tooltip_label.text != text:
		_tooltip_label.text = text
		_tooltip.reset_size()
	var box : Vector2 = _tooltip.get_combined_minimum_size()
	var at : Vector2 = mouse + TOOLTIP_OFFSET
	if at.x + box.x > size.x:
		at.x = mouse.x - TOOLTIP_OFFSET.x - box.x
	if at.y + box.y > size.y:
		at.y = mouse.y - TOOLTIP_OFFSET.y - box.y
	_tooltip.position = at.clamp(Vector2.ZERO, (size - box).max(Vector2.ZERO))
	_tooltip.size = box
	_tooltip.visible = true
	move_child(_tooltip, get_child_count() - 1) #(drawn over the layers and the zoom buttons)


func _mouse_is_here() -> bool:
	var hovered : Control = get_viewport().gui_get_hovered_control()
	if mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return hovered == null or hovered == self or is_ancestor_of(hovered)
	return hovered == self or (hovered != null and is_ancestor_of(hovered))
