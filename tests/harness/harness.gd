extends Node

# Scripted two-process smoke test for the multiplayer template. Drives the real host/join code without menus.
# Run one process with `-- --role host` and, once it prints HOST_READY, another with `-- --role client`.
# Output lines are prefixed so a runner script can grep them.

const MAIN_SCENE : PackedScene = preload("res://multiplayer_template/main/main.tscn")
const LOBBY_PORT : int = 5000
const TIMEOUT : float = 45.0
const MOVING_HIT_RADIUS : float = 16.0

var role : String = "host"
var use_noray : bool = false
var use_rollback : bool = false
var use_demo : bool = false
var use_moving : bool = false #shooter and target run side by side, the shooter fires at where it sees the target
var no_lagcomp : bool = false #the lobby does not rewind targets, for comparison
var join_port : int = LOBBY_PORT #the client can join through a latency proxy by using another port
var game_id : String = ""
var main_node : Node


func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var idx : int = args.find("--role")
	if idx != -1 and idx + 1 < args.size():
		role = args[idx + 1]
	use_noray = args.has("--noray")
	use_moving = args.has("--moving")
	no_lagcomp = args.has("--no-lagcomp")
	use_demo = args.has("--demo") or use_moving or OS.get_cmdline_args().has("--harness-demo")
	use_rollback = args.has("--rollback") or use_demo
	idx = args.find("--join-port")
	if idx != -1 and idx + 1 < args.size():
		join_port = int(args[idx + 1])
	idx = args.find("--game-id")
	if idx != -1 and idx + 1 < args.size():
		game_id = args[idx + 1]
	if OS.get_cmdline_args().has("--harness-lobby"): #this process is the lobby instance launched by a rollback host
		role = "lobby"
		use_rollback = true
	main_node = MAIN_SCENE.instantiate()
	if use_rollback:
		apply_rollback_overrides(main_node)
	get_tree().root.add_child.call_deferred(main_node) #must be /root/Main so RPC node paths match the lobby instance
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if role == "host":
		await run_host()
	elif role == "client":
		await run_client()
	elif role == "lobby":
		await run_lobby_tweaks()


func apply_rollback_overrides(main : Node) -> void:
	#swaps in RollbackGameManager and either the probe game or the rollback demo configuration, without touching main.tscn.
	#Every process must do this, the lobby instance included
	if use_demo:
		main.configuration = load("res://multiplayer_template/demo_games/demo_rollback_game/rollback_demo_configuration.tres")
		main.configuration.rollback_diagnostics = false #keep the overlay out of the way of the automated run
	else:
		main.configuration.game_manager_scene = load("res://multiplayer_template/rollback/rollback_game_manager.tscn")
		main.configuration.game_scene = load("res://tests/harness/probe/probe_game.tscn")


func demo_positions(game : Node) -> String:
	var entries : Array = []
	for id in game.spawner.players:
		var p : Node2D = game.spawner.players[id]
		entries.append("%d=%.1f,%.1f,%d" % [id, p.position.x, p.position.y, p.health])
	return "me=%d %s" % [multiplayer.get_unique_id(), ";".join(entries)]


func run_lobby_tweaks() -> void:
	#the lobby instance has no test logic of its own, but the moving-target scenario needs it to tolerate many hits and, optionally, to not rewind
	if not OS.get_cmdline_args().has("--harness-moving"):
		return
	if not await wait_until(func(): return Main.mode != null and Main.mode.get_game() != null and "spawner" in Main.mode.get_game() and Main.mode.get_game().spawner.players.size() >= 2, 120.0):
		return
	var game : Node = Main.mode.get_game()
	for player in game.spawner.players.values():
		player.health = 1000
		game.get_node("LagCompensator").track(player, &"position", MOVING_HIT_RADIUS) #small targets make a stale rewind visible
	if OS.get_cmdline_args().has("--harness-no-lagcomp"):
		game.get_node("LagCompensator").max_rewind_ticks = 0
	print("[LOBBY] tweaks applied no_lagcomp=%s" % OS.get_cmdline_args().has("--harness-no-lagcomp"))


func moving_target_run(duration : float) -> void:
	#press down and, on the shooter, fire continuously at the displayed position of the other player
	var game : Node = Main.mode.get_game()
	var me : Node2D = game.spawner.local_player
	var target : Node2D = null
	for id in game.spawner.players:
		if id != multiplayer.get_unique_id():
			target = game.spawner.players[id]
	Input.action_press("ui_down")
	var is_shooter : bool = role == "client"
	if is_shooter:
		Input.action_press("ui_accept")
	var elapsed : float = 0.0
	var shots : int = 0
	var newest_shot_tick : int = me.last_fire_tick
	while elapsed < duration:
		if is_shooter:
			me.input.test_aim = (target.position - me.position).normalized()
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if me.last_fire_tick > newest_shot_tick: #resimulation can move it back, only count new highs
			newest_shot_tick = me.last_fire_tick
			shots += 1
	Input.action_release("ui_down")
	Input.action_release("ui_accept")
	if is_shooter:
		log_line("MOVING_SHOTS shots=%d rtt_ms=%.0f view_lag=%d" % [shots, NetworkTime.remote_rtt * 1000.0, me.input.view_lag])


func fire_pulse(aim : Vector2) -> void:
	#the client taps fire for a moment while aiming along `aim`. The cooldown is longer than the tap, so it is exactly one shot
	var game : Node = Main.mode.get_game()
	game.spawner.local_player.input.test_aim = aim
	Input.action_press("ui_accept")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("ui_accept")


func hold_move_right_and_measure() -> void:
	#the client presses right for one second. Reports how many frames passed before its own player visibly moved
	var game : Node = Main.mode.get_game()
	var me : Node2D = game.spawner.local_player
	var start_x : float = me.position.x
	Input.action_press("ui_right")
	var frames : int = 0
	while frames < 120 and me.position.x <= start_x:
		await get_tree().process_frame
		frames += 1
	log_line("LOCAL_RESPONSE frames=%d" % frames)
	await get_tree().create_timer(1.0).timeout
	Input.action_release("ui_right")


func log_line(msg : String) -> void:
	print("[%s] %s" % [role.to_upper(), msg])
	if OS.has_environment("HARNESS_MARK_STDERR"): #lets you see where engine errors fall relative to the test phases
		printerr("MARK [%s] %s" % [role.to_upper(), msg.left(40)])


func wait_until(condition : Callable, timeout : float = TIMEOUT) -> bool:
	var elapsed : float = 0.0
	while elapsed < timeout:
		if condition.call():
			return true
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	return false


func fail(msg : String) -> void:
	log_line("FAIL " + msg)
	get_tree().quit(1)


func describe_game() -> String:
	var game : Node = Main.mode.get_game()
	if game == null:
		return "no game"
	if game.has_method("describe"):
		return game.describe()
	if "spawner" in game:
		return demo_positions(game)
	var info : Array = []
	for p in game.players:
		if is_instance_valid(p):
			info.append("%s@%s" % [p.name, p.position])
	return "players=" + str(info)


func run_host() -> void:
	if use_noray: #same switch the host menu makes
		var lobby_args : Array[String] = Main.main.configuration.lobby_args
		lobby_args.erase("--mode lobby")
		lobby_args.append("--mode noray_lobby")
	if use_rollback: #the lobby instance has to run the harness scene too so it gets the same overrides
		var lobby_args : Array[String] = Main.main.configuration.lobby_args
		lobby_args.insert(0, "res://tests/harness/harness.tscn")
		lobby_args.append("--harness-lobby")
		if use_demo:
			lobby_args.append("--harness-demo")
		if use_moving:
			lobby_args.append("--harness-moving")
		if no_lagcomp:
			lobby_args.append("--harness-no-lagcomp")
	Main.open_mode(P2PHostMode.new())
	var mode : P2PHostMode = Main.mode
	mode.my_member_data.name = "HostPlayer"
	mode.lobby_name = "HarnessLobby"
	mode.host_with_lan()
	if not await wait_until(func(): return mode.state == P2PHostMode.CLIENT_STATE.CONNECTED_TO_LOBBY):
		return fail("host never connected to its lobby")
	if not await wait_until(func(): return mode.lobby.has_authority):
		return fail("host never got authority")
	if use_noray:
		if not await wait_until(func(): return mode.lobby.stats.game_id != ""):
			return fail("lobby never published a noray game id")
		log_line("GAME_ID " + mode.lobby.stats.game_id)
	log_line("HOST_READY authority=%s" % mode.lobby.has_authority)
	if not await wait_until(func(): return mode.lobby.members.size() >= 2):
		return fail("client never joined")
	log_line("MEMBERS " + str(mode.lobby.get_serialized_members()))
	mode.lobby.trigger_request_begin_game()
	if not await wait_until(func(): return mode.lobby.game_manager.in_game):
		return fail("game never started")
	await get_tree().create_timer(2.0).timeout
	log_line("GAME_STARTED " + describe_game())
	if use_moving:
		await moving_target_run(1.7)
		await get_tree().create_timer(3.0).timeout
		log_line("MOVING_RESULT health=%d" % Main.mode.get_game().spawner.local_player.health)
	elif use_demo: #the client moves for a second and settles, then compare what this peer sees
		await get_tree().create_timer(7.0).timeout
		log_line("DEMO_POS " + describe_game())
	mode.lobby.trigger_request_end_game()
	if not await wait_until(func(): return not mode.lobby.game_manager.in_game):
		return fail("game never ended")
	log_line("GAME_ENDED")
	await get_tree().create_timer(1.0).timeout
	mode.shut_down_lobby()
	await get_tree().create_timer(1.0).timeout
	log_line("DONE")
	get_tree().quit(0)


func run_client() -> void:
	Main.open_mode(ClientMode.new())
	var mode : ClientMode = Main.mode
	mode.my_member_data.name = "ClientPlayer"
	if use_noray:
		mode.join_noray_lobby(game_id)
	else:
		mode.direct_join_lobby("127.0.0.1", join_port)
	if not await wait_until(func(): return mode.state == ClientMode.CLIENT_STATE.CONNECTED_TO_LOBBY):
		return fail("client never connected to lobby")
	if not await wait_until(func(): return mode.lobby.members.size() >= 2):
		return fail("client never saw membership")
	log_line("JOINED members=" + str(mode.lobby.get_serialized_members()))
	if not await wait_until(func(): return mode.lobby.game_manager.in_game):
		return fail("game never started")
	await get_tree().create_timer(2.0).timeout
	log_line("GAME_STARTED " + describe_game())
	if use_moving:
		await moving_target_run(1.7)
		await get_tree().create_timer(3.0).timeout
	elif use_demo:
		await fire_pulse(Vector2.UP) #miss: nothing is above the client
		await get_tree().create_timer(0.5).timeout
		await fire_pulse(Vector2.LEFT) #hit: the host's player stands 100 px to the left
		await get_tree().create_timer(0.8).timeout
		await hold_move_right_and_measure()
		await get_tree().create_timer(2.0).timeout
		log_line("DEMO_POS " + describe_game())
	if not await wait_until(func(): return not mode.lobby.game_manager.in_game):
		return fail("game never ended")
	log_line("GAME_ENDED")
	await get_tree().create_timer(1.0).timeout
	log_line("DONE")
	get_tree().quit(0)
