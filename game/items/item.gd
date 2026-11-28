class_name Item
extends Resource

##Generic inventory item. Override use() per item type; not every item needs to be rollback-safe
##(that's only required of items, like guns, whose use() affects deterministic gameplay state).
##
##Every item can be dropped (G drops the one in the hand, and everything a player carries falls round them when they die) and picked up again: see PickupControl.
##An item that is not drawable may still do something when it is chosen (`click_use`): a click puts a portable generator down, holding E uses up medicine. That goes through
##the lobby, like a pickup.

enum ClickUse {
	NONE, ## the click does nothing (a relic, an ammo box)
	CONSUME, ## not a click: chosen, E is held on it (a progress bar, see ItemUse) to use it up; the lobby applies it (consume_on) and the item leaves the inventory (medicine)
	PLACE, ## put down where the player stands, the same as dropping it (a portable generator, a tripwire, a coms hacker)
	THROW, ## thrown towards the mouse (as far as throw_range_px, stopped by walls): it leaves the inventory and thrown() runs where it lands, on every peer (a smoke bomb)
}

@export var item_name : String = ""
@export var icon : Texture2D
@export var cooldown_ticks : int = 0 #ticks before this item can be used again
@export var drawable : bool = false #held out in the hands (a gun): selecting it draws it, H holsters or draws it, and it can only be used while drawn
@export var click_use : ClickUse = ClickUse.NONE ## what clicking with it chosen does, for an item that is not drawable
@export_range(0.1, 10.0, 0.1, "suffix:s") var hold_seconds : float = 2.0 ## ClickUse.CONSUME: how long E is held to use it
@export_range(0.0, 1000.0, 1.0, "suffix:px") var throw_range_px : float = 300.0 ## ClickUse.THROW: how far it can be thrown


func use(_user : Player, _tick : int) -> void:
	pass #override per item type


## The slot taking this item would use, or -1 when there is no room for it (the pickups ask: see PickupControl and PlayerInteractor).
func slot_for(inventory : Inventory) -> int:
	return inventory.first_free_slot()


## Takes it into the inventory, in the slot slot_for() gave, on the tick the pickup is applied (the same tick on every peer).
func put_into(inventory : Inventory, slot : int, _tick : int) -> void:
	inventory.put_in_slot(slot, self)


## Lobby: can this player use it up now (ClickUse.CONSUME)? The lobby asks before it agrees.
func can_consume(_user : Player) -> bool:
	return false


## ClickUse.CONSUME: what the HUD says while it is chosen and can be used.
func hold_prompt() -> String:
	return "Hold E   use the %s" % item_name.to_lower()


## Lobby: what using it up does (ClickUse.CONSUME), done when the lobby agrees. Its effect must be something the lobby already syncs (the health).
func consume_on(_user : Player) -> void:
	pass


## What the prompt says for taking it off the floor.
func take_prompt() -> String:
	return "E to pick up %s" % item_name


## Called on every peer when it comes to lie on the floor (dropped, placed or put there at the start), and when it leaves it (taken, or the game ending).
## The portable generator runs while it is down.
func on_floor(_pickup : Pickup, _control : PickupControl) -> void:
	pass


func off_floor(_pickup : Pickup, _control : PickupControl) -> void:
	pass


## ClickUse.THROW: called on every peer, on the same tick, when it lands (a world position). By then it has left the thrower's inventory.
func thrown(_at : Vector2, _control : PickupControl) -> void:
	pass
