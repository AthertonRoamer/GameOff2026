class_name Revivable
extends Node2D

##A player's body as something a medic can bring back (an interactable, see PlayerInteractor). It lies where the body lies, and is only offered to a player whose role
##can revive, while the player is down and has been for less than AbilityControl.revive_window_seconds. Child of the Player; the game gives it the AbilityControl.

@export var reach_m : float = 1.2

var control : AbilityControl

@onready var player : Player = get_parent()


func _ready() -> void:
	add_to_group(PlayerInteractor.GROUP)


func _process(_delta : float) -> void:
	if not player.is_alive():
		global_position = player.skin.body_position() #a fallen body lies away from where its player stood


func can_interact(medic : Player) -> bool:
	return control != null and medic != player and medic.role != null and medic.role.can_revive and medic.is_alive() and control.revive_window_open(player)


func is_in_reach(world_position : Vector2, slack : float = 1.0) -> bool:
	return not player.is_alive() and player.skin.body_position().distance_to(world_position) <= reach_m * Acoustics.PX_PER_METRE * slack


func get_prompt() -> String:
	return "E   revive %s" % (player.player_name if player.player_name != "" else "them")


func interact(_medic : Player) -> Control:
	control.request_revive(player)
	return null
