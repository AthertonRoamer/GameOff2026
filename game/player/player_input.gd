class_name PlayerInput
extends NetInput

var movement : Vector2 = Vector2.ZERO
var aim : Vector2 = Vector2.ZERO
var active : bool = false


func _gather() -> void:
	movement = Input.get_vector("player_left", "player_right", "player_up", "player_down") if active else Vector2.ZERO
	aim = (get_parent() as Node2D).get_global_mouse_position() if active else aim
