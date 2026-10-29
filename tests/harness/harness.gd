extends Node

# Scripted two-process smoke test for the multiplayer template. Drives the real host/join code without menus.
# Run one process with `-- --role host` and, once it prints HOST_READY, another with `-- --role client`.
# Output lines are prefixed so a runner script can grep them.

const MAIN_SCENE : PackedScene = preload("res://multiplayer_template/main/main.tscn")
const LOBBY_PORT : int = 5000
const TIMEOUT : float = 45.0

var role : String = "host"
var main_node : Node


func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var idx : int = args.find("--role")
	if idx != -1 and idx + 1 < args.size():
		role = args[idx + 1]
	main_node = MAIN_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(main_node) #must be /root/Main so RPC node paths match the lobby instance
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if role == "host":
		await run_host()
	else:
		await run_client()


func log_line(msg : String) -> void:
	print("[%s] %s" % [role.to_upper(), msg])


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
	var info : Array = []
	for p in game.players:
		if is_instance_valid(p):
			info.append("%s@%s" % [p.name, p.position])
	return "players=" + str(info)


func run_host() -> void:
	Main.open_mode(P2PHostMode.new())
	var mode : P2PHostMode = Main.mode
	mode.my_member_data.name = "HostPlayer"
	mode.lobby_name = "HarnessLobby"
	mode.host_with_lan()
	if not await wait_until(func(): return mode.state == P2PHostMode.CLIENT_STATE.CONNECTED_TO_LOBBY):
		return fail("host never connected to its lobby")
	if not await wait_until(func(): return mode.lobby.has_authority):
		return fail("host never got authority")
	log_line("HOST_READY authority=%s" % mode.lobby.has_authority)
	if not await wait_until(func(): return mode.lobby.members.size() >= 2):
		return fail("client never joined")
	log_line("MEMBERS " + str(mode.lobby.get_serialized_members()))
	mode.lobby.trigger_request_begin_game()
	if not await wait_until(func(): return mode.lobby.game_manager.in_game):
		return fail("game never started")
	await get_tree().create_timer(2.0).timeout
	log_line("GAME_STARTED " + describe_game())
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
	if not await wait_until(func(): return not mode.lobby.game_manager.in_game):
		return fail("game never ended")
	log_line("GAME_ENDED")
	await get_tree().create_timer(1.0).timeout
	log_line("DONE")
	get_tree().quit(0)
