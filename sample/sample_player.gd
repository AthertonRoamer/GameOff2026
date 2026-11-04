#class_name Player
extends CharacterBody2D

var keys : int = 0

signal died

var level : CustomLevel

var active : bool = true #moving or listening for input

@export var primary_item : PrimaryItem


#region physics variables
@export_group("Walk")
@export var walk_max_speed : float = 250
@export var walk_accel : float = 500
var current_accel : float = walk_accel
var walk_direction : Vector2 = Vector2.ZERO

@export var walk_accel_time : float = .025
@export var set_walk_accel_from_time : bool = true

@export var dash_speed : float = 1000
@export var dash_time : float = 0.2
@export var dash_cooldown_time : float = 0.5
var dash_cooldown_time_elapsed : float = dash_cooldown_time
var dash_time_elapsed : float = 0
var dash_direction : Vector2
var dashing : bool = false


@export_group("Friction")
@export var current_slow_down_time : float = .1
@export var set_current_friction_from_slow_down_time : bool = true

var current_friction : float = 2500

#endregion 

signal health_changed(h : int)

var starting_health : float = 100
var health = starting_health:
	set(v):
		if v <= 0:
			health = 0
			die()
		else:
			health = v
		health_changed.emit(v)



func _ready() -> void:
	if primary_item:
		primary_item.add_to_entity(self)
	add_to_group("damageable")
	if set_current_friction_from_slow_down_time:
		#250 px/sec 250 px/sec / 1 sec = 250 px / sec /sec
		current_friction = walk_max_speed / current_slow_down_time
		#print("current friction: ", current_friction)
	if set_walk_accel_from_time:
		walk_accel = walk_max_speed / walk_accel_time
		#print("walk accel ", walk_accel)
	#set jump time from jump height and jump speed
	#px / (px/sec) = sec
		
	
func _input(event : InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("primary"):
		take_primary_action()
	elif event.is_action_pressed("secondary"):
		take_secondary_action()


func _physics_process(delta: float) -> void:
	if not active:
		return
		
	var new_rotation : float = (get_global_mouse_position() - global_position).angle() +(PI/2)
	rotation = new_rotation
	
	walk_direction = Vector2.ZERO
		
	if Input.is_action_pressed("walk_down"):
		walk_direction += Vector2.DOWN
	if Input.is_action_pressed("walk_up"):
		walk_direction += Vector2.UP
	if Input.is_action_pressed("walk_right"):
		walk_direction += Vector2.RIGHT
	if Input.is_action_pressed("walk_left"):
		walk_direction += Vector2.LEFT
		
	walk_direction = walk_direction.normalized()
	
	if Input.is_action_just_pressed("dash") and dash_cooldown_time_elapsed >= dash_cooldown_time and walk_direction != Vector2.ZERO:
		dashing = true
		dash_direction = global_position.direction_to(get_global_mouse_position())
		dash_cooldown_time_elapsed = 0
		dash_direction = walk_direction
		
	if not dashing:
		var v = velocity.length()
		if v > 0:
			v -= current_friction * delta
			v = max(v, 0)
			velocity = velocity.normalized() * v 
			
		#walk
		var this_walk_accel : Vector2 = walk_direction * walk_accel * delta
		if (velocity + this_walk_accel).length() <= walk_max_speed: #if accelerating doesnt exceed max speed, accelerate
			velocity += this_walk_accel
		elif velocity.length() < walk_max_speed: #if accelerating does exceed max speed but player hasnt reached max speed
			velocity = walk_max_speed * walk_direction #reach max speed
		elif velocity.length() > walk_max_speed:
			velocity = walk_max_speed * walk_direction
	if dashing:
		dash_time_elapsed += delta
		if dash_time_elapsed >= dash_time:
			dashing = false
			dash_time_elapsed = 0
		velocity = dash_direction * dash_speed
	else:
		dash_cooldown_time_elapsed += delta
		
	move_and_slide()
	
	# Play walking sound if moving
	#var is_moving = velocity.length() > 5.0 and not dying
	#if is_moving:
		#if not %walk_noise.playing:
			#%walk_noise.play()
	#else:
		#if %walk_noise.playing:
			#%walk_noise.stop()


func take_primary_action() -> void:
	if primary_item:
		primary_item.use(self)
	
	
func take_secondary_action() -> void:
	pass


func take_damage(dmg : float, _damage_type: String = "default") -> void:
	health -= dmg
	#%damage_noise.play()


func die() -> void:
	died.emit()
	Main.level.hud.display_failure("You perished.")
	queue_free()
	
	
func add_primary_item(pi : PrimaryItem) -> void:
	if pi != primary_item and primary_item:
		drop_primary_item()
	primary_item = pi
		
		
func drop_primary_item() -> void:
	primary_item.remove_from_entity(self)
	primary_item.place_on_ground(position + Vector2.RIGHT.rotated(rotation) * 75)
