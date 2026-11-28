class_name ComsHackerItem
extends Item

##A coms hacker. Put down by a player (clicked down, or dropped with G) it listens for them: every chat message sent within GadgetSystem.listen_radius_m of it, on a
##channel they are not on (the attackers' own, for a guard), reaches them too, with who sent it (GadgetSystem.intercept). It blinks a small red light, so others can
##find it: a shot breaks it, and E takes it (to put down for themselves). One found lying about, or fallen from a dead player, listens for nobody until it is put down.


func _init() -> void:
	click_use = ClickUse.PLACE


func on_floor(pickup : Pickup, control : PickupControl) -> void:
	var visual : ComsHackerVisual = ComsHackerVisual.new()
	visual.name = "Hacker"
	visual.pickup = pickup
	visual.listening = pickup.placed_by >= 0
	pickup.add_child(visual)
	pickup.icon_sprite.visible = false
	if pickup.placed_by >= 0:
		var gadgets : Node = control.get_tree().get_first_node_in_group(GadgetSystem.GROUP) if control.is_inside_tree() else null
		if gadgets is GadgetSystem:
			(gadgets as GadgetSystem).add_hacker(pickup)


func off_floor(pickup : Pickup, control : PickupControl) -> void:
	var gadgets : Node = control.get_tree().get_first_node_in_group(GadgetSystem.GROUP) if control.is_inside_tree() else null
	if gadgets is GadgetSystem:
		(gadgets as GadgetSystem).remove_hacker(pickup)
