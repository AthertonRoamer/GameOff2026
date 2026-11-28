class_name MedicineMaker
extends Node

##A medic making their next dose of medicine, as something to hold a key on (see PlayerInteractor): once the HUD's medicine bar is full (AbilityControl), holding Q for
##Role.medicine_make_seconds fills the progress bar, and the lobby is asked to hand the dose over (it checks the dose is ready, the hold was long enough and there is a free slot).
##It is not in the interactables group, and has no prompt of its own: the medicine bar's label says when Q can be held.

var player : Player


func _abilities() -> AbilityControl:
	return get_tree().get_first_node_in_group(AbilityControl.GROUP) as AbilityControl


func get_prompt() -> String:
	return ""


func is_in_reach(_world_position : Vector2) -> bool:
	return true


## A living medic whose next dose is ready, with a free slot for it.
func can_interact(_player : Node) -> bool:
	var abilities : AbilityControl = _abilities()
	return abilities != null and player.is_alive() and player.role != null and player.role.medicine_item != null \
		and abilities.own_medicine_known and abilities.own_medicine_ready and player.inventory.first_free_slot() >= 0


func hold_seconds(_player : Node) -> float:
	return player.role.medicine_make_seconds if player.role != null else 2.0


func hold_started(_player : Node) -> void:
	var abilities : AbilityControl = _abilities()
	if abilities != null:
		abilities.request_make_hold(true)


func hold_cancelled(_player : Node) -> void:
	var abilities : AbilityControl = _abilities()
	if abilities != null:
		abilities.request_make_hold(false)


func interact(_player : Node) -> Control:
	var abilities : AbilityControl = _abilities()
	if abilities != null:
		abilities.request_make_medicine()
	return null
