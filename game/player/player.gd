class_name Player
extends CharacterBody2D

@export var speed : float = 250.0
@export var acceleration : float = 500.0
@export var acceleration_time : float = .025
@export var set_acceleration_from_time : bool = true
@export var friction : float = 2500.0
@export var slow_down_time : float = .1
@export var set_friction_from_slow_down_time : bool = true
@export var name_display : Label
@export var muzzle_distance : float = 28.0 #from the player's middle to the end of the barrel, in pixels: where bullets start and the flash is
@export var starting_items : Array[Item] = []

@onready var input : PlayerInput = $Input
@onready var interpolator : TickInterpolator = $TickInterpolator
@onready var camera : Camera2D = $Camera2D
@onready var skin : NightShiftCharacter = $Skin
@onready var flashlight : Flashlight = $Skin/Torso/Flashlight #comes out of the front of the torso, so it follows the aim

var lag_compensator : LagCompensator
var projectile_manager : ProjectileManager
var interacting : bool = false #a local visual flag: plays the torso's interact animation while true

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
	skin.update_visual(velocity, aim_direction, true, false, interacting)


func _rollback_tick(delta : float, _tick : int, _is_fresh : bool) -> void:
	var speed_now : float = velocity.length()
	if speed_now > 0.0:
		speed_now = max(speed_now - friction * delta, 0.0)
		velocity = velocity.normalized() * speed_now

	var accel_step : Vector2 = input.movement * acceleration * delta
	if (velocity + accel_step).length() <= speed:
		velocity += accel_step
	elif input.movement != Vector2.ZERO:
		velocity = input.movement * speed

	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor


func set_active(active : bool) -> void:
	input.active = active


func take_damage(dmg : float) -> void:
	health -= dmg


func die() -> void:
	died.emit()
	set_active(false)


func is_alive() -> bool:
	return health > 0
