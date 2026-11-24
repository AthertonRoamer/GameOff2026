class_name Vent
extends Node2D

##A vent of the facility: an interactable (see PlayerInteractor) only a ventrat can use. In reach, E opens the vent map to pick another vent to come out of
##(AbilityControl decides and moves them). Made by AbilityControl.build() for every marker under the map's Vents node: put a vent in the map by adding a Marker2D there.

@export var reach_m : float = 1.2

var index : int = -1 #the place in AbilityControl.vents, the same on every peer
var control : AbilityControl


func _ready() -> void:
	add_to_group(PlayerInteractor.GROUP)


func can_interact(player : Player) -> bool:
	return player.role != null and player.role.can_vent and player.is_alive() and control != null and control.vents.size() > 1


func is_in_reach(world_position : Vector2, slack : float = 1.0) -> bool:
	return global_position.distance_to(world_position) <= reach_m * Acoustics.PX_PER_METRE * slack


func get_prompt() -> String:
	return "E   climb into the vent"


func interact(player : Player) -> Control:
	control.vent_screen.open(player, self)
	return control.vent_screen
