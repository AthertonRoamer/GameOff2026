class_name RollbackDemoInput
extends NetInput

##Input for the rollback demo player. "movement" is an input property of the player's RollbackSynchronizer.

var movement : Vector2 = Vector2.ZERO
var active : bool = false #input is ignored until the game has started


func _gather() -> void:
	if active:
		movement = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	else:
		movement = Vector2.ZERO
