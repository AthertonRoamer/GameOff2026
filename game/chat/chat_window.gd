class_name ChatWindow
extends PanelContainer

##The local player's chat window, in the HUD. Move and resize it freely in the editor (drag the ChatWindow node in player_hud.tscn): everything in it sits
##in containers, so it works tall above the minimap or as a long strip beside the inventory.
##
##Enter starts typing (the player stops moving and shooting), Enter again sends, Esc stops typing. Clicking on the window starts typing, clicking off it
##stops. A player on both channels (an imposter) gets a header with a tab for each: GUARDS in green, INTRUDERS in red. The one being written in is big
##and bright, the other small with a bubble counting the messages not seen there yet. C or a click on a tab switches.
##Every message that arrives dings, through a plain (not positional) AudioStreamPlayer: only peers the lobby sent the message to ever play it.
##HUD.bind_chat hands it the relay, the local player and the channels; until then (and in a deathmatch or the playground) it stays hidden.
##After idle_hide_seconds with nothing happening it fades away (and takes no clicks); Enter brings it back, and so does a message arriving.

@export_group("Colours")
@export var guards_colour : Color = Color("#3ddc6a") ## the GUARDS tab
@export var intruders_colour : Color = Color("#ff3b3b") ## the INTRUDERS tab
@export var own_name_colour : Color = Palette.BACKUP ## your name on your own messages
@export var name_colour : Color = Palette.ACCENT_BLUE ## everyone else's name
@export_group("Header")
@export var active_tab_font_size : int = 22 ## the channel being written in
@export var inactive_tab_font_size : int = 13 ## the other one
@export_group("Log")
@export var history_lines : int = 100 ## kept per channel; older lines are dropped
@export var log_font_size : int = 13
@export_group("Auto hide")
@export_range(0.0, 60.0, 0.5, "suffix:s") var idle_hide_seconds : float = 8.0 ## faded away after this long with no message and no typing. 0: never
@export_range(0.0, 2.0, 0.05, "suffix:s") var fade_seconds : float = 0.4
@export_group("Ding")
@export var ding : AudioStream ## played when a message arrives. None: a short chime made in code
@export var ding_volume_db : float = -8.0
@export var ding_bus : StringName = &"Master"

@onready var _header : HBoxContainer = $Box/Header
@onready var _tabs : Array[Button] = [$Box/Header/GuardsTab, $Box/Header/IntrudersTab]
@onready var _bubbles : Array[PanelContainer] = [$Box/Header/GuardsBubble, $Box/Header/IntrudersBubble]
@onready var _log : RichTextLabel = $Box/Log
@onready var _line : LineEdit = $Box/Input
@onready var _ding_player : AudioStreamPlayer = $Ding

var relay : ChatRelay
var _player : Player
var _channels : Array[int] = []
var _current : int = ChatRules.Channel.GUARDS
var _history : Dictionary = {ChatRules.Channel.GUARDS: [], ChatRules.Channel.INTRUDERS: []} #channel -> lines (BBCode)
var _unread : Dictionary = {ChatRules.Channel.GUARDS: 0, ChatRules.Channel.INTRUDERS: 0}
var _line_focused : bool = false
var _mouse_held : bool = false #a click on (or off) the window is still held: the player does not shoot with it
var _can_send : bool = true
var _panel_style : StyleBoxFlat
var _focus_style : StyleBoxFlat
var _idle : float = 0.0 #seconds since anything happened
var held_open : bool = false : set = set_held_open ## stays up whatever happens (the role reveal)


func _ready() -> void:
	visible = false #shown by bind()
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(Palette.SHADOW, 0.72)
	_panel_style.border_color = Palette.PANEL_LINE
	_panel_style.set_border_width_all(1)
	_panel_style.set_content_margin_all(6)
	_focus_style = _panel_style.duplicate()
	_focus_style.border_color = Palette.BACKUP
	add_theme_stylebox_override("panel", _panel_style)
	_log.add_theme_font_size_override("normal_font_size", log_font_size)
	_log.add_theme_font_size_override("italics_font_size", log_font_size)
	for channel in 2:
		_tabs[channel].pressed.connect(switch_to.bind(channel))
		_tabs[channel].focus_mode = Control.FOCUS_NONE
		var bubble_style : StyleBoxFlat = StyleBoxFlat.new()
		bubble_style.bg_color = _colour_of(channel)
		bubble_style.set_corner_radius_all(9)
		bubble_style.content_margin_left = 6
		bubble_style.content_margin_right = 6
		_bubbles[channel].add_theme_stylebox_override("panel", bubble_style)
		(_bubbles[channel].get_child(0) as Label).add_theme_color_override("font_color", Palette.VOID)
	_line.max_length = ChatRules.MAX_LENGTH
	_line.focus_entered.connect(_on_line_focus.bind(true))
	_line.focus_exited.connect(_on_line_focus.bind(false))
	_line.text_submitted.connect(_on_submitted)
	_line.gui_input.connect(_on_line_input)
	_ding_player.stream = ding if ding != null else make_chime()
	_ding_player.volume_db = ding_volume_db
	_ding_player.bus = ding_bus if AudioServer.get_bus_index(ding_bus) != -1 else &"Master"
	_refresh_header()


##Connects the window to the relay and the local player, on the channels given (ChatRules.channels_for). No channels: hidden.
##Called again whenever the local player's role or team changes; the history is kept.
func bind(new_relay : ChatRelay, player : Player, channels : Array[int]) -> void:
	if relay != new_relay:
		if relay != null:
			relay.message_received.disconnect(_on_message)
			relay.notice.disconnect(_on_notice)
		relay = new_relay
		relay.message_received.connect(_on_message)
		relay.notice.connect(_on_notice)
	if _player != player:
		if is_instance_valid(_player):
			_player.died.disconnect(_refresh_can_send)
			_player.health_changed.disconnect(_on_health_changed)
		_player = player
		_player.died.connect(_refresh_can_send)
		_player.health_changed.connect(_on_health_changed)
	if _channels != channels:
		wake()
	_channels = channels.duplicate()
	visible = not _channels.is_empty()
	if not visible:
		stop_typing()
		return
	if not _channels.has(_current):
		_current = _channels[0]
	_unread[_current] = 0
	_refresh_can_send()
	_refresh_header()
	_redraw_log()


func current_channel() -> int:
	return _current


func unread(channel : int) -> int:
	return _unread.get(channel, 0)


func is_typing() -> bool:
	return _line_focused


func set_held_open(value : bool) -> void:
	held_open = value
	wake()


## Shows the window (again) and starts the idle time over.
func wake() -> void:
	_idle = 0.0
	modulate.a = 1.0
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED


func is_faded() -> bool:
	return idle_hide_seconds > 0.0 and _idle >= idle_hide_seconds


func _process(delta : float) -> void:
	if not visible or idle_hide_seconds <= 0.0:
		return
	if held_open or _line_focused or _mouse_held:
		wake()
		return
	_idle += delta
	if is_faded():
		mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED #(what is not there takes no clicks)
		modulate.a = clampf(1.0 - (_idle - idle_hide_seconds) / maxf(fade_seconds, 0.001), 0.0, 1.0)


func start_typing() -> void:
	if not visible or _channels.is_empty():
		return
	wake() #(a dead player can still open it to read)
	if _can_send:
		_line.grab_focus()


func stop_typing() -> void:
	if _line.has_focus():
		_line.release_focus()


func switch_to(channel : int) -> void:
	if not _channels.has(channel):
		return
	wake()
	_current = channel
	_unread[channel] = 0
	_refresh_header()
	_redraw_log()


func _unhandled_input(event : InputEvent) -> void:
	if not is_visible_in_tree() or _line_focused or event.is_echo():
		return
	if event.is_action_pressed("chat_open"):
		if get_viewport().gui_get_focus_owner() == null: #(another box being typed in keeps its Enter)
			start_typing()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat_switch_channel") and _channels.size() > 1:
		switch_to(ChatRules.Channel.INTRUDERS if _current == ChatRules.Channel.GUARDS else ChatRules.Channel.GUARDS)
		get_viewport().set_input_as_handled()


##Clicks: on the window starts typing, off it stops. Either way the click is the chat's: while it is held the player does not shoot
##(the gun reads the held button, not the click), and a click off the window that stops typing goes no further.
func _input(event : InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventMouseButton:
		return
	var button : InputEventMouseButton = event
	if not button.pressed:
		if _mouse_held:
			_mouse_held = false
			_apply_typing()
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	var inside : bool = get_global_rect().has_point(button.position) and not is_faded()
	if inside:
		_mouse_held = true
		_apply_typing()
		if not _line_focused and not _tabs[0].get_global_rect().has_point(button.position) and not _tabs[1].get_global_rect().has_point(button.position):
			start_typing.call_deferred() #(after the click has gone through the window's own controls)
	elif _line_focused:
		_mouse_held = true
		stop_typing()
		get_viewport().set_input_as_handled()


func _on_line_focus(focused : bool) -> void:
	_line_focused = focused
	_apply_typing()


func _on_line_input(event : InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		stop_typing()
		_line.accept_event() #(the escape menu does not open as well)


func _on_submitted(text : String) -> void:
	_line.clear()
	if text.strip_edges() != "" and relay != null and _can_send:
		relay.submit(_current, text)
	stop_typing()


func _on_message(channel : int, sender : String, text : String, is_own : bool) -> void:
	if not _channels.has(channel):
		return
	var colour : Color = own_name_colour if is_own else name_colour
	var who : String = ChatRules.escape_bbcode(sender)
	if sender == ChatRules.UNKNOWN_ALLY:
		who = "[i]%s[/i]" % who
		colour = Palette.MUTED
	_add_line(channel, "[color=#%s]%s:[/color] %s" % [colour.to_html(false), who, ChatRules.escape_bbcode(text)])
	if channel != _current:
		_unread[channel] += 1
		_refresh_header()
	wake()
	_ding_player.play()


## The message ding on its own (a ping arrived).
func chime() -> void:
	_ding_player.play()


func _on_notice(text : String) -> void:
	wake()
	_add_line(_current, "[color=#%s][i]%s[/i][/color]" % [Palette.MUTED.to_html(false), ChatRules.escape_bbcode(text)])


func _add_line(channel : int, line : String) -> void:
	var lines : Array = _history[channel]
	lines.append(line)
	var dropped : bool = false
	while lines.size() > history_lines:
		lines.pop_front()
		dropped = true
	if channel == _current:
		if dropped:
			_redraw_log()
		else:
			_log.append_text(("\n" if lines.size() > 1 else "") + line)


func _redraw_log() -> void:
	_log.clear()
	_log.append_text("\n".join(PackedStringArray(_history[_current])))


func _refresh_header() -> void:
	_header.visible = _channels.size() > 1
	for channel in 2:
		var active : bool = channel == _current
		var tab : Button = _tabs[channel]
		var colour : Color = _colour_of(channel) if active else Color(_colour_of(channel).lerp(Palette.MUTED, 0.5), 0.75)
		tab.add_theme_font_size_override("font_size", active_tab_font_size if active else inactive_tab_font_size)
		for state : StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
			tab.add_theme_color_override(state, colour)
		var count : int = _unread[channel]
		_bubbles[channel].visible = not active and count > 0
		(_bubbles[channel].get_child(0) as Label).text = str(count) if count < 100 else "99+"


func _refresh_can_send() -> void:
	_can_send = is_instance_valid(_player) and (_player.is_alive() or (relay != null and relay.dead_can_send))
	_line.editable = _can_send
	_line.placeholder_text = "Press Enter to chat" if _can_send else "Dead players can only read"
	if not _can_send:
		stop_typing()


func _on_health_changed(_health : float) -> void:
	_refresh_can_send()


func _apply_typing() -> void:
	add_theme_stylebox_override("panel", _focus_style if _line_focused else _panel_style)
	if is_instance_valid(_player):
		_player.input.typing = _line_focused or _mouse_held


func _colour_of(channel : int) -> Color:
	return intruders_colour if channel == ChatRules.Channel.INTRUDERS else guards_colour


##A short two-note bell, made in code so the chat needs no sound file.
static func make_chime() -> AudioStreamWAV:
	var rate : int = 44100
	var length : float = 0.32
	var count : int = int(rate * length)
	var data : PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t : float = float(i) / rate
		var second : float = 1.0 if t > 0.07 else 0.0
		var sample : float = 0.45 * sin(TAU * 1318.5 * t) * exp(-t * 14.0) \
				+ 0.4 * second * sin(TAU * 1975.5 * (t - 0.07)) * exp(-(t - 0.07) * 11.0)
		sample *= minf(t * 400.0, 1.0) #(no click at the start)
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream : AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
