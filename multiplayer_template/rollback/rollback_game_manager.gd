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

var _start_pending : bool = false


func _ready() -> void:
	game_scene = Main.main.configuration.game_scene


func get_game() -> Node:
	return game


func load_game() -> void:
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
	var timeout_msec : int = int(Main.main.configuration.rollback_sync_timeout * 1000.0)
	var deadline : int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		var all_synced : bool = true
		for member in lobby.members:
			if not NetworkTime.is_client_synced(member.id):
				all_synced = false
				break
		if all_synced:
			return
		await get_tree().create_timer(0.1).timeout
		if not is_inside_tree():
			return
	push_warning("RollbackGameManager timed out waiting for all members to sync their clocks, starting anyway")


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
