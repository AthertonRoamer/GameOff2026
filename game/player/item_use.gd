class_name ItemUse
extends Node

##The item in the hand as something to hold E on (see PlayerInteractor): while an item that is used by holding E (Item.ClickUse.CONSUME: medicine) is chosen in the
##inventory and can be used, the HUD says "Hold E to heal" and holding E fills the progress bar; when it is full the lobby is asked to use the item (PickupControl.request_use),
##and it is gone from the inventory. The interactor offers this before anything in the world, since choosing the item is choosing to use it.
##It is not in the interactables group: the interactor asks it directly.

var player : Player


func item() -> Item:
	var active : Item = player.inventory.active_item if player != null else null
	return active if active != null and active.click_use == Item.ClickUse.CONSUME else null


func get_prompt() -> String:
	var held : Item = item()
	return held.hold_prompt() if held != null else ""


func is_in_reach(_world_position : Vector2) -> bool:
	return true


## The item is still in the hand and can be used now (medicine: alive and hurt).
func can_interact(_player : Node) -> bool:
	var held : Item = item()
	return held != null and held.can_consume(player)


func hold_seconds(_player : Node) -> float:
	var held : Item = item()
	return held.hold_seconds if held != null else 1.0


func interact(_player : Node) -> Control:
	var control : Node = get_tree().get_first_node_in_group(PickupControl.GROUP)
	if control != null and item() != null:
		control.request_use(player.inventory.active_slot)
	return null
