class_name DoorSwitch
extends Node2D

##Lets a player whose role works doors by hand (Role.can_work_doors: the technician) open or close a door while standing next to it, with E (see PlayerInteractor).
##The level puts one on every door. It only asks: FacilityControl.request_door_by_hand, and the lobby checks the player is next to the door and, to close it, that its
##region has the power to hold it shut (as the door console does). A locked door, or one already switching, can't be worked.

const REACH_PX : float = 62.0 #from the door's middle: about a step either side of the doorway
const REACH_SLACK : float = 1.5 #the lobby's view of a player can be a few ticks behind

var door : FacilityDoor
var control : FacilityControl


func _ready() -> void:
	add_to_group(PlayerInteractor.GROUP)


static func may_work(player : Node) -> bool:
	var role : Role = player.get("role")
	return role != null and role.can_work_doors


func can_interact(player : Node) -> bool:
	return control != null and may_work(player) and door.state != FacilityDoor.State.LOCKED and not control.is_pending(door)


func is_in_reach(world_position : Vector2, slack : float = 1.0) -> bool:
	return door.global_position.distance_to(world_position) <= REACH_PX * slack


## Closing it needs power free in its region (an open door costs nothing; a shut one is held shut by power).
func has_power_to_close() -> bool:
	return control == null or control.power == null or control.power.has_load(PowerGrid.door_key(door)) \
		or control.power.can_afford(control.facility.region_of_door(door), control.power.door_cost())


func get_prompt() -> String:
	if door.state == FacilityDoor.State.OPEN:
		return "E   close the door" if has_power_to_close() else "No power to close this door"
	return "E   open the door"


func interact(_player : Node) -> Control:
	if door.state == FacilityDoor.State.OPEN:
		if has_power_to_close():
			control.request_door_by_hand(door, FacilityDoor.State.CLOSED)
	else:
		control.request_door_by_hand(door, FacilityDoor.State.OPEN)
	return null
