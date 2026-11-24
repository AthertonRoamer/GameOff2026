class_name AmmoItem
extends Item

##A box of ammunition. Picking one up takes a slot, and the rounds go to the player's supply (see Inventory.reserve_at); a second box joins the first one's slot instead of
##taking another. The guns are loaded from the supply: see Inventory and Gun.magazine_size.

@export var rounds : int = 12 ## what one box adds to the supply


func slot_for(inventory : Inventory) -> int:
	var pouch : int = inventory.ammo_slot()
	return pouch if pouch >= 0 else inventory.first_free_slot()


func put_into(inventory : Inventory, slot : int, tick : int) -> void:
	inventory.add_supply(tick, rounds)
	if inventory.slots[slot] == null:
		inventory.put_in_slot(slot, self)
