class_name TurretSwitch
extends Node2D

##Lets a player whose role works doors by hand (Role.can_work_doors: the technician) switch a turret on or off while standing next to it, with E, the way
##DoorSwitch works a door (see PlayerInteractor). TurretSystem puts one on every turret. It only asks: FacilityControl.request_turret_by_hand, and the lobby
##checks the player is next to it and, to switch it on, that its region has the power. A shot-down turret can't be switched (a guard repairs it first, see Turret).

const REACH_SLACK : float = 1.5 #the lobby's view of a player can be a few ticks behind

var turret : Turret
var control : FacilityControl


func _ready() -> void:
	add_to_group(PlayerInteractor.GROUP)


static func may_work(player : Node) -> bool:
	return DoorSwitch.may_work(player)


func can_interact(player : Node) -> bool:
	return control != null and turret != null and may_work(player) and not turret.is_destroyed() and not control.is_turret_pending(turret.index)


func is_in_reach(world_position : Vector2, slack : float = 1.0) -> bool:
	return turret.global_position.distance_to(world_position) <= turret.reach_px() * slack


## Switching it on needs power free in its region.
func has_power_to_switch_on() -> bool:
	return control == null or control.power == null or control.power.has_load(PowerGrid.turret_key(turret.index)) \
		or control.power.can_afford(control.turret_region(turret.index), control.power.turret_cost())


func get_prompt() -> String:
	if control.is_turret_on(turret.index):
		return "E   switch the turret off"
	return "E   switch the turret on" if has_power_to_switch_on() else "No power for this turret"


func interact(_player : Node) -> Control:
	var on : bool = control.is_turret_on(turret.index)
	if on or has_power_to_switch_on():
		control.request_turret_by_hand(turret.index, not on)
	return null
