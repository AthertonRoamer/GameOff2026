extends Node

# Scripted two-process smoke test for the multiplayer template. Drives the real host/join code without menus.
# Run one process with `-- --role host` and, once it prints HOST_READY, another with `-- --role client`.
# Output lines are prefixed so a runner script can grep them.

const MAIN_SCENE : PackedScene = preload("res://multiplayer_template/main/main.tscn")
const LOBBY_PORT : int = 5000
const TIMEOUT : float = 45.0
const MOVING_HIT_RADIUS : float = 16.0
const HITCH_SECONDS : float = 0.25

var role : String = "host"
var use_noray : bool = false
var use_rollback : bool = false
var use_demo : bool = false
var use_moving : bool = false #shooter and target run side by side, the shooter fires at where it sees the target
var use_combat : bool = false #the acting client kills the host's player with projectiles, then everyone checks the respawn
var use_hold : bool = false #the client, then the host, hold fire for 3 s each and report every shot event they saw
var use_night_shift : bool = false #the real game (game/game.tscn): the client works the door console; every peer reports doors, flashlight, interact
var no_lagcomp : bool = false #the lobby does not rewind targets, for comparison
var join_port : int = LOBBY_PORT #the client can join through a latency proxy by using another port
var players_expected : int = 2 #host waits for this many members before beginning
var client_name : String = "ClientPlayer"
var observer : bool = false #a client that takes no actions, it only reports what it sees
var rounds : int = 1 #how many games are played back to back in the same lobby
var leave_mode : bool = false #the acting client leaves gracefully shortly after the game starts
var kill_mode : bool = false #the runner kills the client process, the host must notice it is gone
var game_id : String = ""
var soak_seconds : float = 0.0 #--soak N: the real game runs N seconds with nothing scripted, to watch how sync holds up over time
var soak_move : bool = false #--soak-move: during a soak every player walks a square (inputs keep changing) instead of standing still
var main_node : Node


func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var idx : int = args.find("--role")
	if idx != -1 and idx + 1 < args.size():
		role = args[idx + 1]
	use_noray = args.has("--noray")
	use_moving = args.has("--moving")
	no_lagcomp = args.has("--no-lagcomp")
	use_combat = args.has("--combat")
	use_hold = args.has("--hold")
	use_demo = args.has("--demo") or use_moving or use_combat or use_hold or OS.get_cmdline_args().has("--harness-demo")
	idx = args.find("--soak")
	if idx != -1 and idx + 1 < args.size():
		soak_seconds = float(args[idx + 1])
	soak_move = args.has("--soak-move")
	use_night_shift = args.has("--night-shift") or OS.get_cmdline_args().has("--harness-night-shift") or soak_seconds > 0.0 #a soak plays the real game
	use_rollback = args.has("--rollback") or use_demo or use_night_shift
	idx = args.find("--join-port")
	if idx != -1 and idx + 1 < args.size():
		join_port = int(args[idx + 1])
	idx = args.find("--players")
	if idx != -1 and idx + 1 < args.size():
		players_expected = int(args[idx + 1])
	idx = args.find("--name")
	if idx != -1 and idx + 1 < args.size():
		client_name = args[idx + 1]
	idx = args.find("--rounds")
	if idx != -1 and idx + 1 < args.size():
		rounds = int(args[idx + 1])
	observer = args.has("--observer")
	leave_mode = args.has("--leave")
	kill_mode = args.has("--kill")
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
	if OS.has_environment("HARNESS_NO_LOG_LIMIT"): #print every netfox warning, like upstream netfox (for comparison)
		NetfoxLogger.rate_limit_seconds = 0.0
	if OS.has_environment("HARNESS_CLOCK"):
		clock_log_loop()
	if role == "host":
		await run_host()
	elif role == "client":
		await run_client()
	elif role == "lobby":
		await run_lobby_tweaks()


func apply_rollback_overrides(main : Node) -> void:
	#swaps in RollbackGameManager and either the probe game or the rollback demo configuration, without touching main.tscn.
	#Every process must do this, the lobby instance included
	if use_night_shift:
		main.configuration.game_manager_scene = load("res://multiplayer_template/rollback/rollback_game_manager.tscn")
		main.configuration.game_scene = load("res://game/game.tscn")
	elif use_demo:
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


var _last_frame_usec : int = 0
var _last_frame_tick : int = 0


func _process(delta : float) -> void:
	#a frame that takes this long freezes the process: it delays clock replies and corrupts a time sync regardless of the network.
	#Measured both as Godot's delta and as wall time, in case the two disagree
	var now_usec : int = Time.get_ticks_usec()
	var wall : float = (now_usec - _last_frame_usec) / 1000000.0 if _last_frame_usec > 0 else 0.0
	_last_frame_usec = now_usec
	var ticks : int = NetworkTime.tick - _last_frame_tick
	_last_frame_tick = NetworkTime.tick
	if OS.has_environment("HARNESS_CLOCK") and ticks > 3 and ticks < 1000: #netfox ran several ticks in one frame to catch up (1000+: a clock reset)
		print("[%s] TICKBURST %d ticks in one frame at tick %d unix %.3f" % [role.to_upper(), ticks, NetworkTime.tick, Time.get_unix_time_from_system()])
	if delta > HITCH_SECONDS or wall > HITCH_SECONDS:
		var line : String = "HITCH %.0f ms (wall %.0f ms) at unix %.3f" % [delta * 1000.0, wall * 1000.0, Time.get_unix_time_from_system()]
		if role == "lobby": #the lobby instance's output is not captured, so it appends to a file the runner reads
			var path : String = OS.get_environment("TEMP") + "/godot_smoke/lobby_hitch.log"
			var file : FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
			if file != null:
				file.seek_end()
				file.store_line(line)
		else:
			print("[%s] %s" % [role.to_upper(), line])


func wait_game_started() -> bool:
	#the lobby reports in_game as soon as it begins, but a rollback game only starts later, on the agreed tick
	var game : Node = Main.mode.get_game()
	if game != null and ("started" in game or "started_at_tick" in game):
		var started : bool = await wait_until(func():
			var g : Node = Main.mode.get_game()
			return g != null and (g.get("started") == true or int(g.get("started_at_tick") if "started_at_tick" in g else -1) >= 0), 90.0)
		await get_tree().create_timer(1.0).timeout
		return started
	await get_tree().create_timer(2.0).timeout
	return true


func bandwidth_reset() -> void:
	var peer : ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null and peer.host != null:
		peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
		peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)


func perf_line(seconds : float) -> void:
	#what this process cost and sent since bandwidth_reset(): bytes per second on its own connection, and netfox's rollback workload
	var sent : float = 0.0
	var received : float = 0.0
	var peer : ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null and peer.host != null:
		sent = peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
		received = peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var rollback : String = "rollback info unavailable"
	if NetworkPerformance.is_enabled():
		rollback = "rollback ticks/frame %d, nodes/tick %.1f, loop %.2f ms" % [NetworkPerformance.get_rollback_ticks(), NetworkPerformance.get_rollback_nodes_simulated_per_tick(), NetworkPerformance.get_rollback_loop_duration_ms()]
	log_line("PERF sent %.1f kB/s, received %.1f kB/s, %s" % [sent / seconds / 1000.0, received / seconds / 1000.0, rollback])


func clock_log_loop() -> void:
	#once a second: wall clock, netfox tick, rtt and clock offsets, so peers' clocks can be compared at the same instant
	print("[%s] NETFOX sync_to_physics=%s tickrate=%d max_ticks_per_frame=%d" % [role.to_upper(), NetworkTime.sync_to_physics, NetworkTime.tickrate, NetworkTime.max_ticks_per_frame])
	var last_msec : int = Time.get_ticks_msec()
	while is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		var gap : int = Time.get_ticks_msec() - last_msec
		last_msec = Time.get_ticks_msec()
		if gap > 1500: #the 1 s timer fired late: this process was not running its frames
			print("[%s] CLOCKGAP %d ms at unix %.3f" % [role.to_upper(), gap, Time.get_unix_time_from_system()])
		print("[%s] CLOCK unix=%.3f tick=%d rtt_ms=%.0f offset_ms=%.1f remote_offset_ms=%.1f stretch=%.3f" % [role.to_upper(), Time.get_unix_time_from_system(), NetworkTime.tick, NetworkTime.remote_rtt * 1000.0, NetworkTime.clock_offset * 1000.0, NetworkTime.remote_clock_offset * 1000.0, NetworkTime.clock_stretch_factor])


func run_lobby_tweaks() -> void:
	#the lobby instance has no test logic of its own, but the moving-target scenario needs it to tolerate many hits and, optionally, to not rewind
	if use_night_shift:
		await night_shift_lobby()
		return
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


func hold_report(who : String) -> void:
	#holds the instant shot, then the projectile weapon, for 3 s each, aiming where nothing is. Reports every CONFIRMING event this process saw
	var game : Node = Main.mode.get_game()
	var me : Node2D = game.spawner.local_player
	me.input.test_aim = Vector2.UP
	me.fire_events.clear()
	me.alt_events.clear()
	Input.action_press("ui_accept")
	await get_tree().create_timer(3.0).timeout
	Input.action_release("ui_accept")
	await get_tree().create_timer(0.5).timeout
	Input.action_press("ui_focus_next")
	await get_tree().create_timer(3.0).timeout
	Input.action_release("ui_focus_next")
	await get_tree().create_timer(0.5).timeout
	log_line("HOLD_%s fire=%s" % [who.to_upper(), str(me.fire_events)])
	log_line("HOLD_%s alt=%s" % [who.to_upper(), str(me.alt_events)])


func alt_pulse(aim : Vector2) -> void:
	#one projectile: the tap is shorter than the cooldown
	var game : Node = Main.mode.get_game()
	game.spawner.local_player.input.test_aim = aim
	Input.action_press("ui_focus_next")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("ui_focus_next")


func combat_report() -> void:
	#every peer reports two moments as it sees them (peers start a moment apart on a bad connection, so no fixed times):
	#the victim (the host's player, who respawns at 400,400) is dead, then it is alive again. A peer that never sees it gives up after 20 s.
	var game : Node = Main.mode.get_game()
	var victim : Node = null
	for player in game.spawner.players.values():
		if player.spawn_position == Vector2(400, 400):
			victim = player
	await wait_until(func(): return victim.health <= 0, 20.0)
	await get_tree().create_timer(0.5).timeout
	log_line("COMBAT_DEAD " + describe_game())
	await wait_until(func(): return victim.is_alive() and victim.health > 0, 20.0)
	await get_tree().create_timer(1.0).timeout
	log_line("COMBAT_RESPAWNED " + describe_game())
	await get_tree().create_timer(1.0).timeout


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
		lobby_args.append_array(["--log-file", OS.get_environment("TEMP") + "/godot_smoke/lobby.log"]) #its stdout isn't captured otherwise
		if use_demo:
			lobby_args.append("--harness-demo")
		if use_night_shift:
			lobby_args.append("--harness-night-shift")
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
	if not await wait_until(func(): return mode.lobby.members.size() >= players_expected):
		return fail("not all players joined")
	log_line("MEMBERS " + str(mode.lobby.get_serialized_members()))
	for round_number in range(1, rounds + 1):
		if round_number > 1:
			await get_tree().create_timer(1.5).timeout
		mode.lobby.trigger_request_begin_game()
		if not await wait_until(func(): return mode.lobby.game_manager.in_game):
			return fail("game never started")
		if not await wait_game_started():
			return fail("game never really started")
		if round_number > 1:
			await get_tree().create_timer(1.0).timeout
			log_line("ROUND_%d POS %s" % [round_number, describe_game()])
		else:
			log_line("GAME_STARTED " + describe_game())
			bandwidth_reset()
			await run_host_scenario()
		mode.lobby.trigger_request_end_game()
		if not await wait_until(func(): return not mode.lobby.game_manager.in_game):
			return fail("game never ended")
		log_line("GAME_ENDED")
	await get_tree().create_timer(1.0).timeout
	mode.shut_down_lobby()
	await get_tree().create_timer(1.0).timeout
	log_line("DONE")
	get_tree().quit(0)


##Night shift (the real game), lobby side: once the game runs, wait a while (so the client can first ask from out of reach, which must be
##refused), then move every player to the door console with the rollback-safe teleport, as the lobby is the only one that may.
func night_shift_lobby() -> void:
	if not await wait_until(_night_shift_running, 120.0):
		return
	await get_tree().create_timer(4.0).timeout
	var game : Game = Main.mode.get_game()
	var panel : ControlPanel = game.level.consoles.panel_for("doors")
	var i : int = 0
	for player : Player in game.spawner.players.values():
		player.teleport(panel.position + Vector2(-20.0 + 40.0 * i, 44.0))
		i += 1


func _night_shift_running() -> bool:
	var game : Node = Main.mode.get_game() if Main.mode != null else null
	return game is Game and game.spawner.players.size() >= 2 and game.spawner.players.values()[0].input.active


##Night shift, every player peer: records the tick each door changes on, so the peers can be compared.
func night_shift_watch_doors(game : Game) -> Dictionary:
	var changes : Dictionary = {}
	for door : FacilityDoor in game.level.facility.doors:
		door.state_changed.connect(func(state : FacilityDoor.State) -> void: changes[door.door_index] = "%s@%d" % [FacilityDoor.State.keys()[state], NetworkTime.tick])
	return changes


func night_shift_report(game : Game, changes : Dictionary) -> void:
	var states : String = "".join(game.level.facility.doors.map(func(d : FacilityDoor) -> String: return FacilityDoor.State.keys()[d.state].substr(0, 1)))
	var others : Array = []
	for id in game.spawner.players:
		var p : Player = game.spawner.players[id]
		others.append("%d:flash=%s,interacting=%s,torso=%s,pos=%.0f,%.0f" % [id, p.flashlight.on, p.input.interacting, p.skin.torso.animation, p.position.x, p.position.y])
	log_line("NS_RESULT doors=%s changes=%s players=[%s]" % [states, changes, " ".join(others)])


func night_shift_client() -> void:
	var game : Game = Main.mode.get_game()
	var changes : Dictionary = night_shift_watch_doors(game)
	var me : Player = game.spawner.local_player
	var panel : ControlPanel = game.level.consoles.panel_for("doors")
	game.level.control.request_door(game.level.facility.doors[1], FacilityDoor.State.CLOSED) #from the spawn, far from the console: the lobby must refuse
	log_line("NS_ASKED_FROM_SPAWN distance=%.0f" % me.global_position.distance_to(panel.global_position))
	if not await wait_until(func(): return panel.is_in_reach(me.global_position), 15.0):
		return fail("the lobby never moved the client to the console")
	await get_tree().create_timer(0.3).timeout
	log_line("NS_PROMPT \"%s\"" % game.player_hud.interact_prompt.text)
	me.interactor.use(panel)
	var screen : DoorMapScreen = panel.screen
	for index in [0, 3]:
		screen.toggle_door(game.level.facility.doors[index])
	me.input.flashlight_on = false
	await get_tree().create_timer(2.0).timeout
	night_shift_report(game, changes)
	await get_tree().create_timer(2.0).timeout


func night_shift_host() -> void:
	var game : Game = Main.mode.get_game()
	var changes : Dictionary = night_shift_watch_doors(game)
	await get_tree().create_timer(12.0).timeout
	night_shift_report(game, changes)


##Soak: nothing scripted, the game just runs for soak_seconds. With soak_move this peer's player walks a square, a side a second, so its
##input keeps changing; otherwise it stands still. Logs SOAK_DONE when the time is up.
func soak_run() -> void:
	var actions : Array[StringName] = [&"player_right", &"player_down", &"player_left", &"player_up"]
	var started_msec : int = Time.get_ticks_msec()
	var step : int = 0
	while (Time.get_ticks_msec() - started_msec) / 1000.0 < soak_seconds:
		if soak_move:
			for action in actions:
				Input.action_release(action)
			Input.action_press(actions[step % actions.size()])
			step += 1
		await get_tree().create_timer(1.0).timeout
	for action in actions:
		Input.action_release(action)
	log_line("SOAK_DONE seconds=%.0f move=%s %s" % [soak_seconds, soak_move, describe_game()])


func run_host_scenario() -> void:
	if soak_seconds > 0.0:
		await soak_run()
	elif use_night_shift:
		await night_shift_host()
	elif leave_mode or kill_mode:
		#a player disappears mid-game: the host must see it go, and its own game must keep running
		var game : Node = Main.mode.get_game()
		var started_msec : int = Time.get_ticks_msec()
		var gone : bool = await wait_until(func(): return game.spawner.players.size() <= players_expected - 1, 70.0)
		log_line("DEPARTURE_RESULT ok=%s players=%d seconds=%.1f" % [gone, game.spawner.players.size(), (Time.get_ticks_msec() - started_msec) / 1000.0])
		var me : Node2D = game.spawner.local_player
		var start_x : float = me.position.x
		Input.action_press("ui_right")
		await get_tree().create_timer(0.6).timeout
		Input.action_release("ui_right")
		await get_tree().create_timer(0.4).timeout
		log_line("HOST_STILL_RUNS moved=%.1f" % (me.position.x - start_x))
	elif use_combat:
		await combat_report()
	elif use_hold:
		await get_tree().create_timer(5.0).timeout #the client holds first
		await hold_report("host")
		await get_tree().create_timer(1.0).timeout
	elif use_moving:
		await moving_target_run(1.7)
		await get_tree().create_timer(3.0).timeout
		log_line("MOVING_RESULT health=%d" % Main.mode.get_game().spawner.local_player.health)
	elif use_demo: #the client moves for a second and settles, then compare what this peer sees
		await get_tree().create_timer(7.0).timeout
		log_line("DEMO_POS " + describe_game())
		perf_line(7.0)
	else: #nothing to do, but let the other peers report before the game is torn down
		await get_tree().create_timer(2.0).timeout


func run_client_scenario(mode : ClientMode) -> void:
	if soak_seconds > 0.0:
		await soak_run()
	elif use_night_shift:
		await night_shift_client()
	elif leave_mode:
		await get_tree().create_timer(1.0).timeout
		mode.leave_lobby()
		log_line("LEFT")
	elif kill_mode:
		await get_tree().create_timer(300.0).timeout #the runner kills this process
	elif use_hold:
		await hold_report("client")
		await get_tree().create_timer(5.0).timeout
	elif use_combat:
		if not observer:
			for shot in 3: #40 damage each: two shots hurt, the third kills
				await alt_pulse(Vector2.LEFT)
				await get_tree().create_timer(0.7).timeout
		await combat_report()
	elif observer:
		if use_demo:
			await get_tree().create_timer(7.0).timeout
			log_line("DEMO_POS " + describe_game())
			perf_line(7.0)
	elif use_moving:
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
		perf_line(7.0)


func run_client() -> void:
	Main.open_mode(ClientMode.new())
	var mode : ClientMode = Main.mode
	mode.my_member_data.name = client_name
	if use_noray:
		mode.join_noray_lobby(game_id)
	else:
		mode.direct_join_lobby("127.0.0.1", join_port)
	if not await wait_until(func(): return mode.state == ClientMode.CLIENT_STATE.CONNECTED_TO_LOBBY):
		return fail("client never connected to lobby")
	if not await wait_until(func(): return mode.lobby.members.size() >= players_expected):
		return fail("client never saw all members")
	log_line("JOINED members=" + str(mode.lobby.get_serialized_members()))
	for round_number in range(1, rounds + 1):
		if not await wait_until(func(): return mode.lobby.game_manager.in_game, 90.0):
			return fail("game never started")
		if not await wait_game_started():
			return fail("game never really started")
		if round_number > 1:
			await get_tree().create_timer(1.0).timeout
			log_line("ROUND_%d POS %s" % [round_number, describe_game()])
		else:
			log_line("GAME_STARTED " + describe_game())
			bandwidth_reset()
			await run_client_scenario(mode)
			if leave_mode:
				await get_tree().create_timer(1.0).timeout
				log_line("DONE")
				get_tree().quit(0)
				return
		if not await wait_until(func(): return not mode.lobby.game_manager.in_game, TIMEOUT + soak_seconds): #the host ends the game when its soak is over
			return fail("game never ended")
		log_line("GAME_ENDED")
	await get_tree().create_timer(1.0).timeout
	log_line("DONE")
	get_tree().quit(0)
