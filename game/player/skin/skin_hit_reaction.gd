class_name SkinHitReaction
extends Node

## How a skin reacts to being hit: a flinch away from the shot (the whole skin is pushed a few pixels along the way the shot was travelling and eases back, flashing
## red) and a puff of blood. Child of the skin; NightShiftCharacter.hit() plays it. The values are editable on the node.

@export var flinch_distance := 3.0 ## how far (pixels) a hit pushes the skin
@export var flinch_time := 0.18 ## seconds for the push and the return
@export var flinch_tint := Color(1.0, 0.55, 0.55) ## the colour the skin flashes
@export_group("Blood")
@export var blood_color := Color(0.62, 0.04, 0.05)
@export var blood_amount := 9

var _tween : Tween
var _rest := Vector2.ZERO #where the skin stands, which a flinch moves it from and back to

@onready var _skin : Node2D = get_parent()


## away: the way the shot was travelling, in the world. flinch: false for a hit that killed (the body is falling, only the blood).
func react(away : Vector2, flinch := true) -> void:
	_puff_of_blood(away)
	if not flinch:
		return
	if _tween != null and _tween.is_valid():
		cancel() #a second hit while still flinching starts from rest again
	else:
		_rest = _skin.position
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_skin, "position", _rest + away * flinch_distance, flinch_time * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_skin, "modulate", flinch_tint, flinch_time * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_property(_skin, "position", _rest, flinch_time * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_skin, "modulate", Color.WHITE, flinch_time * 0.65)


## Stops a flinch part way and puts the skin back (dying or being revived).
func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_skin.position = _rest
		_skin.modulate = Color.WHITE


## Droplets thrown the way the shot was travelling, from the player's chest. They are left where they fly (the emitter is not carried along by the player) and
## the emitter removes itself when they are gone.
func _puff_of_blood(away : Vector2) -> void:
	var puff := CPUParticles2D.new()
	puff.top_level = true
	puff.one_shot = true
	puff.emitting = false
	puff.explosiveness = 1.0
	puff.amount = blood_amount
	puff.lifetime = 0.4
	puff.direction = away
	puff.spread = 35.0
	puff.gravity = Vector2.ZERO
	puff.initial_velocity_min = 25.0
	puff.initial_velocity_max = 70.0
	puff.damping_min = 90.0
	puff.damping_max = 140.0
	puff.scale_amount_min = 1.2
	puff.scale_amount_max = 2.4
	var fade := Gradient.new()
	fade.set_color(0, blood_color)
	fade.set_color(1, Color(blood_color, 0.0))
	puff.color_ramp = fade
	puff.finished.connect(puff.queue_free)
	_skin.add_child(puff)
	puff.global_position = _skin.global_position
	puff.emitting = true
