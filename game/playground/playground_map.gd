class_name PlaygroundMap
extends Node2D

##A single-player testing ground: the same Level as the game (game/level/night_shift_level.tscn) with one player in the guard skin and the HUD.
##No lobby and no network: netfox's clock is started offline, so the player's rollback tick, input and interpolation run exactly as they do in a
##game, and the local peer is the lobby, so door requests go through FacilityControl just like in a game.
##  WASD move, shift runs (and holsters the gun), hold right mouse to draw the gun and aim (the torso follows the mouse, the legs follow the movement), left mouse fires the drawn gun (1-4 or the wheel pick the slot),
##  P turns the pixel art pass on and off (it covers the whole game, see game/effects/pixel_art.gd),
##  F turns the flashlight on and off, N turns the darkness on and off (the Level's can_toggle_darkness is on here).
##Doors are open at the start (they need power to stay shut) and cannot be worked by hand. The Door Control room has a control panel: stand next to
##it and press E to open its screen, a minimap of the facility where a click on a door opens or closes it. E or Esc leaves the screen.
##Command line (after --), for screenshots and checks:  --shot=<png> [--press=<action>] [--hold=<seconds>] [--aim=dx,dy] [--at=x,y] [--flash=off] [--dark=off]
##  [--panel=1] [--toggle=<door index>,<door index>] [--close]  presses an input action for a while, aims at a point on screen, takes a screenshot and prints what the player did.
##  --panel=1 walks the player to the panel and opens its screen; --toggle clicks those doors on the screen, like a mouse would.

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
	player.projectile_manager = level.projectiles #the gun spawns its bullets here; walls and closed doors stop them
	hud.bind_player(player)
	level.actors.add_child(player)
	player.input.flashlight_on = String(_args.get("flash", "on")) != "off"
	level.player_lookup = func(_peer_id : int) -> Player: return player
	player.position = level.spawn_position()
	if _args.has("at"):
		var at : PackedStringArray = String(_args["at"]).split(",")
		player.position = Vector2(float(at[0]), float(at[1]))
	player.set_active(true)
	level.darkness.visible = String(_args.get("dark", "on")) != "off"
	PixelArt.enabled = String(_args.get("pixel", "on")) != "off" #P turns the pixel art pass on and off
	player.camera.zoom = Vector2.ONE * float(_args.get("zoom", camera_zoom))
	player.shot_fired.connect(func() -> void: _shots += 1)
	if _args.has("shot"):
		_run_check()


##Screenshot mode: optionally aim the mouse, hold an action, then save a picture and report.
func _run_check() -> void:
	if _args.has("aim"): #a direction like 1,0 (right) or 0,-1 (up). The input is paused so the aim sticks; the real mouse cannot be driven from here
		var aim : PackedStringArray = String(_args["aim"]).split(",")
		player.input.active = false
		player.input.aim = player.global_position + Vector2(float(aim[0]), float(aim[1])) * 100.0
		player.input.aiming = true #the gun is drawn, as if the right mouse button were held
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
	var start : Vector2 = player.position
	var action : String = String(_args.get("press", ""))
	if action != "":
		for each : String in action.split(","): #several actions can be held together, like player_right,player_run
			Input.action_press(each)
		await get_tree().create_timer(float(_args.get("hold", 1.0))).timeout
	get_viewport().get_texture().get_image().save_png(String(_args["shot"]))
	var door_states : Array = facility.doors.map(func(d : FacilityDoor) -> String: return FacilityDoor.State.keys()[d.state].substr(0, 1))
	print("PLAYGROUND doors=%s shots_fired=%d projectiles_in_flight=%d aim=%s aiming=%s use=%s interacting=%s active=%s flashlight=%s" % ["".join(door_states), _shots, level.projectiles.get_projectiles().size(), player.input.aim - player.global_position, player.input.aiming, player.input.use_item, player.input.interacting, player.input.active, player.flashlight.on])
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
