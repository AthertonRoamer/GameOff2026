class_name MapScreen
extends Control

##The facility map the player opens with the map key (Caps Lock): the same map as a control panel's screen (rooms and where you are; scroll it by dragging, zoom with the
##wheel), without the doors to click. The game goes on behind it. The key (or Esc) closes it. Put it on the HUD, set `facility` and `player`.
##The treasure rooms that held a relic when the match started are outlined in yellow for everyone (mark_relic_rooms, RelicRoomsLayer); the outline stays
##when a relic is carried off. The target exit is outlined in green for intruders only: not for a guard who is secretly attacking, although their game
##knows it too (`exit_chooser` knows it on every attacker's game, DesignatedExitChooser; never on a defender's).

const BG_DIM : Color = Color(0.03, 0.04, 0.05, 0.78)
const MARGIN : float = 36.0

var facility : FacilityMap
var player : Node2D #drawn as a dot on the map
var power : PowerGrid #the regions' power numbers and the generators, shown to guards only (PowerReadout.shows_power_to)
var exit_chooser : DesignatedExitChooser #the target exit, outlined for an intruder (shows_exit_to). Unset: no exit is shown
var exit_needs_intruder : bool = true #off: anyone whose game knows the exit sees it (the playground's player has no role)

var _panel_rect : Rect2
var _font : Font

@onready var map : FacilityMapView = $Map
@onready var player_layer : PlayerDotLayer = $Map/Player
@onready var regions_layer : RegionsLayer = $Map/Regions #the region outlines, for everyone; the power under their names, for guards
@onready var generators_layer : GeneratorsLayer = $Map/Generators
@onready var exits_layer : ExitsLayer = $Map/Exits #the target exit only, for intruders
@onready var relic_rooms_layer : RelicRoomsLayer = $Map/RelicRooms


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_default_font()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if facility == null:
		return
	visible = true
	_layout()
	if map.facility != facility:
		map.facility = facility
	player_layer.tracked = player
	var guard : bool = power != null and PowerReadout.shows_power_to(player)
	regions_layer.grid = power
	regions_layer.show_power = guard
	generators_layer.grid = power
	exits_layer.highlighted = exit_chooser.designated if exit_chooser != null and shows_exit_to(player) else "" #(checked on every open: a role can change)
	if is_instance_valid(player):
		map.center_on(player.global_position)
	queue_redraw()


##Whether this player sees the target exit: an intruder does; a guard does not, even one secretly attacking.
func shows_exit_to(viewer : Node2D) -> bool:
	if not exit_needs_intruder:
		return true
	return viewer is Player and (viewer as Player).role != null and (viewer as Player).role.is_intruder()


##Outlines the treasure rooms (kind Item) that have a relic at one of these positions. Called once, when the relics are placed at the start of the match
##(ArtifactPlacer.placed): the outlines stay as they are when a relic is carried off.
func mark_relic_rooms(positions : PackedVector2Array) -> void:
	var ids : Array[String] = []
	if facility != null:
		for at : Vector2 in positions:
			var id : String = facility.room_at(facility.to_local(at))
			if id != "" and facility.rooms[id]["kind"] == "item" and not ids.has(id):
				ids.append(id)
	relic_rooms_layer.rooms = ids


func close() -> void:
	visible = false


func _input(event : InputEvent) -> void:
	if event.is_action_pressed("player_map") and not event.is_echo() and not get_viewport().gui_get_focus_owner() is LineEdit: #(not while typing in the chat)
		get_viewport().set_input_as_handled()
		toggle()
	elif visible and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _gui_input(_event : InputEvent) -> void: #the screen covers the game: clicks outside the map go nowhere
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
	draw_rect(Rect2(Vector2.ZERO, size), BG_DIM)
	draw_rect(_panel_rect, Palette.PANEL)
	draw_rect(_panel_rect, Palette.PANEL_LINE, false, 2.0)
	draw_rect(Rect2(_panel_rect.position, Vector2(6.0, 44.0)), Palette.BACKUP)
	draw_string(_font, _panel_rect.position + Vector2(20.0, 30.0), "FACILITY MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.TEXT)
	draw_rect(Rect2(map.position, map.size).grow(1.0), Palette.PANEL_LINE, false, 1.0)
	draw_string(_font, Vector2(_panel_rect.position.x + 20.0, _panel_rect.end.y - 18.0), "drag to scroll, wheel to zoom   -   Caps Lock or Esc to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MUTED)
