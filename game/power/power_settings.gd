@tool
class_name PowerSettings
extends Resource

##The numbers of the power system, in one place (power_settings.tres, set on the level's PowerGrid). Power is a flow: generators give points per
##second, and everything that is on (a closed door, a light, a camera, a turret) takes points per second while it is on. See PowerGrid.
##
##shed_order is what goes first when there is not enough power any more (a generator shot down): the first category in the list is switched off
##first, then the next, until what is left fits. Drag the entries in the inspector to change the order.

enum Category { DOORS, LIGHTS, CAMERAS, TURRETS }

const CATEGORY_NAMES : Array[String] = ["doors", "lights", "cameras", "turrets"]

@export var shed_order : Array[Category] = [Category.TURRETS, Category.CAMERAS, Category.LIGHTS, Category.DOORS] ## first is switched off first when power runs short

@export_group("Cost per second")
@export_range(0.0, 100.0, 0.5, "suffix:pts/s") var door_cost : float = 2.0 ## a door held shut
@export_range(0.0, 100.0, 0.5, "suffix:pts/s") var light_cost : float = 1.0 ## a light switched on
@export_range(0.0, 100.0, 0.5, "suffix:pts/s") var camera_cost : float = 3.0 ## a camera in use
@export_range(0.0, 100.0, 0.5, "suffix:pts/s") var turret_cost : float = 5.0 ## a turret switched on

@export_group("Generators")
@export_range(0.0, 500.0, 1.0, "suffix:pts/s") var region_generator_output : float = 12.0 ## a region generator's output, unless it sets its own
@export_range(0.0, 500.0, 1.0, "suffix:pts/s") var whole_map_generator_output : float = 20.0 ## a whole-map generator's output, unless it sets its own
@export_range(1.0, 2000.0, 1.0) var generator_health : float = 300.0 ## how much damage takes a generator down, unless it sets its own
@export_range(0.1, 60.0, 0.1, "suffix:s") var start_seconds : float = 4.0 ## how long E is held to start a generator
@export_range(0.1, 60.0, 0.1, "suffix:s") var repair_seconds : float = 8.0 ## how long E is held to bring a shot-down generator back


func cost_of(category : Category) -> float:
	match category:
		Category.DOORS: return door_cost
		Category.LIGHTS: return light_cost
		Category.CAMERAS: return camera_cost
		Category.TURRETS: return turret_cost
	return 0.0


##The cheapest thing that can be switched on: below this, nothing more can be.
func cheapest_cost() -> float:
	return minf(minf(door_cost, light_cost), minf(camera_cost, turret_cost))


##Where a category comes in shed_order (0 goes first). A category missing from the list goes after all the others.
func shed_rank(category : Category) -> int:
	var at : int = shed_order.find(category)
	return at if at >= 0 else shed_order.size() + int(category)


##What is wrong with shed_order, or "" (every category exactly once).
func shed_order_problem() -> String:
	for category : int in Category.values():
		var count : int = shed_order.count(category)
		if count == 0:
			return "shed_order is missing %s" % CATEGORY_NAMES[category]
		if count > 1:
			return "shed_order has %s more than once" % CATEGORY_NAMES[category]
	return ""


static func category_name(category : Category) -> String:
	return CATEGORY_NAMES[category]
