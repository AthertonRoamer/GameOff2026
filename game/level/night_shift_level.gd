class_name NightShiftLevel
extends Node2D

##The world a round is played in, shared by the game (game.tscn) and the playground: the facility map, the darkness over it, the projectiles,
##the facility's shared state (FacilityControl) and the utility room consoles. It knows nothing about lobbies or how players are made:
##the scene that owns it puts players into `actors` and tells it how to find a peer's player (player_lookup), which the lobby needs to check
##that someone asking to work the doors is really standing at the door console.

const CONSOLE_REACH_SLACK : float = 1.5 #the lobby's view of a player can be a few ticks behind, so its reach check is a little looser

@export var spawn_room : String = "" #players start in the middle of this room. Empty, or a room the map no longer has: the map's biggest corridor (FacilityMap.start_room)

@onready var facility : FacilityMap = $FacilityMap
@onready var darkness : CanvasModulate = $Darkness
@onready var projectiles : ProjectileManager = $ProjectileLayer/ProjectileManager
@onready var hitscan : HitscanManager = $ProjectileLayer/HitscanManager #instant shots (above the darkness, like the bullets)
@onready var control : FacilityControl = $FacilityControl
@onready var consoles : UtilityConsoles = $UtilityConsoles
@onready var power : PowerGrid = $PowerGrid #the generators and what the doors and lights (and later cameras, turrets) cost to keep on
@onready var lights : RoomLightShapes = $RoomLights #where each room's ceiling light falls (switched by FacilityControl, drawn by PlayerSight)
@onready var blood : BloodSplats = $BloodSplats #the blood on the floor (above the floor, below the bodies)
@onready var sound : SoundSystem = $Sound #plays footsteps, shots and doors for the local player, shaped by the map (see game/audio)

##(peer_id : int) -> Player, or null. Set by the scene that spawns the players.
var player_lookup : Callable = Callable()

var actors : Node2D:
	get: return facility.actors


func _ready() -> void:
	#the map builds itself in its own _ready, before this one
	consoles.build()
	consoles.player_of = func(peer_id : int) -> Player: return player_lookup.call(peer_id) if player_lookup.is_valid() else null
	control.can_operate = _can_operate
	power.player_of = consoles.player_of
	power.build()


func spawn_position() -> Vector2:
	if spawn_room != "" and not facility.has_room(spawn_room):
		push_warning("NightShiftLevel: the map has no room \"%s\" to start in; starting in \"%s\" instead" % [spawn_room, facility.start_room()])
	return facility.room_center_px(facility.start_room(spawn_room))


func _can_operate(peer_id : int, function : String) -> bool:
	if not player_lookup.is_valid():
		return true
	var player : Player = player_lookup.call(peer_id)
	return player != null and player.is_alive() and consoles.is_at_console(function, player.global_position, CONSOLE_REACH_SLACK) and consoles.is_occupant(peer_id, function)

