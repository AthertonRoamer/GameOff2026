extends Node2D

# A stand-in player for test_turrets: where it stands, its role, its health. Turrets only ask a player for these.

var role : Role
var health : float = 50.0


func is_alive() -> bool:
	return health > 0.0


func take_damage(damage : float, _direction : Vector2 = Vector2.ZERO) -> void:
	health -= damage
