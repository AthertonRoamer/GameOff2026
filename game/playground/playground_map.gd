class_name PlaygroundMap
extends Node2D

##A single-player testing ground: the facility map with one player in the guard skin. No lobby and no network: netfox's clock is started
##offline, so the player's rollback tick, input and interpolation run exactly as they do in a game.
##  WASD move, shift runs (and holsters the gun), hold right mouse to draw the gun and aim (the torso follows the mouse, the legs follow the movement), left mouse fires the drawn gun (1-4 or the wheel pick the slot),
##  F turns the flashlight on and off, N turns the darkness (the CanvasModulate over the whole map, players included) on and off.
##Doors are open at the start (they need power to stay shut) and cannot be worked by hand. The Door Control room has a control panel: stand next to
##it and press E to open its screen, a minimap of the facility where a click on a door opens or closes it. E or Esc leaves the screen.
##Command line (after --), for screenshots and checks:  --shot=<png> [--press=<action>] [--hold=<seconds>] [--aim=dx,dy] [--at=x,y] [--flash=off] [--dark=off]
##  [--panel=1] [--toggle=<door index>,<door index>]  presses an input action for a while, aims at a point on screen, takes a screenshot and prints what the player did.
##  --panel=1 walks the player to the panel and opens its screen; --toggle clicks those doors on the screen, like a mouse would.

const PLAYER_SCENE : PackedScene = preload("res://game/player/player.tscn")
const INTERACT_TIME : float = 0.6
const PANEL_ROOM : String = "door_control" #the utility room whose function is "doors"

@export var spawn_room : String = "ring"
@export var camera_zoom : float = 2.0

@onready var facility : FacilityMap = $FacilityMap
@onready var darkness : CanvasModulate = $Darkness
@onready var projectiles : ProjectileManager = $ProjectileLayer/ProjectileManager

var player : Player
var panel : ControlPanel
var screen : DoorMapScreen
var _interact_left : float = 0.0
var _prompt : Label
var _args : Dictionary = {}


func _ready() -> void:
	_args = _parse_args()
	if await NetworkTime.start() != OK: #a coroutine: on the offline peer, which counts as the server, it is done at once
		push_warning("PlaygroundMap: NetworkTime did not start, the player will not move")
	player = PLAYER_SCENE.instantiate()
	player.player_name = "Guard"
	facility.actors.add_child(player)
	player.position = facility.room_center_px(spawn_room)
	if _args.has("at"):
		var at : PackedStringArray = String(_args["at"]).split(",")
		player.position = Vector2(float(at[0]), float(at[1]))
	player.projectile_manager = projectiles #the gun spawns its bullets here; walls (physics layer 2) stop them. The manager is on its own canvas layer, so the darkness does not dim the bullets, they glow
	player.set_active(true)
	player.flashlight.on = String(_args.get("flash", "on")) != "off"
	darkness.visible = String(_args.get("dark", "on")) != "off"
	player.camera.zoom = Vector2.ONE * float(_args.get("zoom", camera_zoom))
	_build_utility_room()
	if _args.has("shot"):
		_run_check()


func _process(delta : float) -> void:
	if _interact_left > 0.0:
		_interact_left -= delta
		if not screen.visible:
			player.interacting = _interact_left > 0.0
	var in_reach : bool = panel != null and not screen.visible and panel.is_in_reach(player.global_position)
	_prompt.visible = in_reach
	if in_reach:
		_prompt.position = (_prompt.get_viewport_rect().size - _prompt.size) / 2.0 + Vector2(0.0, _prompt.get_viewport_rect().size.y * 0.32)
	if Input.is_action_just_pressed("player_interact"):
		if screen.visible:
			screen.close()
		elif in_reach:
			_open_screen()


func _unhandled_key_input(event : InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_F:
			player.flashlight.toggle()
		KEY_N:
			darkness.visible = not darkness.visible


##The Door Control room's console, and the screen it opens. Doors start open: a door needs power to be held shut.
func _build_utility_room() -> void:
	for door in facility.doors:
		door.state = FacilityDoor.State.OPEN
	var rects : Array[Rect2] = facility.room_rects_px(PANEL_ROOM)
	panel = ControlPanel.new()
	panel.title = "Door control"
	panel.name = "DoorControlPanel"
	panel.position = Vector2(rects[0].position.x + 62.0, rects[0].position.y + 22.0) #against the north wall, left of the room's door
	facility.props_node.add_child(panel)
	var layer : CanvasLayer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	screen = DoorMapScreen.new()
	layer.add_child(screen)
	screen.closed.connect(_on_screen_closed)
	_prompt = Label.new()
	_prompt.text = "E   use the door control panel"
	_prompt.add_theme_font_size_override("font_size", 16)
	_prompt.add_theme_color_override("font_color", Color("#f2b544"))
	_prompt.add_theme_color_override("font_outline_color", Color("#06080c"))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.visible = false
	$Hint.add_child(_prompt)


func _open_screen() -> void:
	player.set_active(false) #the player stands at the console while the screen is up
	player.interacting = true
	screen.open(facility, player)


func _on_screen_closed() -> void:
	player.set_active(true)
	player.interacting = false


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
		player.position = panel.position + Vector2(0.0, 44.0)
		await get_tree().create_timer(0.4).timeout
		print("PLAYGROUND panel in reach=%s doors_open=%d of %d" % [panel.is_in_reach(player.global_position), facility.doors.filter(func(d : FacilityDoor) -> bool: return d.state == FacilityDoor.State.OPEN).size(), facility.doors.size()])
		_open_screen()
		await get_tree().create_timer(0.3).timeout
		if _args.has("toggle"): #click doors on the screen by their position on it
			for index : String in String(_args["toggle"]).split(","):
				var door : FacilityDoor = facility.doors[int(index)]
				var click_at : Vector2 = screen.screen_position_of(door)
				var found : FacilityDoor = screen.door_at(click_at)
				print("PLAYGROUND click door %s at %s hits door %s" % [index, click_at, found.door_index if found != null else -1])
				if found != null:
					screen.toggle_door(found)
		await get_tree().create_timer(0.2).timeout
	var start : Vector2 = player.position
	var action : String = String(_args.get("press", ""))
	if action != "":
		for each : String in action.split(","): #several actions can be held together, like player_right,player_run
			Input.action_press(each)
		await get_tree().create_timer(float(_args.get("hold", 1.0))).timeout
	get_viewport().get_texture().get_image().save_png(String(_args["shot"]))
	var door_states : Array = facility.doors.map(func(d : FacilityDoor) -> String: return FacilityDoor.State.keys()[d.state].substr(0, 1))
	print("PLAYGROUND doors=%s projectiles_in_flight=%d" % ["".join(door_states), projectiles.get_projectiles().size()])
	print("PLAYGROUND start=%s end=%s moved=%.1f legs=%s torso=%s" % [start, player.position, player.position.distance_to(start),
		player.skin.legs.animation, player.skin.torso.animation])
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
