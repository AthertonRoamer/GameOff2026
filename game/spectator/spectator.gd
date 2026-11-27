class_name Spectator
extends Node

## Once the local player is dead, the camera follows a living player: A / D (the move left and right keys) switch between them. A player brought back (a medic) gets
## their own camera again. Only this peer's view changes: nothing is sent, and it shows a player's name only, never their role or team (a revived player must not
## have been told who the secret attacker is). What a dead player can see is PlayerSight's business: everything. Not used in a deathmatch (the dead come back).

@export_range(0.0, 10.0, 0.1, "suffix:s") var delay_seconds : float = 2.0 ## how long the player watches their own fall first

var players : Callable = Callable() ## () -> Array of every player (set by the game, with the next three)
var local_player : Callable = Callable() ## () -> this peer's own player, or null
var name_of : Callable = Callable() ## (player) -> String
var allowed : Callable = Callable() ## () -> bool: play is on and this mode has spectating

var target : Node2D #the player being watched, null while not spectating

var _dead_for : float = 0.0

@onready var camera : Camera2D = $Camera
@onready var screen : CanvasLayer = $Screen
@onready var label : Label = $Screen/Label


func _ready() -> void:
	camera.enabled = false
	screen.visible = false


func is_spectating() -> bool:
	return target != null


func _process(delta : float) -> void:
	var me : Node2D = local_player.call() if local_player.is_valid() else null
	if not is_instance_valid(me) or me.is_alive() or (allowed.is_valid() and not allowed.call()):
		_dead_for = 0.0
		_stop(me)
		return
	_dead_for += delta
	if _dead_for < delay_seconds:
		return
	var living : Array = _living(me)
	if living.is_empty(): #nobody left to watch: stay by the body
		_stop(me)
		return
	if not is_instance_valid(target) or not living.has(target):
		_watch(living[0], me)
	camera.global_position = target.global_position


func _unhandled_input(event : InputEvent) -> void: #(typing in the chat takes the keys before they get here)
	if not is_spectating() or event.is_echo():
		return
	var step : int = int(event.is_action_pressed(&"player_right")) - int(event.is_action_pressed(&"player_left"))
	if step != 0:
		cycle(step)
		get_viewport().set_input_as_handled()


## The next (1) or the one before (-1) of the living players.
func cycle(step : int) -> void:
	var me : Node2D = local_player.call()
	var living : Array = _living(me)
	if living.is_empty():
		return
	_watch(living[posmod(maxi(living.find(target), 0) + step, living.size())], me)
	camera.global_position = target.global_position


func _living(me : Node2D) -> Array:
	var result : Array = []
	for player : Variant in (players.call() if players.is_valid() else []):
		if is_instance_valid(player) and player != me and player.is_alive():
			result.append(player)
	return result


func _watch(player : Node2D, me : Node2D) -> void:
	target = player
	var own : Camera2D = me.get("camera")
	if own != null:
		camera.zoom = own.zoom
	camera.enabled = true
	camera.global_position = player.global_position
	camera.make_current()
	camera.reset_smoothing()
	var who : String = name_of.call(player) if name_of.is_valid() else "player"
	label.text = "SPECTATING  %s\nA / D to switch player" % who
	screen.visible = true
	print("Spectator: watching %s" % who)


func _stop(me : Node2D) -> void:
	if target == null and not screen.visible:
		return
	target = null
	screen.visible = false
	camera.enabled = false
	if is_instance_valid(me):
		var own : Camera2D = me.get("camera")
		if own != null and own.enabled:
			own.make_current()
	print("Spectator: off")
