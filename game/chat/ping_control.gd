class_name PingControl
extends Node

##Placing pings, for the local player (in the HUD). A middle click on any map (the full map, the minimap, the door console, the vent map, the spawn map) or on
##the world in play opens a small box to name the ping: Enter places it (with or without a name), a second middle click places it at once, Esc or a click
##elsewhere drops it. It goes to the chat channel being written in (the box says which, in its colour), through ChatRelay: only that channel's players get it.
##A map's click comes in through MapIntel.ping_requested; the minimap takes no mouse of its own, so clicks on it and on the world are caught here.

const MARGIN : float = 12.0

@export var hud : CanvasLayer ## the PlayerHud: its chat says the channel, its minimap takes clicks while shown

@onready var _layer : CanvasLayer = $Box
@onready var _panel : PanelContainer = $Box/Panel
@onready var _title : Label = $Box/Panel/Rows/Title
@onready var _line : LineEdit = $Box/Panel/Rows/Label

var relay : ChatRelay
var _player : Player
var _intel : MapIntel
var _at : Vector2
var _channel : int = ChatRules.Channel.GUARDS


func _ready() -> void:
	_layer.visible = false
	_line.max_length = ChatRules.MAX_PING_LABEL
	_line.text_submitted.connect(func(_text : String) -> void: place())


func bind(new_relay : ChatRelay, player : Player) -> void:
	relay = new_relay
	_player = player


func listen_to(intel : MapIntel) -> void:
	_intel = intel
	intel.ping_requested.connect(open)


func is_open() -> bool:
	return _layer.visible


## Whether this player can ping at all now: in a match with chat (not a deathmatch), and alive unless the dead may send.
func can_ping() -> bool:
	return relay != null and hud.chat.visible and is_instance_valid(_player) and (_player.is_alive() or relay.dead_can_send)


## Opens the naming box for a ping at a world position, by the spot on the screen that was clicked.
func open(at : Vector2, screen_position : Vector2) -> void:
	if not can_ping():
		return
	_at = at
	_channel = hud.chat.current_channel()
	hud.chat.stop_typing()
	_title.text = "PING TO %s" % ChatRules.channel_name(_channel).to_upper()
	_title.add_theme_color_override("font_color", PingsLayer.colour_of(_channel))
	_line.clear()
	_layer.visible = true
	_panel.reset_size()
	var room : Vector2 = _panel.get_viewport_rect().size - _panel.size - Vector2.ONE * MARGIN
	_panel.position = (screen_position + Vector2(MARGIN, MARGIN)).clamp(Vector2.ONE * MARGIN, room.max(Vector2.ONE * MARGIN))
	_line.grab_focus()
	_player.input.typing = true #the keys and the mouse are the box's


func place() -> void:
	if not is_open():
		return
	if can_ping():
		relay.submit_ping(_channel, _at, _line.text)
	close()


func close() -> void:
	if not is_open():
		return
	_line.release_focus()
	_layer.visible = false
	if is_instance_valid(_player):
		_player.input.typing = hud.chat.is_typing()


func _process(_delta : float) -> void:
	if is_open() and not can_ping(): #died, or the match ended
		close()


func _input(event : InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled() #(the map under the box stays open)
		close()
	elif event is InputEventMouseButton and event.pressed:
		var button : InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			get_viewport().set_input_as_handled()
			place()
		elif not _panel.get_global_rect().has_point(button.position) and (button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT):
			get_viewport().set_input_as_handled()
			close()


func _unhandled_input(event : InputEvent) -> void: #the minimap and the world: nothing else took the click
	if not event is InputEventMouseButton or not event.pressed or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_MIDDLE:
		return
	if not hud.visible or not can_ping() or _intel == null: #(the HUD is up only in play)
		return
	var at : Vector2 = (event as InputEventMouseButton).position
	var minimap : Minimap = hud.minimap
	if minimap.is_visible_in_tree() and minimap.facility != null and minimap.get_global_rect().has_point(at):
		open(minimap.facility.to_global(minimap.screen_to_world(minimap.get_global_transform().affine_inverse() * at)), at)
	else:
		open(get_viewport().get_canvas_transform().affine_inverse() * at, at)
	get_viewport().set_input_as_handled()
