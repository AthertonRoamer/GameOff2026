class_name RollbackDemoInput
extends NetInput

##Input for the rollback demo player. movement, fire, aim and view_lag are input properties of the player's RollbackSynchronizer.
##Move with the arrow keys, aim with the mouse, fire with the left mouse button or ui_accept (space / enter).

var movement : Vector2 = Vector2.ZERO
var fire : bool = false
var fire_alt : bool = false #projectile weapon: right mouse button or Tab
var aim : Vector2 = Vector2.RIGHT
var view_lag : int = 0 #how many ticks behind the server this player is looking at the other players, used for lag compensation
var active : bool = false #input is ignored until the game has started

var test_aim : Variant = null #automated tests set this to aim without a mouse


func _gather() -> void:
	if not active:
		movement = Vector2.ZERO
		fire = false
		fire_alt = false
		return
	movement = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	fire = Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	fire_alt = Input.is_action_pressed("ui_focus_next") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var body : Node2D = get_parent()
	if test_aim != null:
		aim = test_aim
	else:
		aim = (body.get_global_mouse_position() - body.global_position).normalized()
	if aim.is_zero_approx():
		aim = Vector2.RIGHT
	view_lag = int(ceil(NetworkTime.remote_rtt * 0.5 * NetworkTime.tickrate)) + NetworkRollback.display_offset
