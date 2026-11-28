class_name SmokeBombItem
extends Item

##A smoke bomb. Chosen and clicked, it is thrown towards the mouse (throw_range_px at most, stopped short of a wall) and bursts into a SmokeCloud where it
##lands, which hides whatever is behind it from players, cameras and turrets for a while. G drops it unused, like any item.

@export var radius_px : float = 120.0 ## how big the cloud gets
@export_range(1.0, 60.0, 0.5, "suffix:s") var smoke_seconds : float = 14.0 ## how long it stays thick


func _init() -> void:
	click_use = ClickUse.THROW


func thrown(at : Vector2, control : PickupControl) -> void:
	var gadgets : Node = control.get_tree().get_first_node_in_group(GadgetSystem.GROUP) if control.is_inside_tree() else null
	if gadgets is GadgetSystem:
		(gadgets as GadgetSystem).add_smoke(at, radius_px, smoke_seconds)
