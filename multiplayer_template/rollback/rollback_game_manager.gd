class_name RollbackGameManager
extends GameManager

##Drop-in replacement for BasicGameManager for games that use netfox rollback.
##Same contract as BasicGameManager: set game_scene on the Configuration, give the root node of the game a start() and an end() method.
##What it adds:
##  - game_loaded is only reported once NetworkTime has finished its initial sync, so the lobby's load barrier also guarantees synced clocks
##  - the game does not start the moment the lobby says so. The lobby picks a tick a little in the future and every peer starts on that same tick

var game_scene : PackedScene
var game : Node
var start_tick : int = -1
var diagnostics : RollbackDiagnostics

const CLOCK_HEALTHY_OFFSET : float = 0.05 #seconds. How far a member's game clock may be from the shared clock when the game starts

var _start_pending : bool = false
var _saved_netfox_log_level : Variant = null #set while netfox's own logging is muted, see _mute_netfox_logs()
var _clock_reports : Dictionary = {} #lobby only. key: member id, value: {offset: float, received_msec: int}


func _ready() -> void:
	game_scene = Main.main.configuration.game_scene


func get_game() -> Node:
	return game


func _exit_tree() -> void:
	_restore_netfox_logs()


##Until the game starts, a client whose clock is still catching up gets thousands of "older than 64 frames" messages a second from
##netfox. Writing them stalls the process for seconds, which breaks its clock sync further (seen on lossy connections). They carry no
##information while the clock is catching up, so netfox's own logging is muted from loading until the game starts.
func _mute_netfox_logs() -> void:
	if Main.main.configuration.rollback_quiet_loading and _saved_netfox_log_level == null:
		_saved_netfox_log_level = NetfoxLogger.module_log_level.get("netfox", NetfoxLogger.DEFAULT_LOG_LEVEL)
		NetfoxLogger.module_log_level["netfox"] = NetfoxLogger.LOG_NONE


func _restore_netfox_logs() -> void:
	if _saved_netfox_log_level != null:
		NetfoxLogger.module_log_level["netfox"] = _saved_netfox_log_level
		_saved_netfox_log_level = null


func load_game() -> void:
	_mute_netfox_logs()
	if game_scene != null:
		game = game_scene.instantiate()
		add_child(game, true)
	else:
		push_warning("RollbackGameManager cannot load game because it does not have a game scene to load")
	if Main.main.configuration.rollback_diagnostics and not lobby.is_master:
		diagnostics = RollbackDiagnostics.new()
		add_child(diagnostics)
	if not NetworkTime.is_initial_sync_done():
		Main.output("Rollback: waiting for time sync before reporting game loaded")
		await NetworkTime.after_sync
		if not is_inside_tree():
			return
	is_game_loaded = true
	game_loaded.emit()


func start_game() -> void:
	in_game = true
	if lobby.is_master:
		_schedule_start()
	#on every other peer the start tick arrives from the lobby in _receive_start_tick()


func end_game() -> void:
	_cancel_pending_start()
	_restore_netfox_logs()
	in_game = false
	is_game_loaded = false
	start_tick = -1
	ending_game.emit()
	if is_instance_valid(game):
		if game.has_method("end"):
			game.end()
		else:
			push_warning("RollbackGameManager cannot end game because it does not have an end method")
	if is_instance_valid(diagnostics):
		diagnostics.queue_free()
		diagnostics = null


func _schedule_start() -> void:
	await _wait_for_members_synced()
	if not in_game or not is_inside_tree():
		return
	var tick : int = NetworkTime.tick + Main.main.configuration.rollback_start_delay_ticks
	Main.output("Rollback: scheduling game start for tick %d (now %d)" % [tick, NetworkTime.tick])
	_receive_start_tick.rpc(tick)


func _wait_for_members_synced() -> void:
	#A member is ready when netfox says its initial sync is done AND its clock is currently healthy. The second part matters on
	#lossy connections: a lost clock message can leave a client seconds behind, and it then needs a long time to catch up.
	#Starting during that time makes every input from that client arrive "too old".
	var timeout_msec : int = int(Main.main.configuration.rollback_sync_timeout * 1000.0)
	var deadline : int = Time.get_ticks_msec() + timeout_msec
	var next_report : int = 0
	while Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() >= next_report:
			_request_clock_report.rpc() #asks every member for its current clock offset
			next_report = Time.get_ticks_msec() + 500
		var waiting_for : Array[int] = []
		for member in lobby.members:
			if not NetworkTime.is_client_synced(member.id) or not _is_clock_healthy(member.id):
				waiting_for.append(member.id)
		if waiting_for.is_empty():
			return
		await get_tree().create_timer(0.1).timeout
		if not is_inside_tree():
			return
	push_warning("RollbackGameManager timed out waiting for members' clocks to become healthy, starting anyway")


func _is_clock_healthy(member_id : int) -> bool:
	if not _clock_reports.has(member_id):
		return false
	var report : Dictionary = _clock_reports[member_id]
	var fresh : bool = Time.get_ticks_msec() - report["received_msec"] < 2000
	return fresh and absf(report["offset"]) <= CLOCK_HEALTHY_OFFSET


@rpc("authority", "call_remote", "unreliable")
func _request_clock_report() -> void:
	#unreliable on purpose: it is repeated every half second, and a lost reliable message would be delayed by retransmission
	_report_clock.rpc_id(1, NetworkTime.clock_offset)


@rpc("any_peer", "call_remote", "unreliable")
func _report_clock(offset : float) -> void:
	_clock_reports[multiplayer.get_remote_sender_id()] = {"offset": offset, "received_msec": Time.get_ticks_msec()}


@rpc("authority", "call_local", "reliable")
func _receive_start_tick(tick : int) -> void:
	start_tick = tick
	if not _start_pending:
		_start_pending = true
		NetworkTime.on_tick.connect(_on_network_tick)


func _on_network_tick(_delta : float, tick : int) -> void:
	if tick < start_tick or not in_game:
		return
	if tick > start_tick:
		push_warning("RollbackGameManager is late for the start tick (%d, now %d), start delay may be too short" % [start_tick, tick])
	_cancel_pending_start()
	_restore_netfox_logs()
	Main.output("Rollback: game starting on tick %d" % tick)
	starting_game.emit()
	if is_instance_valid(game) and game.has_method("start"):
		game.start()
	else:
		push_warning("RollbackGameManager cannot start game because the game is missing or has no start method")


func _cancel_pending_start() -> void:
	_start_pending = false
	if NetworkTime.on_tick.is_connected(_on_network_tick):
		NetworkTime.on_tick.disconnect(_on_network_tick)
