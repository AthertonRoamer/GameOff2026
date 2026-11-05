class_name NightShiftLevel
extends Node2D

##The world a round is played in, shared by the game (game.tscn) and the playground: the facility map, the darkness over it, the projectiles,
##the facility's shared state (FacilityControl) and the utility room consoles. It knows nothing about lobbies or how players are made:
##the scene that owns it puts players into `actors` and tells it how to find a peer's player (player_lookup), which the lobby needs to check
##that someone asking to work the doors is really standing at the door console.

const DEBUG_SETTINGS : Array[StringName] = [&"can_toggle_darkness"] #turned off by DebugRemover

const CONSOLE_REACH_SLACK : float = 1.5 #the lobby's view of a player can be a few ticks behind, so its reach check is a little looser

@export var spawn_room : String = "ring" #players start in the middle of this room

@export_group("Debug")
@export var can_toggle_darkness : bool = false #N turns the darkness on and off (only on this peer)

@onready var facility : FacilityMap = $FacilityMap
@onready var darkness : CanvasModulate = $Darkness
@onready var projectiles : ProjectileManager = $ProjectileLayer/ProjectileManager
@onready var control : FacilityControl = $FacilityControl
@onready var consoles : UtilityConsoles = $UtilityConsoles

##(peer_id : int) -> Player, or null. Set by the scene that spawns the players.
var player_lookup : Callable = Callable()

var actors : Node2D:
	get: return facility.actors


func _ready() -> void:
	#the map builds itself in its own _ready, before this one
	consoles.build()
	control.can_operate = _can_operate


func spawn_position() -> Vector2:
	return facility.room_center_px(spawn_room)


func _can_operate(peer_id : int, function : String) -> bool:
	if not player_lookup.is_valid():
		return true
	var player : Player = player_lookup.call(peer_id)
	return player != null and player.is_alive() and consoles.is_at_console(function, player.global_position, CONSOLE_REACH_SLACK)


func _unhandled_key_input(event : InputEvent) -> void:
	if can_toggle_darkness and event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_N:
		darkness.visible = not darkness.visible
