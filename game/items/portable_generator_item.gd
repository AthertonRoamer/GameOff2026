class_name PortableGeneratorItem
extends Item

##The technician's portable generator. Carried, it takes a slot like any item. Put down (chosen and clicked, or dropped with G) it runs where it lies: it adds as much
##power as a facility region generator (or `output`, if set) to the power of the region it stands in (PowerGrid.add_portable), hums, and is picked up again with E. Dropped by a technician who dies, it runs too.
##While it is on the floor it is a Pickup like any other, with a generator drawn in place of the icon (PortableGeneratorVisual).

@export_range(-1.0, 200.0, 1.0, "or_greater", "suffix:pts/s") var output : float = -1.0 ## -1: the same as a facility region generator (PowerSettings.region_generator_output)


func _init() -> void:
	click_use = ClickUse.PLACE


static func key_of(pickup : Pickup) -> String:
	return "portable:%d" % pickup.pickup_id


func on_floor(pickup : Pickup, control : PickupControl) -> void:
	var visual : PortableGeneratorVisual = PortableGeneratorVisual.new()
	visual.name = "Generator"
	pickup.add_child(visual)
	pickup.icon_sprite.visible = false
	if control.power != null:
		var map : FacilityMap = control.power.facility
		var region : String = map.region_at(map.to_local(pickup.global_position)) if map != null else ""
		control.power.add_portable(key_of(pickup), region, output_on(control.power), pickup.global_position)


func off_floor(pickup : Pickup, control : PickupControl) -> void:
	if control.power != null:
		control.power.remove_portable(key_of(pickup))


## Points per second it gives on this grid: its own output if set, otherwise the same as a facility generator powering a region.
func output_on(grid : PowerGrid) -> float:
	if output >= 0.0:
		return output
	return grid.settings.region_generator_output if grid != null and grid.settings != null else PowerGrid.DEFAULT_SETTINGS.region_generator_output
