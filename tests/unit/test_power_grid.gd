extends Node

# Offline test of the power system (game/power): regions on the map, generators, what a door costs, the shared pool, switching things off in
# PowerSettings.shed_order when power runs short, repairing a generator, and FacilityControl refusing a door there is no power for.
# Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_power_grid.tscn

const MAP_SCENE : PackedScene = preload("res://game/environment/facility_map.tscn")
const WINGS_SCENE : PackedScene = preload("res://game/environment/facility_map_wings.tscn")

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	var map : FacilityMap = MAP_SCENE.instantiate()
	map.doors_start = FacilityDoor.State.OPEN
	add_child(map)
	await get_tree().process_frame

	#regions on the map
	var region_nodes : int = map.get_node("Regions").get_child_count()
	check(map.regions.size() == region_nodes and region_nodes >= 3, "the map has every region under its Regions node (%d of %d)" % [map.regions.size(), region_nodes])
	for id : String in map.rooms:
		var region : String = map.rooms[id]["region"]
		check(region == "" or map.regions.has(region), "room %s is in a region the map has (%s)" % [id, region])
	check(map.region_at(map.room_center_px("archive")) == "west", "the archive is in the west wing")
	check(map.region_at(map.room_center_px("cafeteria")) == "east", "the cafeteria is in the east wing")
	check(map.region_at(Vector2(-5000, -5000)) == "", "nowhere is in no region")
	check(not map.region_outline("west").is_empty() and map.region_outline("west").size() % 2 == 0, "the west wing has an outline (%d points)" % map.region_outline("west").size())
	var vault_door : FacilityDoor = _door_between(map, "corridor", "vault")
	check(vault_door != null and map.region_of_door(vault_door) == "west", "the door from the corridor into the vault is paid for by the vault's region")

	var grid : PowerGrid = PowerGrid.new()
	grid.facility = map
	grid.settings = PowerGrid.DEFAULT_SETTINGS.duplicate()
	add_child(grid)
	grid.build()
	var west_gen : Generator = _generator(grid, "WestGenerator")
	var main_gen : Generator = _generator(grid, "MainGenerator")
	var placed : int = map.props_node.find_children("*", "StaticBody2D", true, false).filter(func(n : Node) -> bool: return n is Generator).size()
	check(grid.generators.size() == placed and placed >= 3, "the grid finds every generator on the map (%d of %d)" % [grid.generators.size(), placed])
	check(west_gen != null and west_gen.region == "west" and west_gen.scope == Generator.Scope.REGION, "the west generator powers the west wing")
	check(main_gen != null and main_gen.scope == Generator.Scope.WHOLE_MAP, "the main generator powers the whole map")
	for generator : Generator in grid.generators:
		check(generator.state == Generator.State.OFF and generator.health == generator.max_health(), "%s starts off, at full health" % generator.name)
	check(grid.available("west") == 0.0 and not grid.can_afford("west", grid.door_cost()), "with nothing running there is no power for a door")

	#a region generator powers its own region only
	grid.set_generator(west_gen, Generator.State.RUNNING)
	var west_out : float = west_gen.output()
	check(is_equal_approx(grid.available("west"), west_out) and grid.available("core") == 0.0, "the west generator gives the west wing %d and the core nothing" % west_out)
	vault_door.state = FacilityDoor.State.CLOSED
	check(grid.has_load(PowerGrid.door_key(vault_door)) and is_equal_approx(grid.available("west"), west_out - grid.door_cost()), "a shut door takes its cost from its region")

	#the whole-map generator fills the shared pool
	grid.set_generator(main_gen, Generator.State.RUNNING)
	var pool : float = main_gen.output()
	check(is_equal_approx(grid.available("core"), pool), "the pool is free for the core (%d)" % pool)
	check(is_equal_approx(grid.available("west"), west_out - grid.door_cost() + pool), "the west wing has its own power left plus the pool")
	var core_door : FacilityDoor = _door_between(map, "corridor", "door_control")
	core_door.state = FacilityDoor.State.CLOSED
	grid.add_load("light", PowerSettings.Category.LIGHTS, "core")
	grid.add_load("turret", PowerSettings.Category.TURRETS, "core")
	grid.add_load("camera", PowerSettings.Category.CAMERAS, "east")
	var core_need : float = grid.door_cost() + grid.settings.light_cost + grid.settings.turret_cost
	check(is_equal_approx(grid.pool_free(), pool - core_need - grid.settings.camera_cost), "the core and the east wing share the pool (%.1f left)" % grid.pool_free())
	check(is_equal_approx(grid.available("east"), grid.available("core")), "two regions with no generators of their own have the same pool left")

	#power runs short: the first of shed_order goes first, and a region its own generator covers is left alone
	main_gen.output_override = core_need + grid.settings.camera_cost - 1.0 #a little short
	grid.set_generator(main_gen, Generator.State.RUNNING)
	check(not grid.has_load("turret"), "short of power, the turret goes first (shed_order starts with turrets)")
	check(grid.has_load("light") and grid.has_load("camera") and core_door.state == FacilityDoor.State.CLOSED, "and nothing else goes once what is left fits")
	check(vault_door.state == FacilityDoor.State.CLOSED, "the west wing's door, covered by its own generator, stays shut")
	grid.settings.shed_order = [PowerSettings.Category.DOORS, PowerSettings.Category.TURRETS, PowerSettings.Category.CAMERAS, PowerSettings.Category.LIGHTS] as Array[PowerSettings.Category]
	main_gen.output_override = grid.settings.light_cost + grid.settings.camera_cost + 0.5
	grid.set_generator(main_gen, Generator.State.RUNNING)
	check(core_door.state == FacilityDoor.State.OPEN and not grid.has_load(PowerGrid.door_key(core_door)), "with doors first in shed_order, the core's door opens first")
	check(grid.has_load("light") and grid.has_load("camera"), "and the light and the camera stay on")
	check(grid.settings.shed_order_problem() == "", "the reordered shed_order has every category once")
	grid.settings.shed_order = [PowerSettings.Category.DOORS] as Array[PowerSettings.Category]
	check(grid.settings.shed_order_problem() != "", "a shed_order missing categories is reported (%s)" % grid.settings.shed_order_problem())

	#shot down: the pool empties and everything drawing on it goes
	grid.damage_generator(main_gen, main_gen.max_health() * 0.4)
	check(main_gen.state == Generator.State.RUNNING and main_gen.health < main_gen.max_health(), "a damaged generator keeps running")
	grid.damage_generator(main_gen, main_gen.max_health())
	check(main_gen.state == Generator.State.DESTROYED and main_gen.health == 0.0 and grid.pool_supply() == 0.0, "shot down, it stops and the pool is empty")
	check(not grid.has_load("light") and not grid.has_load("camera"), "everything that drew on the pool is switched off")
	check(vault_door.state == FacilityDoor.State.CLOSED, "the west wing still runs on its own generator")

	#repairing: hold E long enough, as a guard (no player lookup here: anyone counts)
	check(main_gen.hold_seconds(null) == main_gen.repair_seconds(), "a shot-down generator takes the repair time to bring back")
	grid.request_hold(main_gen, true)
	grid.request_finish(main_gen)
	check(main_gen.state == Generator.State.DESTROYED, "a hold that was too short does not repair it")
	grid.request_hold(main_gen, true)
	grid._holds[multiplayer.get_unique_id()]["since"] -= int(main_gen.repair_seconds() * 1000.0) #as if E had been held all that time
	grid.request_finish(main_gen)
	check(main_gen.state == Generator.State.RUNNING and main_gen.health == main_gen.max_health(), "a full hold repairs it, at full health")

	#starting one: its starter is heard while E is held, and stops when it catches or the hold is let go
	var cranks : Array = []
	grid.generator_worked.connect(func(key : String, _at : Vector2, work : int) -> void: cranks.append([key, work == PowerGrid.Work.CRANK]))
	grid.set_generator(main_gen, Generator.State.OFF)
	grid.request_hold(main_gen, true)
	check(grid.is_cranking(main_gen) and cranks.size() == 1 and cranks[0] == [PowerGrid.generator_key(main_gen), true], "holding E on a generator that is off cranks its starter")
	grid.request_hold(main_gen, false)
	check(not grid.is_cranking(main_gen) and cranks.size() == 2 and cranks[1][1] == false, "letting go stops it")
	grid.request_hold(main_gen, true)
	grid._holds[multiplayer.get_unique_id()]["since"] -= int(main_gen.start_seconds() * 1000.0)
	grid.request_finish(main_gen)
	check(main_gen.state == Generator.State.RUNNING and not grid.is_cranking(main_gen) and cranks.size() == 4, "a full hold starts it and the starter stops as it catches")
	grid.request_hold(main_gen, true)
	check(not grid.is_cranking(main_gen) and cranks.size() == 4, "holding E to turn a running one off does not crank it")
	grid.request_hold(main_gen, false)
	grid.set_generator(main_gen, Generator.State.OFF)
	grid.request_hold(main_gen, true)
	grid._holds[multiplayer.get_unique_id()]["since"] -= int((main_gen.start_seconds() + PowerGrid.STALE_HOLD_SECONDS + 1.0) * 1000.0)
	grid._process(0.1)
	check(not grid.is_cranking(main_gen) and grid._holds.is_empty(), "a hold that was never ended (its player left) is let go, and the starter stops")

	#repairing one is heard too (not as a start)
	var works : Array = []
	grid.generator_worked.connect(func(_key : String, _at : Vector2, work : int) -> void: works.append(work))
	grid.set_generator(main_gen, Generator.State.DESTROYED, 0.0)
	grid.request_hold(main_gen, true)
	check(grid.work_on(main_gen) == PowerGrid.Work.REPAIR and works == [PowerGrid.Work.REPAIR], "holding E on a shot-down generator is heard as a repair, not a start")
	grid._holds[multiplayer.get_unique_id()]["since"] -= int(main_gen.repair_seconds() * 1000.0)
	grid.request_finish(main_gen)
	check(main_gen.state == Generator.State.RUNNING and grid.work_on(main_gen) == PowerGrid.Work.NONE and works == [PowerGrid.Work.REPAIR, PowerGrid.Work.NONE], "the repair sound stops when it is done")
	grid.set_generator(main_gen, Generator.State.RUNNING)

	#a generator set to start running in the editor
	var east_gen : Generator = _generator(grid, "EastGenerator")
	east_gen.starts_running = true
	var grid2 : PowerGrid = PowerGrid.new()
	grid2.facility = map
	add_child(grid2)
	grid2.build()
	check(_generator(grid2, "EastGenerator").state == Generator.State.RUNNING and grid2.local_supply("east") > 0.0, "a generator with starts_running is running from the start")
	grid2.queue_free()
	east_gen.starts_running = false
	grid.build() #(the second grid took the generators over: give them back)

	#the door console asks FacilityControl, which asks the grid
	var control : FacilityControl = FacilityControl.new()
	control.facility = map
	control.power = grid
	add_child(control)
	grid.control = control
	var refused : Array = []
	control.door_refused.connect(func(door : FacilityDoor, reason : String) -> void: refused.append([door, reason]))
	for generator : Generator in grid.generators:
		grid.set_generator(generator, Generator.State.OFF)
	var east_door : FacilityDoor = _door_between(map, "corridor", "cafeteria")
	if east_door == null:
		east_door = _door_between(map, "cafeteria", "pad_east")
	control.request_door(east_door, FacilityDoor.State.CLOSED)
	check(refused.size() == 1 and refused[0][1] == "power" and not control.is_pending(east_door), "closing a door with no power in its region is refused")
	grid.set_generator(main_gen, Generator.State.RUNNING)
	control.request_door(east_door, FacilityDoor.State.CLOSED)
	check(control.is_pending(east_door) and grid.has_load(PowerGrid.door_key(east_door)), "with power it is accepted, and its power is counted at once")
	grid.set_generator(main_gen, Generator.State.DESTROYED, 0.0)
	check(not grid.has_load(PowerGrid.door_key(east_door)), "when the power goes, the door's load is dropped and it is told to open")

	#the rooms' ceiling lights: switched from the same console, paid for by the room's region, switched off before doors when power runs short
	const SETTLE : int = 100000 #a tick far ahead: every scheduled change is due
	grid.settings.shed_order = [PowerSettings.Category.TURRETS, PowerSettings.Category.CAMERAS, PowerSettings.Category.LIGHTS, PowerSettings.Category.DOORS] as Array[PowerSettings.Category]
	main_gen.output_override = -1.0
	control._apply_due(NetworkTime.tick + SETTLE)
	grid.build() #(again, now that the grid has its control: it counts the lights too)
	var light : int = map.light_of_room("cafeteria")
	var supplier : Generator = null #a generator that powers the cafeteria's region: a whole-map one, or one of the region's own
	for generator : Generator in grid.generators:
		if supplier == null and (generator.scope == Generator.Scope.WHOLE_MAP or generator.region == control.light_region(light)):
			supplier = generator
	check(supplier != null, "something can power the cafeteria's region (%s)" % (supplier.name if supplier != null else "nothing"))
	for generator : Generator in grid.generators:
		grid.set_generator(generator, Generator.State.OFF)
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.light_count() == map.light_rooms.size() and map.light_rooms.size() > 0, "the control has a switch for every room light (%d)" % map.light_rooms.size())
	for index in control.light_count():
		check(not control.is_light_on(index), "light %s starts off" % map.light_rooms[index])
	check(light >= 0 and control.light_region(light) == map.region_of_room("cafeteria"), "the cafeteria has a light, paid for by its region")
	var light_refusals : Array = []
	control.light_refused.connect(func(index : int, reason : String) -> void: light_refusals.append([index, reason]))
	control.request_light(light, true)
	check(light_refusals.size() == 1 and light_refusals[0][1] == "power" and not control.is_light_pending(light), "switching a light on with no power in its region is refused")
	grid.set_generator(supplier, Generator.State.RUNNING)
	var free_before : float = grid.available(control.light_region(light))
	control.request_light(light, true)
	check(control.is_light_pending(light) and grid.has_load(PowerGrid.light_key(light)), "with power it is accepted, and its power is counted at once")
	check(is_equal_approx(grid.available(control.light_region(light)), free_before - grid.light_cost()) and is_equal_approx(grid.light_cost(), 1.0), "a light takes 1 pt/s from its region")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.is_light_on(light) and not control.is_light_pending(light), "on its tick the light comes on")
	control.request_light(light, false)
	check(not grid.has_load(PowerGrid.light_key(light)), "switching it off frees its power at once")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(not control.is_light_on(light), "and on its tick it goes off")
	control.request_light(light, true)
	control.request_door(east_door, FacilityDoor.State.CLOSED)
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.is_light_on(light) and east_door.state == FacilityDoor.State.CLOSED, "a light and a door both on in the east")
	supplier.output_override = grid.door_cost() + grid.light_cost() - 0.5 #a little short
	grid.set_generator(supplier, Generator.State.RUNNING)
	check(not grid.has_load(PowerGrid.light_key(light)) and grid.has_load(PowerGrid.door_key(east_door)), "short of power, the light goes before the door (shed_order)")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(not control.is_light_on(light) and east_door.state == FacilityDoor.State.CLOSED, "the light goes off and the door stays shut")
	supplier.output_override = -1.0
	grid.set_generator(supplier, Generator.State.RUNNING)
	var snapshot_lights : PackedByteArray = control.lights_on.duplicate()
	snapshot_lights[light] = 1
	var door_states : PackedByteArray = PackedByteArray()
	for door : FacilityDoor in map.doors:
		door_states.append(door.state)
	control._receive_snapshot(door_states, snapshot_lights) #(what a client gets when the game starts)
	check(control.is_light_on(light) and grid.has_load(PowerGrid.light_key(light)), "a snapshot from the lobby switches the lights it has on, and their power is counted")

	#the big wings map: its regions and generators add up too
	map.queue_free()
	var wings : FacilityMap = WINGS_SCENE.instantiate()
	add_child(wings)
	await get_tree().process_frame
	check(wings.regions.size() == 5, "the wings map has five regions (%d)" % wings.regions.size())
	var checker : Node = preload("res://tests/unit/test_facility_map.gd").new()
	checker.check_power(wings)
	failures += checker.failures
	checker.free()

	print("RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


##The door between two rooms. "corridor" stands for any corridor room, so the test does not depend on how the main corridor is split up and named.
func _door_between(map : FacilityMap, a : String, b : String) -> FacilityDoor:
	var is_a : Callable = func(id : String) -> bool: return id == a or (a == "corridor" and map.rooms.has(id) and map.rooms[id]["kind"] == "corridor")
	for door : FacilityDoor in map.doors:
		if (is_a.call(door.room_a) and door.room_b == b) or (door.room_a == b and is_a.call(door.room_b)):
			return door
	return null


func _generator(grid : PowerGrid, node_name : String) -> Generator:
	for generator : Generator in grid.generators:
		if generator.name == node_name:
			return generator
	return null
