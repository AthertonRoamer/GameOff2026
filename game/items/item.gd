class_name Item
extends Resource

##Generic inventory item. Override use() per item type; not every item needs to be rollback-safe
##(that's only required of items, like guns, whose use() affects deterministic gameplay state).

@export var item_name : String = ""
@export var icon : Texture2D
@export var cooldown_ticks : int = 0 #ticks before this item can be used again


func use(_user : Player, _tick : int) -> void:
	pass #override per item type
