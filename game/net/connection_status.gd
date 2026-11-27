extends CanvasLayer

## Shows the player when their connection is in trouble (an autoload, ConnectionStatus, so it works while a match loads too): nothing while all is well, an
## amber symbol when packets are being lost or the ping is high, a red one with a count of seconds when nothing is arriving from the lobby.
## The lobby sends every peer a small numbered heartbeat, unreliably, so one that is missing really was lost on the way. Each peer judges only its own
## connection (ConnectionMonitor); this changes nothing in the game.

signal state_changed(state : ConnectionMonitor.State)

@export var beats_per_second : float = 10.0
@export_group("When to show")
@export var lost_after_seconds : float = 3.5
@export_range(0.0, 1.0) var weak_loss : float = 0.08
@export var weak_ping_ms : float = 300.0

@onready var panel : Control = $Panel
@onready var icon : ConnectionIcon = $Panel/Row/Icon
@onready var title : Label = $Panel/Row/Text/Title
@onready var detail : Label = $Panel/Row/Text/Detail

var monitor : ConnectionMonitor = ConnectionMonitor.new()
var _number : int = 0
var _since_beat : float = 0.0
var _shown : ConnectionMonitor.State = ConnectionMonitor.State.GOOD


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	monitor.lost_after_seconds = lost_after_seconds
	monitor.weak_loss = weak_loss
	monitor.weak_ping_ms = weak_ping_ms
	panel.visible = false


func _process(delta : float) -> void:
	var enet : ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		monitor.reset() #(not in a lobby, or dropped: the menus say so themselves)
		_show(ConnectionMonitor.State.GOOD, 0.0)
		return
	if multiplayer.is_server():
		_since_beat += delta
		if _since_beat >= 1.0 / beats_per_second:
			_since_beat = 0.0
			_number += 1
			for id : int in multiplayer.get_peers():
				_heartbeat.rpc_id(id, _number)
		return
	var link : ENetPacketPeer = enet.get_peer(1)
	var ping : float = link.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if link != null else 0.0
	_show(monitor.evaluate(Time.get_ticks_msec() / 1000.0, ping), ping)


@rpc("authority", "call_remote", "unreliable")
func _heartbeat(number : int) -> void:
	monitor.beat(number, Time.get_ticks_msec() / 1000.0)


## Fills in the symbol and its two lines (public so a preview can show each state).
func _show(state : ConnectionMonitor.State, ping : float) -> void:
	if state != _shown:
		_shown = state
		panel.visible = state != ConnectionMonitor.State.GOOD
		print("ConnectionStatus: %s (loss %d%%, ping %d ms, silent %.1f s)" % [ConnectionMonitor.State.keys()[state], roundi(monitor.loss * 100.0), roundi(ping), monitor.silence])
		state_changed.emit(state)
	if state == ConnectionMonitor.State.GOOD:
		return
	icon.state = state
	var lost : bool = state == ConnectionMonitor.State.LOST
	title.text = "NO SIGNAL" if lost else "WEAK CONNECTION"
	title.add_theme_color_override("font_color", Palette.ALARM if lost else Palette.BACKUP)
	if lost:
		detail.text = "Waiting for the server... %d s" % floori(monitor.silence)
	else:
		detail.text = "%d%% packets missed   ping %d ms" % [roundi(monitor.loss * 100.0), roundi(ping)]
