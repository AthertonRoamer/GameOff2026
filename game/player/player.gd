class_name Player
extends CharacterBody2D

@export var speed : float = 250.0
@export var run_multiplier : float = 1.6 #top speed while shift is held and the player is moving
@export var acceleration : float = 500.0
@export var acceleration_time : float = .025
@export var set_acceleration_from_time : bool = true
@export var friction : float = 2500.0
@export var slow_down_time : float = .1
@export var set_friction_from_slow_down_time : bool = true
@export var name_display : Label
@export var muzzle_distance : float = 28.0 #from the player's middle to the end of the barrel, in pixels: where bullets start and the flash is
@export var arm_extra : float = 14.0 #how far the hands reach past the barrel end, in pixels: a wall closer than muzzle_distance + this lowers the gun
@export var starting_items : Array[Item] = []

@onready var input : PlayerInput = $Input
@onready var inventory : Inventory = $Inventory
@onready var interpolator : TickInterpolator = $TickInterpolator
@onready var camera : Camera2D = $Camera2D
@onready var skin : NightShiftCharacter = $Skin
@onready var flashlight : Flashlight = $Skin/Torso/Lamp/Flashlight #the shoulder lamp's beam; the lamp is on the torso, so it follows the aim
@onready var interactor : PlayerInteractor = $Interactor #uses consoles and other interactables (local player only)

var lag_compensator : LagCompensator
var projectile_manager : ProjectileManager
var _teleport_to : Variant = null #a position the next tick moves the player to, see teleport()

var player_name : String = "":
	set(value):
		player_name = value
		if name_display:
			name_display.text = value

signal health_changed(h : float)
signal died
signal shot_fired #a gun fired: plays the skin's recoil and muzzle flash

@export var starting_health : float = 100.0
var health : float = starting_health:
	set(v):
		if v <= 0:
			health = 0
			die()
		else:
			health = v
		health_changed.emit(health)


func _ready() -> void:
	if set_friction_from_slow_down_time:
		friction = speed / slow_down_time
	if set_acceleration_from_time:
		acceleration = speed / acceleration_time
	camera.enabled = input.is_multiplayer_authority()
	died.connect(skin.die)
	shot_fired.connect(skin.play_shot)


func _process(_delta : float) -> void:
	#The body no longer turns to face the mouse: the skin turns its own legs (to the way it moves) and torso (to the aim). The gun stays out.
	var aim_direction : Vector2 = (input.aim - global_position).normalized() if input.aim != Vector2.ZERO else Vector2.ZERO
	skin.update_visual(velocity, aim_direction, is_aiming() and not is_barrel_blocked(aim_direction), is_running(), input.interacting)
	if flashlight.on != input.flashlight_on: #the flashlight is part of the synced input, so this shows every player's beam as they set it
		flashlight.on = input.flashlight_on


##Moves the player to a point. Setting position directly does not stick: the next tick restores it from the rollback history. This applies it
##inside the next tick instead, so it is recorded (and, on the lobby, sent to every peer like any other movement). Lobby or offline only.
func teleport(to : Vector2) -> void:
	_teleport_to = to


func _rollback_tick(delta : float, _tick : int, _is_fresh : bool) -> void:
	if _teleport_to != null:
		position = _teleport_to
		velocity = Vector2.ZERO
		_teleport_to = null
		interpolator.teleport()
	var speed_now : float = velocity.length()
	if speed_now > 0.0:
		speed_now = max(speed_now - friction * delta, 0.0)
		velocity = velocity.normalized() * speed_now

	var top_speed : float = speed * (run_multiplier if is_running() else 1.0)
	var accel_step : Vector2 = input.movement * acceleration * delta
	if (velocity + accel_step).length() <= top_speed:
		velocity += accel_step
	elif input.movement != Vector2.ZERO:
		velocity = input.movement * top_speed

	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor


##Shift held while moving. Drawing the gun (right mouse) while running drops you to a walk with the gun out.
func is_running() -> bool:
	return input.run and input.movement != Vector2.ZERO and not is_aiming()


##The active item (the gun) is out in the hands: chosen in the inventory, H holsters or draws it. A holstered gun cannot fire.
func is_aiming() -> bool:
	return inventory.drawn


##True when a wall or a closed door is within reach of the gun arms in this direction: the gun is lowered (the skin shows the arms down) and cannot
##fire, so the arms never poke through a wall or a door and no shot starts on the far side of one.
func is_barrel_blocked(direction : Vector2) -> bool:
	if direction.is_zero_approx() or not is_inside_tree():
		return false
	var to : Vector2 = global_position + direction.normalized() * (muzzle_distance + arm_extra)
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, to, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER)
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func set_active(active : bool) -> void:
	input.active = active


func take_damage(dmg : float) -> void:
	health -= dmg


func die() -> void:
	died.emit()
	set_active(false)


func is_alive() -> bool:
	return health > 0
