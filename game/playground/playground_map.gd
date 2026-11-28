class_name PlaygroundMap
extends Node2D

##A single-player testing ground: the same Level as the game (game/level/night_shift_level.tscn) with one player in the guard skin and the HUD.
##No lobby and no network: netfox's clock is started offline, so the player's rollback tick, input and interpolation run exactly as they do in a
##game, and the local peer is the lobby, so door requests go through FacilityControl just like in a game.
##  WASD move, shift runs (and holsters the gun), H draws or holsters the gun (the torso follows the mouse, the legs follow the movement), left mouse fires the drawn gun (1-4 or the wheel pick the slot),
##  F turns the flashlight on and off.
##Doors are open at the start (they need power to stay shut) and cannot be worked by hand. The Door Control room has a control panel: stand next to
##it and press E to open its screen, a minimap of the facility where a click on a door opens or closes it. E or Esc leaves the screen.
##Command line (after --), for screenshots and checks:  --shot=<png> [--press=<action>] [--hold=<seconds>] [--aim=dx,dy] [--at=x,y] [--flash=off] [--dark=off]
##  [--panel=1] [--toggle=<door index>,<door index>] [--close]  presses an input action for a while, aims at a point on screen, takes a screenshot and prints what the player did.
##  --panel=1 walks the player to the panel and opens its screen; --toggle clicks those doors on the screen, like a mouse would.
##  --generator=1 holds E on the nearest generator until it starts and prints the power where the player stands (--mid=<png> takes a picture half way);
##  --map=1 opens the full map (as the map key does), zoomed out, before the picture.
##  --exit=<exit id> plays an intruder who knows that target exit (the full map outlines it).
##  --relics=<room>,<room> outlines those rooms on the full map as if relics had started in them (only treasure rooms count).
##  --lights=<room>,<room> switches those rooms' ceiling lights on at the start (as the console would), and starts every generator so there is power for them.
##  --turrets=1 starts every generator and switches every turret on. --role=<name> plays that role (game/roles/<name>.tres): an intruder's (--role=infiltrator) is shot at.

const PLAYER_SCENE : PackedScene = preload("res://game/player/player.tscn")

@export var camera_zoom : float = 2.0

@onready var level : NightShiftLevel = $Level
@onready var hud : CanvasLayer = $PlayerHud

var player : Player
var facility : FacilityMap
var _shots : int = 0
var _args : Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	facility = level.facility
	if await NetworkTime.start() != OK: #a coroutine: on the offline peer, which counts as the server, it is done at once
		push_warning("PlaygroundMap: NetworkTime did not start, the player will not move")
	player = PLAYER_SCENE.instantiate()
	player.player_name = "Guard"
	player.hitscan_manager = level.hitscan
	player.projectile_manager = level.projectiles #the gun spawns its bullets here; walls and closed doors stop them
	if _args.has("role"): #play this role (a file in game/roles): an intruder's is shot at by the turrets
		var role : Role = load("res://game/roles/%s.tres" % String(_args["role"])) as Role
		if role != null:
			player.role = role
			role.apply(player)
	hud.bind_player(player)
	hud.bind_hitscan(level.hitscan)
	hud.bind_map(level.facility)
	hud.bind_power(level.power)
	level.actors.add_child(player)
	player.input.flashlight_on = String(_args.get("flash", "on")) != "off"
	level.player_lookup = func(_peer_id : int) -> Player: return player
	player.position = level.spawn_position()
	if _args.has("at"):
		var at : PackedStringArray = String(_args["at"]).split(",")
		player.position = Vector2(float(at[0]), float(at[1]))
	player.set_active(true)
	level.darkness.visible = String(_args.get("dark", "on")) != "off"
	PixelArt.enabled = String(_args.get("pixel", "off")) == "on"
	player.camera.zoom = Vector2.ONE * float(_args.get("zoom", camera_zoom))
	player.shot_fired.connect(func() -> void: _shots += 1)
	level.blood.players = func() -> Array: return [player]
	level.hitscan.targets = func() -> Array: return [player] #(a turret's shot is traced against the players)
	level.hitscan.can_hit = func(target : Node) -> bool: return target.is_alive()
	level.hitscan.shot_hit.connect(func(shot : Dictionary, target : Node) -> void: target.take_damage(shot["damage"], shot["direction"]))
	level.turrets.players = func() -> Array: return [player]
	player.damaged.connect(level.blood.on_player_damaged.bind(player))
	player.died.connect(level.blood.on_player_died.bind(player), CONNECT_DEFERRED)
	var sight : PlayerSight = PlayerSight.new() #draws the rooms' ceiling lights where the player can see them, as in a game
	sight.name = "PlayerSight"
	add_child(sight)
	sight.ambient = level.darkness.color
	sight.players = func() -> Array: return [player]
	sight.local_player = func() -> Player: return player
	sight.room_lights = level.lights
	level.blood.sight = sight.visibility #blood is seen only in the view, as in a game
	if _args.has("exit"): #play an attacker who knows the target exit: the full map outlines it
		var chooser : DesignatedExitChooser = DesignatedExitChooser.new()
		chooser.set_designated(String(_args["exit"]))
		add_child(chooser)
		hud.bind_exit(chooser)
		hud.map_screen.exit_needs_intruder = false #(the playground's player has no role)
	if _args.has("relics"): #as if relics had been placed in these rooms at the start
		var at : PackedVector2Array = PackedVector2Array()
		for room : String in String(_args["relics"]).split(","):
			at.append(facility.to_global(facility.room_center_px(room)))
		hud.map_screen.mark_relic_rooms(at)
	if _args.has("lights"):
		for generator : Generator in level.power.generators: #(with no power they would be switched straight off again)
			level.power.set_generator(generator, Generator.State.RUNNING)
		for room : String in String(_args["lights"]).split(","):
			level.control.set_light_now(facility.light_of_room(room), true)
	if _args.has("turrets"): #every generator running and every turret switched on (as the console would)
		for generator : Generator in level.power.generators:
			level.power.set_generator(generator, Generator.State.RUNNING)
		for index in level.control.turret_count():
			level.control.set_turret_now(index, true) #(a request would be refused: the player is not at the console)
	if _args.has("shot"):
		_run_check()


##Screenshot mode: optionally aim the mouse, hold an action, then save a picture and report.
func _run_check() -> void:
	if _args.has("aim"): #a direction like 1,0 (right) or 0,-1 (up). The input is paused so the aim sticks; the real mouse cannot be driven from here
		var aim : PackedStringArray = String(_args["aim"]).split(",")
		player.input.active = false
		player.input.aim = player.global_position + Vector2(float(aim[0]), float(aim[1])) * 100.0
		player.inventory.drawn = true #the gun is out, as if H had been pressed
	await get_tree().create_timer(1.0).timeout
	if _args.has("aim2"): #turn on the spot: swing the aim round after the player has settled, and report what the feet do
		var aim2 : PackedStringArray = String(_args["aim2"]).split(",")
		player.input.aim = player.global_position + Vector2(float(aim2[0]), float(aim2[1])) * 100.0
		for step in 8:
			await get_tree().create_timer(0.15 if step < 7 else 0.6).timeout
			if step == 1 and _args.has("mid"): #a picture partway through the first step
				get_viewport().get_texture().get_image().save_png(String(_args["mid"]))
			print("PLAYGROUND turn t=%d legs=%s legs_deg=%.0f torso_deg=%.0f torso_frame=%d speed=%.1f" % [step, player.skin.legs.animation, rad_to_deg(player.skin.legs.rotation), rad_to_deg(player.skin.torso.rotation), player.skin.torso.frame, player.skin.torso.speed_scale])
	if _args.has("panel"): #stand at the panel and press E
		var panel : ControlPanel = level.consoles.panel_for("doors")
		player.teleport(panel.position + Vector2(0.0, 44.0))
		await get_tree().create_timer(0.4).timeout
		print("PLAYGROUND panel in reach=%s prompt=\"%s\" doors_open=%d of %d" % [panel.is_in_reach(player.global_position), hud.interact_prompt.text, facility.doors.filter(func(d : FacilityDoor) -> bool: return d.state == FacilityDoor.State.OPEN).size(), facility.doors.size()])
		player.interactor.use(panel)
		var screen : DoorMapScreen = panel.screen
		await get_tree().create_timer(0.3).timeout
		if _args.has("toggle"): #click doors on the screen by their position on it
			for index : String in String(_args["toggle"]).split(","):
				var door : FacilityDoor = facility.doors[int(index)]
				var click_at : Vector2 = screen.screen_position_of(door)
				var found : FacilityDoor = screen.door_at(click_at)
				print("PLAYGROUND click door %s at %s hits door %s" % [index, click_at, found.door_index if found != null else -1])
				if found != null:
					screen.toggle_door(found)
		await get_tree().create_timer(0.3).timeout #longer than FacilityControl's delay, so the doors have switched
		if _args.has("close"): #leave the screen again, as E would
			screen.close()
			await get_tree().create_timer(0.3).timeout
	if _args.has("generator"): #hold E on the nearest generator until it starts, then report the power where the player stands
		var nearest : Generator = null
		for generator : Generator in level.power.generators:
			if nearest == null or generator.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position):
				nearest = generator
		Input.action_press("player_interact")
		player.interactor.start_hold(nearest)
		await get_tree().create_timer(nearest.hold_seconds(player) * 0.5).timeout
		if _args.has("mid"): #a picture with the bar half full
			get_viewport().get_texture().get_image().save_png(String(_args["mid"]))
		await get_tree().create_timer(nearest.hold_seconds(player) * 0.5 + 0.3).timeout
		Input.action_release("player_interact")
		var region : String = facility.region_at(player.global_position)
		print("PLAYGROUND generator %s state=%s region=%s available=%.1f capacity=%.1f" % [nearest.name, Generator.State.keys()[nearest.state], region, level.power.available(region), level.power.capacity(region)])
	if _args.has("map"): #the full map, as the map key opens it, zoomed out to the whole facility
		hud.map_screen.open()
		hud.map_screen.map.fit_all()
		await get_tree().create_timer(0.3).timeout
	var start : Vector2 = player.position
	var action : String = String(_args.get("press", ""))
	if action != "":
		for each : String in action.split(","): #several actions can be held together, like player_right,player_run
			Input.action_press(each)
		await get_tree().create_timer(float(_args.get("hold", 1.0))).timeout
	get_viewport().get_texture().get_image().save_png(String(_args["shot"]))
	var door_states : Array = facility.doors.map(func(d : FacilityDoor) -> String: return FacilityDoor.State.keys()[d.state].substr(0, 1))
	print("PLAYGROUND doors=%s shots_fired=%d projectiles_in_flight=%d aim=%s drawn=%s use=%s interacting=%s active=%s flashlight=%s" % ["".join(door_states), _shots, level.projectiles.get_projectiles().size(), player.input.aim - player.global_position, player.inventory.drawn, player.input.use_item, player.input.interacting, player.input.active, player.flashlight.on])
	print("PLAYGROUND start=%s end=%s moved=%.1f legs=%s flip=%s speed_scale=%.1f torso=%s" % [start, player.position, player.position.distance_to(start),
		player.skin.legs.animation, player.skin.legs.flip_h, player.skin.legs.speed_scale, player.skin.torso.animation])
	for each : String in action.split(","):
		if each != "":
			Input.action_release(each)
	get_tree().quit()


func _parse_args() -> Dictionary:
	var result : Dictionary = {}
	for arg : String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts : PackedStringArray = arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1] if parts.size() > 1 else true
	return result
