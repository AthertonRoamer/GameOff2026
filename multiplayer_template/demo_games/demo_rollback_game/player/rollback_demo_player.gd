class_name RollbackDemoPlayer
extends CharacterBody2D

##Player of the rollback demo. The lobby owns the body, the member's own peer owns the Input child (see RollbackPlayerSpawner).
##The owning client simulates the body ahead of the server using its own input (prediction), and netfox rolls it back and
##resimulates whenever the server's state for a tick disagrees.

@export var speed : float = 250.0
@export var name_display : Label
@export var sprite : Sprite2D

var player_name : String = "Player"
var id : int

@onready var input : RollbackDemoInput = $Input


func _ready() -> void:
	name_display.text = player_name
	if input.is_multiplayer_authority(): #the input node is owned by the peer that controls this player
		sprite.modulate = Color(0.6, 1.0, 0.6)


func set_active(active : bool) -> void:
	input.active = active


func _rollback_tick(_delta : float, _tick : int, _is_fresh : bool) -> void:
	velocity = input.movement * speed
	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor
