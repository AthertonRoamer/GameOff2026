class_name Player
extends CharacterBody2D

const BLEED_BELOW : float = 0.5 #a player with less than this share of their starting health is bleeding
const DEAD_Z : int = -10 #z_index of a dead player: above the floor (FacilityMap.FLOOR_Z), below everything else

@export var speed : float = 250.0
@export var run_multiplier : float = 1.6 #top speed while shift is held and the player is moving
@export var sneak_multiplier : float = 0.5 #top speed while ctrl is held: a sneak is slow, but its steps make no sound
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
@export var starting_spare_rounds : int = 24 #ammunition besides the gun's magazine (the role sets it)
@export var stamina_max : float = 100.0 #running uses it up, and it comes back while the player does not run
@export var stamina_drain : float = 28.0 #per second of running
@export var stamina_regen : float = 16.0 #per second of not running
@export var stamina_recover_at : float = 25.0 #a player who ran out (winded) cannot run again until they have this much back

@onready var input : PlayerInput = $Input
@onready var inventory : Inventory = $Inventory
@onready var interpolator : TickInterpolator = $TickInterpolator
@onready var camera : Camera2D = $Camera2D
@onready var skin : NightShiftCharacter = $Skin
@onready var flashlight : Flashlight = $Skin/Torso/Lamp/Flashlight #the shoulder lamp's beam; the lamp is on the torso, so it follows the aim
@onready var interactor : PlayerInteractor = $Interactor #uses consoles and other interactables (local player only)
var footsteps : Footsteps: #makes a step sound as each foot comes down, on every peer (a getter, as the game connects to it before the player is in the tree)
	get: return $Footsteps

var lag_compensator : LagCompensator
var projectile_manager : ProjectileManager
var hitscan_manager : HitscanManager
var role : Role #public, the same on every peer. Null for a player spawned without one (the playground): the exported stats above are used
var team : int = Team.UNKNOWN #secret: only set where this peer may know it. Never use it in simulated gameplay, see Team
var hit_direction : Vector2 = Vector2.ZERO #the way the last shot that hit this player was travelling (synced with the health, so every peer plays the same flinch or death); zero if unknown
var _shown_health : float = starting_health #the health the skin last reacted to: a drop below it is a hit
@onready var _alive_layer : int = collision_layer #the body's collision while alive, which a dead player gives up
@onready var _alive_mask : int = collision_mask
var stamina : float = stamina_max #rollback state, with winded
var winded : bool = false
var died_at_msec : int = 0 #when this peer saw the player fall (the lobby's is the one that decides how long a medic has to bring them back)
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
signal reload_started(gun : Gun) #a reload began (on every peer: the reload is part of the synced state)
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
	if role != null:
		skin.use_skin(role.skin, role.legs_tint)
	footsteps.use_role(role)
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
##reset_tick: the tick the new role's ammunition starts on, the same on every peer (see Inventory.set_items).
func change_role(new_role : Role, reset_tick : int = -1) -> void:
	role = new_role
	if new_role == null:
		return
	new_role.apply(self)
	skin.use_skin(new_role.skin, new_role.legs_tint)
	footsteps.use_role(new_role)
	_derive_movement()
	inventory.set_items(starting_items, reset_tick)

##The skin falls according to where the killing shot came from, measured against the way the player faces (0 is from the front, positive from the right).
func _on_died() -> void:
	died_at_msec = Time.get_ticks_msec()
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


var _was_reloading : bool = false


func _process(_delta : float) -> void:
	#The body no longer turns to face the mouse: the skin turns its own legs (to the way it moves) and torso (to the aim). The gun stays out.
	var aim_direction : Vector2 = (input.aim - global_position).normalized() if input.aim != Vector2.ZERO and not input.interacting else Vector2.ZERO #(at a console the player does not turn: the skin keeps its facing)
	skin.update_visual(velocity, aim_direction, is_aiming() and not is_barrel_blocked(aim_direction), is_running(), input.interacting, inventory.active_slot, _reload_seconds(), sneak_multiplier if is_sneaking() else 1.0)
	var reloading : bool = inventory.is_reloading()
	if reloading and not _was_reloading and inventory.active_item is Gun:
		reload_started.emit(inventory.active_item)
	_was_reloading = reloading
	if flashlight.on != input.flashlight_on: #the flashlight is part of the synced input, so this shows every player's beam as they set it
		flashlight.on = input.flashlight_on


## How long the reload in progress takes (the skin plays its reload over that time), 0 when the gun is not being reloaded.
func _reload_seconds() -> float:
	var gun : Gun = inventory.active_item as Gun
	return gun.reload_seconds if gun != null and inventory.is_reloading() else 0.0


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
	_update_stamina(delta)
	var speed_now : float = velocity.length()
	if speed_now > 0.0:
		speed_now = max(speed_now - friction * delta, 0.0)
		velocity = velocity.normalized() * speed_now

	var top_speed : float = speed * (run_multiplier if is_running() else sneak_multiplier if is_sneaking() else 1.0)
	var accel_step : Vector2 = input.movement * acceleration * delta
	if (velocity + accel_step).length() <= top_speed:
		velocity += accel_step
	elif input.movement != Vector2.ZERO:
		velocity = input.movement * top_speed

	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor


##Running costs stamina; out of it the player is winded and walks until some of it is back.
func _update_stamina(delta : float) -> void:
	if is_running():
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		if stamina <= 0.0:
			winded = true
	else:
		stamina = minf(stamina + stamina_regen * delta, stamina_max)
		if winded and stamina >= stamina_recover_at:
			winded = false


##Shift held while moving, with stamina to do it on. Running holsters the gun (Inventory), and it comes back out when the run stops. Sneaking wins over running.
func is_running() -> bool:
	return input.run and not input.sneak and input.movement != Vector2.ZERO and not winded


##Ctrl held: the player walks slower (sneak_multiplier) and their footsteps make no sound (see Footsteps). Part of the synced input, so every peer agrees.
func is_sneaking() -> bool:
	return input.sneak


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


## For every player but the local one (see PlayerSight): their flashlight beam and glow are drawn by PlayerSight, inside the local player's view only, not lit by the scene.
func paint_flashlight_in_view() -> void:
	flashlight.paint_instead()


## Whether the local player sees this player's muzzle flash (see PlayerSight).
func set_muzzle_seen(seen : bool) -> void:
	skin.set_muzzle_seen(seen)


## How much of this player the local player sees, 0 to 1 (see PlayerSight): the body and the name. Their lights are not hidden.
func set_body_seen(alpha : float, light : Color = Color.WHITE) -> void:
	skin.set_body_alpha(alpha, light)
	if name_display != null:
		name_display.modulate.a = alpha


## The lobby member this player belongs to: the spawner names every player after their member's id.
func member_id() -> int:
	return String(name).to_int()


func is_alive() -> bool:
	return health > 0
