extends Node

# Scripted two-process smoke test for the multiplayer template. Drives the real host/join code without menus.
# Run one process with `-- --role host` and, once it prints HOST_READY, another with `-- --role client`.
# Output lines are prefixed so a runner script can grep them.

const MAIN_SCENE : PackedScene = preload("res://multiplayer_template/main/main.tscn")
const LOBBY_PORT : int = 5000
const TIMEOUT : float = 45.0

var role : String = "host"
var use_noray : bool = false
var use_rollback : bool = false
var use_demo : bool = false
var game_id : String = ""
var main_node : Node


func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var idx : int = args.find("--role")
	if idx != -1 and idx + 1 < args.size():
		role = args[idx + 1]
	use_noray = args.has("--noray")
	use_demo = args.has("--demo") or OS.get_cmdline_args().has("--harness-demo")
	use_rollback = args.has("--rollback") or use_demo
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
		entries.append("%d=%.1f,%.1f" % [id, p.position.x, p.position.y])
	return "me=%d %s" % [multiplayer.get_unique_id(), ";".join(entries)]


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
	if use_demo: #the client moves for a second and settles, then compare what this peer sees
		await get_tree().create_timer(4.5).timeout
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
		mode.direct_join_lobby("127.0.0.1", LOBBY_PORT)
	if not await wait_until(func(): return mode.state == ClientMode.CLIENT_STATE.CONNECTED_TO_LOBBY):
		return fail("client never connected to lobby")
	if not await wait_until(func(): return mode.lobby.members.size() >= 2):
		return fail("client never saw membership")
	log_line("JOINED members=" + str(mode.lobby.get_serialized_members()))
	if not await wait_until(func(): return mode.lobby.game_manager.in_game):
		return fail("game never started")
	await get_tree().create_timer(2.0).timeout
	log_line("GAME_STARTED " + describe_game())
	if use_demo:
		await hold_move_right_and_measure()
		await get_tree().create_timer(2.0).timeout
		log_line("DEMO_POS " + describe_game())
	if not await wait_until(func(): return not mode.lobby.game_manager.in_game):
		return fail("game never ended")
	log_line("GAME_ENDED")
	await get_tree().create_timer(1.0).timeout
	log_line("DONE")
	get_tree().quit(0)
