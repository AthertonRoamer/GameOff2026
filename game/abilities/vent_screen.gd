class_name VentScreen
extends Control

##The vent map: the facility with every vent marked on it. Opened by a ventrat at a vent; clicking another vent asks AbilityControl to take them there, and the screen
##closes. E or Esc closes it without going. Same look and controls as the other maps (drag to scroll, wheel to zoom). Needs `facility` and `control`, then open().

signal closed

const MARGIN : float = 36.0

var facility : FacilityMap
var control : AbilityControl

var _from : Vent
var _panel_rect : Rect2
var _font : Font

@onready var map : FacilityMapView = $Map
@onready var vents_layer : VentsLayer = $Map/Vents
@onready var player_layer : PlayerDotLayer = $Map/Player


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()
	vents_layer.picked.connect(_on_picked)


func open(player : Player, from : Vent) -> void:
	_from = from
	visible = true
	_layout()
	if map.facility != facility:
		map.facility = facility
	vents_layer.vents = control.vents
	vents_layer.from = from
	player_layer.tracked = player
	map.center_on(from.global_position)
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _on_picked(vent : Vent) -> void:
	control.request_vent(_from, vent)
	close()


func _input(event : InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _gui_input(_event : InputEvent) -> void:
	if visible:
		accept_event()


func _notification(what : int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_layout()


func _layout() -> void:
	_panel_rect = Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)
	var map_area : Rect2 = Rect2(_panel_rect.position + Vector2(14.0, 56.0), _panel_rect.size - Vector2(28.0, 56.0 + 36.0))
	map.position = map_area.position
	map.size = map_area.size


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.05, 0.78))
	draw_rect(_panel_rect, Palette.PANEL)
	draw_rect(_panel_rect, Palette.PANEL_LINE, false, 2.0)
	draw_rect(Rect2(_panel_rect.position, Vector2(6.0, 44.0)), Palette.BACKUP)
	draw_string(_font, _panel_rect.position + Vector2(20.0, 30.0), "VENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.TEXT)
	draw_rect(Rect2(map.position, map.size).grow(1.0), Palette.PANEL_LINE, false, 1.0)
	draw_string(_font, Vector2(_panel_rect.position.x + 20.0, _panel_rect.end.y - 18.0), "click a vent to crawl there   -   drag to scroll, wheel to zoom   -   E or Esc to stay", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MUTED)
