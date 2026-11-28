class_name Pickup
extends Node2D

##Any item lying on the floor. An interactable (see PlayerInteractor): in reach, E asks PickupControl to put it in the player's inventory.
##Made with PickupControl.spawn(), never added by hand, so every peer agrees which pickup is which.

@export var item : Item
@export var reach_m : float = 1.2 #how close the player has to be
@export var icon_size_px : float = 30.0 #the item's icon is scaled to this on the floor

var pickup_id : int = -1
var control : PickupControl
var can_take : Callable = Callable() #(player : Player) -> bool. Who may take this one. Unset: anyone
var placed_by : int = -1 #the member who put it down on purpose (dropped or placed it), -1 for one placed at the start or fallen from a dead player. A tripwire or coms hacker works for them only
var placed_facing : float = 0.0 #the way they faced as they put it down (radians): a tripwire is strung across it
var seen : float = 1.0 : set = set_seen ## how well the local player sees it, 0 to 1 (PickupControl sets it from the player's view, as for blood and bodies): drawn that strongly

@onready var icon_sprite : Sprite2D = $Icon


func _ready() -> void:
	add_to_group(PlayerInteractor.GROUP)
	icon_sprite.texture = item.icon
	icon_sprite.scale = Vector2.ONE * icon_size_px / maxf(item.icon.get_width(), item.icon.get_height())


func set_seen(value : float) -> void:
	seen = value
	modulate.a = value


func can_interact(player : Player) -> bool:
	return not can_take.is_valid() or can_take.call(player)


##Close enough, and no wall or closed door in between.
func is_in_reach(world_position : Vector2, slack : float = 1.0) -> bool:
	if global_position.distance_to(world_position) > reach_m * 44.0 * slack:
		return false
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(world_position, global_position, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func get_prompt() -> String:
	return item.take_prompt()


func interact(_player : Player) -> Control:
	control.request_pickup(self)
	return null
