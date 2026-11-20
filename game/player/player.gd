class_name Player
extends CharacterBody2D

const BLEED_BELOW : float = 0.5 #a player with less than this share of their starting health is bleeding
const DEAD_Z : int = -10 #z_index of a dead player: above the floor (FacilityMap.FLOOR_Z), below everything else

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
var role : Role #public, the same on every peer. Null for a player spawned without one (the playground): the exported stats above are used
var team : int = Team.UNKNOWN #secret: only set where this peer may know it. Never use it in simulated gameplay, see Team
var hit_direction : Vector2 = Vector2.ZERO #the way the last shot that hit this player was travelling (synced with the health, so every peer plays the same flinch or death); zero if unknown
var _shown_health : float = starting_health #the health the skin last reacted to: a drop below it is a hit
@onready var _alive_layer : int = collision_layer #the body's collision while alive, which a dead player gives up
@onready var _alive_mask : int = collision_mask
var debug_killed : bool = false #killed by a debug command (set where the kill runs, the lobby): the match counts a player like this as still in play, so it does not end over a test
var _teleport_to : Variant = null #a position the next tick moves the player to, see teleport()

var player_name : String = "":
	set(value):
		player_name = value
		if name_display:
			name_display.text = value

signal health_changed(h : float)
signal died
signal shot_fired #a gun fired: plays the skin's recoil and muzzle flash
signal damaged(direction : Vector2) #health went down from a shot going this way (on every peer: the health and the direction are synced together). BloodSplats listens

@export var starting_health : float = 50.0
var health : float = starting_health:
	set(v):
		if v <= 0:
			var already_dead : bool = health <= 0.0 #the health sync writes the same 0 every tick: dying has to happen once, not again each time
			health = 0
			if not already_dead:
				die()
		else:
			health = v
		health_changed.emit(health)


func _ready() -> void:
	_derive_movement()
	_shown_health = health #(its initial value came before starting_health was set: the first hit was not noticed)
	camera.enabled = input.is_multiplayer_authority()
	if name_display != null:
		name_display.visible = not input.is_multiplayer_authority() #the name is for the others: you do not see your own
	died.connect(_on_died)
	health_changed.connect(_on_health_changed)
	shot_fired.connect(skin.play_shot)


func _derive_movement() -> void:
	if set_friction_from_slow_down_time:
		friction = speed / slow_down_time
	if set_acceleration_from_time:
		acceleration = speed / acceleration_time


##Gives the player another role after they have spawned (debug): the new stats and items, at full health. Run it on every peer, roles are public.
func change_role(new_role : Role) -> void:
	role = new_role
	if new_role == null:
		return
	new_role.apply(self)
	_derive_movement()
	inventory.set_items(starting_items)

##The skin falls according to where the killing shot came from, measured against the way the player faces (0 is from the front, positive from the right).
func _on_died() -> void:
	_set_collidable(false)
	z_index = DEAD_Z #a body on the floor is under everything that stands on it
	skin.die(_hit_angle())


## A dead player is no obstacle: nothing collides with the body, and it collides with nothing, until it is back on its feet.
func _set_collidable(collidable : bool) -> void:
	collision_layer = _alive_layer if collidable else 0
	collision_mask = _alive_mask if collidable else 0


## Where the last shot came from, measured against the way the player faces: 0 is from the front, positive from the right, 180 from behind.
func _hit_angle() -> float:
	if hit_direction.is_zero_approx():
		return 0.0
	var facing : Vector2 = Vector2.from_angle(skin.torso.rotation - PI / 2.0) #the way the torso is turned: where the player aims
	return rad_to_deg(facing.angle_to(-hit_direction))


##Every health change, on every peer: a drop is a hit (a flinch and a puff of blood, the same everywhere as the direction is synced with the health).
##Health coming back to a dead player stands them up again: the skin gets up from its fall and the player can act.
func _on_health_changed(h : float) -> void:
	if h < _shown_health and not hit_direction.is_zero_approx():
		skin.hit(_hit_angle())
		damaged.emit(hit_direction)
	_shown_health = h
	if h > 0.0:
		debug_killed = false
		if skin.dead:
			skin.revive()
			_set_collidable(true)
			z_index = 0
			set_active(true)


## Debug (run where the player's state lives, the lobby; the health sync tells everyone else): kills the player as if shot from source_angle_deg round them
## (0 from the front, positive from the right), or brings a dead one back with full health.
func debug_kill(source_angle_deg : float = 0.0) -> void:
	debug_killed = true #so the match does not end over it (see Game._is_in_play)
	var facing : Vector2 = (input.aim - global_position).normalized() if input.aim != Vector2.ZERO else Vector2.UP
	take_damage(health, -facing.rotated(deg_to_rad(source_angle_deg))) #the shot travels towards the player, away from where it came from


func debug_revive() -> void:
	health = starting_health


func _process(_delta : float) -> void:
	#The body no longer turns to face the mouse: the skin turns its own legs (to the way it moves) and torso (to the aim). The gun stays out.
	var aim_direction : Vector2 = (input.aim - global_position).normalized() if input.aim != Vector2.ZERO else Vector2.ZERO
	skin.update_visual(velocity, aim_direction, is_aiming() and not is_barrel_blocked(aim_direction), is_running(), input.interacting, inventory.active_slot)
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


##Shift held while moving. Running holsters the gun (Inventory), and it comes back out when the run stops.
func is_running() -> bool:
	return input.run and input.movement != Vector2.ZERO


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


##from_direction: the way the shot was travelling (zero when there is none). It decides which death the skin plays if this kills, so it is set before the health changes.
func take_damage(dmg : float, from_direction : Vector2 = Vector2.ZERO) -> void:
	if not from_direction.is_zero_approx():
		hit_direction = from_direction.normalized()
	health -= dmg


func die() -> void:
	died.emit()
	set_active(false)


## Hurt badly enough to be losing blood: alive with less than half their starting health. The lobby drops a splat of blood for a bleeding player every few seconds.
func is_bleeding() -> bool:
	return health > 0.0 and health < starting_health * BLEED_BELOW


func is_alive() -> bool:
	return health > 0
