class_name RollbackDemoPlayer
extends CharacterBody2D

##Player of the rollback demo. The lobby owns the body, the member's own peer owns the Input child (see RollbackPlayerSpawner).
##The owning client simulates the body ahead of the server using its own input (prediction), and netfox rolls it back and
##resimulates whenever the server's state for a tick disagrees.
##
##The weapon is an instant (hitscan) shot built on RewindableAction:
##  - every peer that simulates the tick sees the same action status, so the shooter predicts the shot (tracer) at once
##  - only the lobby resolves the hit, against where the target was when the shooter fired (LagCompensator), and applies damage
##  - health is not rollback state. It is server-owned and sent by a StateSynchronizer, so resimulating a tick can never damage twice

@export var speed : float = 250.0
@export var max_health : int = 100
@export var damage : int = 25
@export var fire_cooldown_ticks : int = 15 #at 60 ticks/s, a quarter of a second
@export var weapon_range : float = 700.0
@export var name_display : Label
@export var sprite : Sprite2D

var player_name : String = "Player"
var id : int
var health : int = 100 #server-owned, synced by HealthSynchronizer
var last_fire_tick : int = -1000 #rollback state, drives the cooldown
var lag_compensator : LagCompensator #set by the game on the lobby, where shots are resolved

var _damaging_shot_ticks : Array[int] = [] #lobby only, not rollback state: ticks of shots that already did damage

@onready var input : RollbackDemoInput = $Input
@onready var fire_action : RewindableAction = $FireAction


func _ready() -> void:
	health = max_health
	if input.is_multiplayer_authority(): #the input node is owned by the peer that controls this player
		sprite.modulate = Color(0.6, 1.0, 0.6)


func _process(_delta : float) -> void:
	name_display.text = "%s  %d" % [player_name, health]
	if not is_alive():
		sprite.modulate.a = 0.3


func is_alive() -> bool:
	return health > 0


func set_active(active : bool) -> void:
	input.active = active


func take_damage(amount : int) -> void:
	if multiplayer.is_server(): #only the lobby changes health
		health = maxi(0, health - amount)


func _rollback_tick(_delta : float, tick : int, _is_fresh : bool) -> void:
	velocity = input.movement * speed if is_alive() else Vector2.ZERO
	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor
	_update_weapon(tick)


func _update_weapon(tick : int) -> void:
	var wants_to_fire : bool = is_alive() and input.fire and tick - last_fire_tick >= fire_cooldown_ticks
	fire_action.set_active(wants_to_fire)
	if fire_action.is_active():
		last_fire_tick = tick #also on resimulation, where the status is ACTIVE rather than CONFIRMING
	if fire_action.get_status() == RewindableAction.CONFIRMING:
		_show_tracer()
		_resolve_shot(tick)


func _resolve_shot(tick : int) -> void:
	if not multiplayer.is_server() or lag_compensator == null:
		return
	#A late input makes the lobby resimulate, and the same shot can then be confirmed on a slightly different tick than before.
	#That is still the same shot, so it must not do damage twice. A real second shot is at least fire_cooldown_ticks away.
	_damaging_shot_ticks = _damaging_shot_ticks.filter(func(t : int) -> bool: return t > tick - 4 * fire_cooldown_ticks)
	for earlier_tick in _damaging_shot_ticks:
		if absi(earlier_tick - tick) <= fire_cooldown_ticks / 2:
			Main.output("Shot on tick %d is a repeat of the shot on tick %d, ignoring" % [tick, earlier_tick])
			return
	_damaging_shot_ticks.append(tick)
	#rewind at least one tick: a tick's positions are only recorded once every node has simulated it
	var rewind : int = maxi(1, lag_compensator.clamp_lag(input.view_lag))
	var hit : Dictionary = lag_compensator.raycast(position, input.aim, weapon_range, tick - rewind, self)
	if not hit.is_empty():
		hit["node"].take_damage(damage)


func _show_tracer() -> void:
	if not is_visible_in_tree(): #the lobby process is headless and invisible
		return
	var tracer : Line2D = Line2D.new()
	tracer.width = 3.0
	tracer.default_color = Color(1.0, 0.9, 0.3)
	tracer.add_point(position)
	tracer.add_point(position + input.aim.normalized() * weapon_range)
	get_parent().get_parent().add_child(tracer) #spawner's parent: the game
	get_tree().create_timer(0.1).timeout.connect(tracer.queue_free)
