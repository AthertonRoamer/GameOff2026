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
@onready var power : PowerGrid = $PowerGrid #the generators and what the doors, lights, cameras and turrets cost to keep on
@onready var turrets : TurretSystem = $Turrets #the turrets: switched by FacilityControl, worked by the lobby
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
	control.can_work_by_hand = _can_work_door_by_hand
	control.operated.connect(consoles.beep_for) #a change made from a console beeps there, heard by whoever is near it
	consoles.beeped.connect(sound.on_console_beep)
	for door : FacilityDoor in facility.doors: #a technician opens and closes the door they stand by (DoorSwitch)
		var door_switch : DoorSwitch = DoorSwitch.new()
		door_switch.name = "DoorSwitch"
		door_switch.door = door
		door_switch.control = control
		door.add_child(door_switch)
	power.generator_switched.connect(sound.on_machine) #a generator starting is heard, and one running hums (before build: the ones running from the start hum too)
	power.generator_worked.connect(sound.on_generator_work) #and its starter grinds while someone holds E to start it, and a repair is heard
	turrets.player_of = consoles.player_of
	turrets.build() #(before the power: it sizes the turrets' switches, which the power counts)
	control.can_work_turret_by_hand = turrets.may_switch_by_hand #a technician switches the turret they stand by (TurretSwitch)
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



## Lobby: may this peer's player work this door by hand now (a living player whose role works doors, standing by it, see DoorSwitch)?
func _can_work_door_by_hand(peer_id : int, door : FacilityDoor) -> bool:
	if not player_lookup.is_valid():
		return true
	var player : Player = player_lookup.call(peer_id)
	if player == null or not player.is_alive() or not DoorSwitch.may_work(player):
		return false
	var door_switch : DoorSwitch = door.get_node_or_null("DoorSwitch")
	return door_switch != null and door_switch.is_in_reach(player.global_position, DoorSwitch.REACH_SLACK)
