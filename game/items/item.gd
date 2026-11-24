class_name Item
extends Resource

##Generic inventory item. Override use() per item type; not every item needs to be rollback-safe
##(that's only required of items, like guns, whose use() affects deterministic gameplay state).

@export var item_name : String = ""
@export var icon : Texture2D
@export var cooldown_ticks : int = 0 #ticks before this item can be used again
@export var drawable : bool = false #held out in the hands (a gun): selecting it draws it, H holsters or draws it, and it can only be used while drawn


func use(_user : Player, _tick : int) -> void:
	pass #override per item type


## The slot taking this item would use, or -1 when there is no room for it (the pickups ask: see PickupControl and PlayerInteractor).
func slot_for(inventory : Inventory) -> int:
	return inventory.first_free_slot()


## Takes it into the inventory, in the slot slot_for() gave, on the tick the pickup is applied (the same tick on every peer).
func put_into(inventory : Inventory, slot : int, _tick : int) -> void:
	inventory.put_in_slot(slot, self)
