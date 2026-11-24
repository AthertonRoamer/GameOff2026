class_name AmmoLocation
extends Marker2D

##A spot where a box of ammo lies. Place these in rooms where it makes sense to find ammunition (an armory, a locker room, a guard post): AmmoPlacer puts a box on each one.

const GROUP : StringName = &"ammo_locations"


func _ready() -> void:
	add_to_group(GROUP)
