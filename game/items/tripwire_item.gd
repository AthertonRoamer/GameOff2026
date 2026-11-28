class_name TripwireItem
extends Item

##A tripwire. Put down by a player (clicked down, or dropped with G) it strings a wire across the way they faced, from wall to wall (wire_half_length_px at most
##each way), and arms it for them: when anyone else crosses it, only they are told, with a ping and a line in the chat (GadgetSystem). It shows where it is, not
##who crossed. The wire is a thin line, seen like any item on the floor (in the view only). E takes it back up. One found lying about, or fallen from a dead
##player, is not armed until someone puts it down.

@export_range(20.0, 300.0, 1.0, "suffix:px") var wire_half_length_px : float = 88.0


func _init() -> void:
	click_use = ClickUse.PLACE


## The wire's two ends (world), across `facing` from `at`, each stopped by the first wall (walls only, so every peer strings it the same).
func wire_ends(space : PhysicsDirectSpaceState2D, at : Vector2, facing : float) -> PackedVector2Array:
	var across : Vector2 = Vector2.from_angle(facing + PI / 2.0)
	var ends : PackedVector2Array = PackedVector2Array()
	for side : float in [-1.0, 1.0]:
		var to : Vector2 = at + across * side * wire_half_length_px
		var hit : Dictionary = space.intersect_ray(PhysicsRayQueryParameters2D.create(at, to, FacilityTileSet.STRUCTURE_LAYER)) if space != null else {}
		ends.append(to if hit.is_empty() else hit["position"])
	return ends


func on_floor(pickup : Pickup, control : PickupControl) -> void:
	if pickup.placed_by < 0:
		return #(not put down by anyone: lies there coiled up)
	var ends : PackedVector2Array = wire_ends(pickup.get_world_2d().direct_space_state if pickup.is_inside_tree() else null, pickup.global_position, pickup.placed_facing)
	var visual : TripwireVisual = TripwireVisual.new()
	visual.name = "Wire"
	visual.ends = ends
	pickup.add_child(visual)
	pickup.icon_sprite.scale *= 0.6
	var gadgets : Node = control.get_tree().get_first_node_in_group(GadgetSystem.GROUP) if control.is_inside_tree() else null
	if gadgets is GadgetSystem:
		(gadgets as GadgetSystem).add_tripwire(pickup, ends[0], ends[1])


func off_floor(pickup : Pickup, control : PickupControl) -> void:
	var gadgets : Node = control.get_tree().get_first_node_in_group(GadgetSystem.GROUP) if control.is_inside_tree() else null
	if gadgets is GadgetSystem:
		(gadgets as GadgetSystem).remove_tripwire(pickup)
