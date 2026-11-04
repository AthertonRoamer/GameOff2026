class_name PlaygroundMap
extends Node2D

##A single-player testing ground: the facility map with one player in the guard skin. No lobby and no network: netfox's clock is started
##offline, so the player's rollback tick, input and interpolation run exactly as they do in a game.
##  WASD move, the mouse aims (the torso follows the mouse, the legs follow the movement), E opens and closes the nearest gate.
##Command line (after --), for screenshots and checks:  --shot=<png> [--press=<action>] [--hold=<seconds>] [--aim=dx,dy] [--at=x,y]
##  presses an input action for a while, aims at a point on screen, takes a screenshot and prints what the player did.

const PLAYER_SCENE : PackedScene = preload("res://game/player/player.tscn")
const INTERACT_RANGE : float = 56.0 #about 1.3 m
const INTERACT_TIME : float = 0.6

@export var spawn_room : String = "ring"
@export var camera_zoom : float = 2.0

@onready var facility : FacilityMap = $FacilityMap

var player : Player
var _interact_left : float = 0.0
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
	player.set_active(true)
	player.camera.zoom = Vector2.ONE * float(_args.get("zoom", camera_zoom))
	if _args.has("shot"):
		_run_check()


func _process(delta : float) -> void:
	if _interact_left > 0.0:
		_interact_left -= delta
		player.interacting = _interact_left > 0.0
	if Input.is_action_just_pressed("player_interact"):
		_use_nearest_gate()


func _use_nearest_gate() -> void:
	var nearest : FacilityDoor = null
	var best : float = INTERACT_RANGE
	for door in facility.doors:
		var d : float = door.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			nearest = door
	_interact_left = INTERACT_TIME
	player.interacting = true
	if nearest != null and nearest.state != FacilityDoor.State.LOCKED:
		nearest.state = FacilityDoor.State.OPEN if nearest.state == FacilityDoor.State.CLOSED else FacilityDoor.State.CLOSED


##Screenshot mode: optionally aim the mouse, hold an action, then save a picture and report.
func _run_check() -> void:
	if _args.has("aim"): #a direction like 1,0 (right) or 0,-1 (up). The input is paused so the aim sticks; the real mouse cannot be driven from here
		var aim : PackedStringArray = String(_args["aim"]).split(",")
		player.input.active = false
		player.input.aim = player.global_position + Vector2(float(aim[0]), float(aim[1])) * 100.0
	await get_tree().create_timer(1.0).timeout
	if _args.has("open"): #press E next to a gate first
		_use_nearest_gate()
		await get_tree().create_timer(0.3).timeout
	var start : Vector2 = player.position
	var action : String = String(_args.get("press", ""))
	if action != "":
		Input.action_press(action)
		await get_tree().create_timer(float(_args.get("hold", 1.0))).timeout
	get_viewport().get_texture().get_image().save_png(String(_args["shot"]))
	var gate_states : Array = facility.doors.filter(func(d : FacilityDoor) -> bool: return d.global_position.distance_to(start) < INTERACT_RANGE).map(func(d : FacilityDoor) -> String: return FacilityDoor.State.keys()[d.state])
	print("PLAYGROUND gates_near_start=%s" % [gate_states])
	print("PLAYGROUND start=%s end=%s moved=%.1f legs=%s torso=%s" % [start, player.position, player.position.distance_to(start),
		player.skin.legs.animation, player.skin.torso.animation])
	if action != "":
		Input.action_release(action)
	get_tree().quit()


func _parse_args() -> Dictionary:
	var result : Dictionary = {}
	for arg : String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts : PackedStringArray = arg.substr(2).split("=", true, 1)
			result[parts[0]] = parts[1] if parts.size() > 1 else true
	return result
