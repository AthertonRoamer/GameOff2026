extends Node

# Offline test of the turrets (game/turrets): placed on the map, switched like a light (FacilityControl, the lobby decides), 5 pts/s from their region, refused
# without power, switched off first when power runs short, warming up after being switched on, shooting intruders in their cone and sight and never guards,
# turning no faster than they may, shot down and repaired, switched by hand by a technician only, and drawn and clicked on the door console's map.
# Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_turrets.tscn

const MAP_SCENE : PackedScene = preload("res://game/environment/facility_map.tscn")
const GENERATOR_SCENE : PackedScene = preload("res://game/power/generator.tscn")
const DOOR_SCREEN : PackedScene = preload("res://game/utility/door_map_screen.tscn")
const DUMMY : GDScript = preload("res://tests/unit/turret_test_dummy.gd")
const INTRUDER_ROLE : Role = preload("res://game/roles/infiltrator.tres")
const GUARD_ROLE : Role = preload("res://game/roles/guard.tres")
const TECHNICIAN_ROLE : Role = preload("res://game/roles/technician.tres")
const SETTLE : int = 100000 #a tick far ahead: every scheduled change is due
const DT : float = 1.0 / 60.0

var failures : int = 0
var shots : int = 0
var map : FacilityMap
var system : TurretSystem
var control : FacilityControl
var dummies : Array = []


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	map = MAP_SCENE.instantiate()
	map.doors_start = FacilityDoor.State.OPEN
	add_child(map)
	await get_tree().process_frame

	var generator : Generator = GENERATOR_SCENE.instantiate() #a whole-map generator of our own: powers every region through the pool
	generator.name = "TestGenerator"
	generator.scope = Generator.Scope.WHOLE_MAP
	map.props_node.add_child(generator)
	generator.global_position = map.to_global(Vector2(-4000, -4000))
	var grid : PowerGrid = PowerGrid.new()
	grid.facility = map
	grid.settings = PowerGrid.DEFAULT_SETTINGS.duplicate()
	add_child(grid)
	control = FacilityControl.new()
	control.facility = map
	control.power = grid
	add_child(control)
	grid.control = control
	var hitscan : HitscanManager = HitscanManager.new()
	add_child(hitscan)
	hitscan.targets = func() -> Array: return dummies
	hitscan.can_hit = func(target : Node) -> bool: return target.is_alive()
	hitscan.shot_hit.connect(func(shot : Dictionary, target : Node) -> void: target.take_damage(shot["damage"], shot["direction"]))
	system = TurretSystem.new()
	system.facility = map
	system.control = control
	system.hitscan = hitscan
	system.players = func() -> Array: return dummies
	add_child(system)
	system.set_physics_process(false) #stepped by hand below
	system.turret_fired.connect(func(_turret : Turret) -> void: shots += 1)
	system.build()
	control.can_work_turret_by_hand = system.may_switch_by_hand
	grid.build()
	for each : Generator in grid.generators:
		grid.set_generator(each, Generator.State.OFF)
	await get_tree().physics_frame
	await get_tree().physics_frame

	#on the map
	check(system.turrets.size() == 4 and control.turret_count() == 4, "the map has 4 turrets, each with a switch (%d)" % system.turrets.size())
	var every_region : bool = true
	for turret in system.turrets:
		every_region = every_region and turret.region != "" and control.turret_region(turret.index) == turret.region and map.room_at(map.to_local(turret.global_position)) != ""
		every_region = every_region and turret.get_node_or_null("TurretSwitch") is TurretSwitch
	check(every_region, "every turret stands in a room in a region, which pays for it, and has a switch for technicians")
	var vault : Turret = map.props_node.get_node("TurretVault")
	var index : int = vault.index
	check(not control.is_turret_on(index) and vault.phase == Turret.Phase.OFF, "turrets start off")
	check(is_equal_approx(grid.turret_cost(), 5.0), "a turret costs 5 pts/s")

	#switched like a light: refused without power, then accepted and paid for
	var refusals : Array = []
	control.turret_refused.connect(func(i : int, reason : String) -> void: refusals.append([i, reason]))
	control.request_turret(index, true)
	check(refusals.size() == 1 and refusals[0][1] == "power" and not control.is_turret_pending(index), "switching a turret on with no power is refused")
	grid.set_generator(generator, Generator.State.RUNNING)
	var free_before : float = grid.available(vault.region)
	control.request_turret(index, true)
	check(control.is_turret_pending(index) and grid.has_load(PowerGrid.turret_key(index)), "with power it is accepted, and its power is counted at once")
	check(is_equal_approx(grid.available(vault.region), free_before - 5.0), "it takes 5 pts/s from its region")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.is_turret_on(index), "on its tick it comes on")

	#warming up, then idle and silent with nobody about
	var intruder : Node2D = _dummy(INTRUDER_ROLE, Vector2(-3000, -3000))
	var guard : Node2D = _dummy(GUARD_ROLE, Vector2(-3000, -3100))
	_step(0.5)
	check(vault.phase == Turret.Phase.WARMING, "switched on, it warms up first")
	_step(vault.the_settings().warmup_seconds)
	check(vault.phase == Turret.Phase.IDLE and shots == 0, "then it watches, still, with nobody to shoot")
	var aim_before : float = vault.aim
	_step(0.5)
	check(is_equal_approx(vault.aim, aim_before) and not vault.is_turning(), "idle, it does not move (so it makes no sound)")

	#a guard in its cone is never shot at
	guard.global_position = map.to_global(Vector2(450, 720))
	_step(2.0)
	check(shots == 0 and vault.target == null and vault.phase == Turret.Phase.IDLE, "a guard in front of it is ignored")
	guard.global_position = map.to_global(Vector2(-3000, -3100))

	#an intruder in its cone: it turns, locks on, then fires bursts
	intruder.global_position = map.to_global(Vector2(450, 780))
	check(vault.can_see(intruder.global_position), "it can see an intruder in its cone, in range, with nothing in the way")
	_step(DT * 3)
	check(vault.target == intruder and (vault.phase == Turret.Phase.TRACKING or vault.phase == Turret.Phase.LOCKING), "it picks the intruder and turns to them")
	check(vault.is_turning(), "and it is turning (heard)")
	var lock_seconds : float = vault.the_settings().lock_on_seconds
	var waited : float = 0.0
	var saw_lock : bool = false
	while shots == 0 and waited < 5.0:
		_step(DT)
		waited += DT
		if vault.phase == Turret.Phase.LOCKING:
			saw_lock = vault.shows_laser()
	check(saw_lock, "while it locks on its laser shows")
	check(shots == 1 and waited >= lock_seconds - 0.05, "it fires only after locking on (%.2f s, lock %.2f s)" % [waited, lock_seconds])
	var health_before : float = intruder.health
	_step(1.0)
	check(shots > 1 and intruder.health < health_before, "it keeps firing and the intruder is hurt (%d shots, %.0f health)" % [shots, intruder.health])
	check(guard.health == 50.0, "the guard is not hurt")

	#a burst pauses
	var settings : TurretSettings = vault.the_settings()
	check(settings.spread_radians(0) < settings.spread_radians(4) and settings.spread_radians(1000) <= deg_to_rad(settings.spread_max_degrees) + 0.0001, "shots stray more as a burst goes on, up to the most")

	#friendly fire off: a guard in the line of fire is not hit, the intruder behind is
	intruder.health = 50.0
	guard.global_position = map.to_global(Vector2(400, 710)) #right in the line of fire
	intruder.global_position = map.to_global(Vector2(520, 690)) #(clear of the vault's crates: furniture is cover)
	_step(2.5)
	check(guard.health == 50.0 and intruder.health < 50.0, "its shots pass through a guard in the way and hit the intruder behind (guard %.0f, intruder %.0f, phase %d)" % [guard.health, intruder.health, vault.phase])
	guard.global_position = map.to_global(Vector2(-3000, -3100))
	check(not vault.can_see(map.to_global(Vector2(560, 740))), "furniture is cover: it can't see through the vault's crate")

	#outside its cone it sees nothing, and it gives up and turns back
	intruder.global_position = map.to_global(Vector2(350, 640)) #nearly straight up from it: outside a 110° cone facing east
	check(not vault.covers(intruder.global_position), "a point beside or behind it is outside its cone")
	_step(settings.lose_target_seconds + 0.2)
	var shots_now : int = shots
	_step(3.0)
	check(shots == shots_now and vault.target == null, "an intruder outside its cone is not shot")
	check(vault.phase == Turret.Phase.IDLE and absf(angle_difference(vault.aim, vault.facing())) < 0.01, "it turns back to its facing and goes idle")

	#turning is limited by its turn speed, and stays inside its cone
	intruder.global_position = map.to_global(Vector2(520, 800)) #about 24° off its facing
	var before : float = vault.aim
	_step(0.1)
	var turned : float = absf(angle_difference(before, vault.aim))
	check(turned > 0.0 and turned <= settings.turn_speed_radians() * 0.1 + 0.01, "it turns no faster than its turn speed (%.1f° in 0.1 s)" % rad_to_deg(turned))
	intruder.global_position = map.to_global(Vector2(-3000, -3000))
	_step(settings.lose_target_seconds + 3.0)

	#walls and closed doors block its view
	var door : FacilityDoor = _door_named("Door_archive_vault")
	var beyond : Vector2 = map.to_global(Vector2(543, 580)) #in the archive, through the vault's top door
	door.state = FacilityDoor.State.OPEN
	await get_tree().physics_frame
	await get_tree().physics_frame
	var open_sees : bool = vault.can_see(beyond)
	door.state = FacilityDoor.State.CLOSED
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(open_sees and not vault.can_see(beyond), "it sees through an open door, not a closed one")
	door.state = FacilityDoor.State.OPEN
	check(not vault.can_see(map.to_global(Vector2(300, 720))), "nor through a wall")

	#shot down: switched off, can't be switched on until a guard repairs it
	system.damage_turret(vault, 30.0)
	check(is_equal_approx(vault.health, settings.max_health - 30.0) and not vault.is_destroyed(), "a shot damages it")
	system.damage_turret(vault, 10000.0)
	check(vault.is_destroyed() and vault.health == 0.0, "enough damage shoots it down")
	check(not grid.has_load(PowerGrid.turret_key(index)), "its power is freed at once")
	control._apply_due(NetworkTime.tick + SETTLE)
	_step(DT)
	check(not control.is_turret_on(index) and vault.phase == Turret.Phase.DESTROYED, "and it is switched off")
	refusals.clear()
	control.request_turret(index, true)
	check(refusals.size() == 1 and refusals[0][1] == "destroyed" and not control.is_turret_pending(index), "switching a shot-down turret on is refused")
	var repairer : Node2D = _dummy(GUARD_ROLE, vault.global_position + Vector2(30, 0))
	var nosy : Node2D = _dummy(INTRUDER_ROLE, vault.global_position + Vector2(30, 0))
	check(vault.can_interact(repairer) and not vault.can_interact(nosy), "a guard can repair it, an intruder can't")
	var me : int = multiplayer.get_unique_id()
	var repairs : Array = []
	system.turret_repairing.connect(func(_turret : Turret, on : bool) -> void: repairs.append(on))
	system._decide_hold(me, index, true)
	check(system.is_repairing(vault) and repairs == [true], "while E is held on it, it is heard being repaired")
	system._decide_finish(me, index)
	check(vault.is_destroyed() and not system.is_repairing(vault) and repairs == [true, false], "a hold that ends too soon does not repair it, and the repair falls silent")
	system._decide_hold(me, index, true)
	system._holds[me]["since"] = Time.get_ticks_msec() - int(settings.repair_seconds * 1000.0)
	system._decide_finish(me, index)
	check(not vault.is_destroyed() and is_equal_approx(vault.health, settings.max_health) and not control.is_turret_on(index), "a full hold repairs it, at full health and still off")
	check(not system.is_repairing(vault) and repairs == [true, false, true, false], "and the repair falls silent when it is done")
	system.set_health(vault, 0.0)
	system._decide_hold(me, index, true)
	system._holds[me]["since"] = Time.get_ticks_msec() - int((settings.repair_seconds + TurretSystem.STALE_HOLD_SECONDS + 1.0) * 1000.0)
	system._drop_stale_holds()
	check(not system.is_repairing(vault) and system._holds.is_empty(), "a repair hold that was never ended (its player left) is let go")
	system.set_health(vault, settings.max_health)
	nosy.global_position = map.to_global(Vector2(-3000, -2900))

	#a technician switches it by hand; nobody else can
	var hand : Array = [repairer]
	system.player_of = func(_peer : int) -> Node2D: return hand[0]
	control.request_turret_by_hand(index, true)
	check(not control.is_turret_pending(index), "a guard who is not a technician can't switch it by hand")
	var technician : Node2D = _dummy(TECHNICIAN_ROLE, vault.global_position + Vector2(30, 0))
	hand[0] = technician
	var tswitch : TurretSwitch = vault.get_node("TurretSwitch")
	check(tswitch.can_interact(technician) and not tswitch.can_interact(repairer), "the switch is for technicians")
	control.request_turret_by_hand(index, true)
	check(control.is_turret_pending(index), "a technician by it switches it on")
	control._apply_due(NetworkTime.tick + SETTLE)
	technician.global_position = map.to_global(Vector2(-3000, -2800))
	control.request_turret_by_hand(index, false)
	check(not control.is_turret_pending(index) and control.is_turret_on(index), "not from across the map")
	technician.global_position = vault.global_position + Vector2(30, 0)
	control.request_turret_by_hand(index, false)
	control._apply_due(NetworkTime.tick + SETTLE)
	check(not control.is_turret_on(index), "and switches it off again")
	technician.global_position = map.to_global(Vector2(-3000, -2800))
	repairer.global_position = map.to_global(Vector2(-3000, -2700))
	system.player_of = Callable()

	#short of power: turrets go first
	control.request_turret(index, true)
	control.request_light(map.light_of_room(map.room_at(map.to_local(vault.global_position))), true)
	control._apply_due(NetworkTime.tick + SETTLE)
	var light : int = map.light_of_room(map.room_at(map.to_local(vault.global_position)))
	check(control.is_turret_on(index) and control.is_light_on(light), "a turret and a light both on")
	generator.output_override = grid.light_cost() + grid.turret_cost() - 0.5
	grid.set_generator(generator, Generator.State.RUNNING)
	check(not grid.has_load(PowerGrid.turret_key(index)) and grid.has_load(PowerGrid.light_key(light)), "short of power, the turret goes before the light")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(not control.is_turret_on(index) and control.is_light_on(light), "the turret goes off and the light stays on")
	generator.output_override = -1.0
	grid.set_generator(generator, Generator.State.RUNNING)

	#the lobby's snapshot carries the turrets
	var door_states : PackedByteArray = PackedByteArray()
	for each : FacilityDoor in map.doors:
		door_states.append(each.state)
	var turrets : PackedByteArray = control.turrets_on.duplicate()
	turrets[index] = 1
	control._receive_snapshot(door_states, control.lights_on.duplicate(), control.cameras_on.duplicate(), turrets)
	check(control.is_turret_on(index) and grid.has_load(PowerGrid.turret_key(index)), "a snapshot from the lobby switches the turrets it has on, and their power is counted")
	control.set_turret_now(index, false)
	check(not grid.has_load(PowerGrid.turret_key(index)), "a turret set off directly frees its power")

	#the door console: a click on a turret switches it; the other maps show every turret the same
	var screen : DoorMapScreen = DOOR_SCREEN.instantiate()
	screen.facility = map
	screen.control = control
	add_child(screen)
	screen.size = Vector2(1280, 720)
	screen.open()
	await get_tree().process_frame
	var view : FacilityMapView = screen.map
	var spot : Vector2 = map.to_local(vault.global_position)
	view.center_on(spot)
	var at : Vector2 = view.world_to_screen(spot)
	var layer : TurretsLayer = screen.turrets_layer
	check(layer.interactive and layer.turret_at(spot) == index, "the console's turrets layer finds the turret under the mouse")
	var light_was : bool = control.is_light_on(light)
	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, false, at))
	check(control.is_turret_pending(index) and not control.is_light_pending(light), "a click on a turret switches it, not its room's light")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.is_turret_on(index) and control.is_light_on(light) == light_was, "and it comes on")
	check(TurretsLayer.state_colour(vault, control) == TurretsLayer.WARMING_COLOUR, "the console shows it warming up")
	_step(settings.warmup_seconds + 0.1)
	check(TurretsLayer.state_colour(vault, control) == TurretsLayer.ON_COLOUR, "then on")
	check(view.icon_label_at(at).begins_with("Turret: on"), "its label on the console says it is on")
	check(screen.toggle_turret(index) and control.is_turret_pending(index), "toggle_turret asks for it the way a click does")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(TurretsLayer.state_colour(vault, control) == TurretsLayer.OFF_COLOUR, "and off")
	layer.interactive = false #as on the minimap and the full map
	check(view.icon_label_at(at) == "Turret", "on the other maps its label does not say whether it is on")
	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, false, at))
	check(not control.is_turret_pending(index), "and a click there does not switch it")
	layer.interactive = true

	#hover labels: a small icon wins over a label for its whole room (the spawn map: a turret in a spawn room)
	screen.regions_layer.room_labels = true
	check(view.icon_label_at(at).begins_with("Turret"), "over a turret, its own label shows, not its room's")
	var room_spot : Vector2 = map.to_local(vault.global_position) + Vector2(150, 40)
	check(view.icon_label_at(view.world_to_screen(room_spot)) == "Relic room", "elsewhere in the vault, the area label over the zone's says what it is: a relic room")
	screen.get_node("Map/RelicRooms").visible = false
	check(view.icon_label_at(view.world_to_screen(room_spot)).begins_with("Vault, in the"), "with nothing over it, the room and its power zone are named (%s)" % view.icon_label_at(view.world_to_screen(room_spot)))
	screen.get_node("Map/RelicRooms").visible = true
	screen.regions_layer.room_labels = false
	screen.close()

	#consoles beep when a change made from them is accepted (not a technician's by hand), heard round the console
	var operated : Array = []
	control.operated.connect(func(peer : int, powered : bool) -> void: operated.append([peer, powered]))
	control.request_turret(index, true)
	control.request_turret(index, false)
	control._apply_due(NetworkTime.tick + SETTLE)
	check(operated == [[me, true], [me, false]], "a console's change is reported, as taking power or freeing it")
	var door0 : FacilityDoor = map.doors[0]
	control.request_door(door0, FacilityDoor.State.CLOSED if door0.state == FacilityDoor.State.OPEN else FacilityDoor.State.OPEN)
	check(operated.size() == 3, "a door from the console too")
	control._apply_due(NetworkTime.tick + SETTLE)
	system.player_of = func(_peer : int) -> Node2D: return technician
	technician.global_position = vault.global_position + Vector2(30, 0)
	control.request_turret_by_hand(index, true)
	check(control.is_turret_pending(index) and operated.size() == 3, "a technician's switch by hand is not a console's (no beep)")
	control._apply_due(NetworkTime.tick + SETTLE)
	system.player_of = Callable()
	var consoles : UtilityConsoles = UtilityConsoles.new()
	consoles.facility = map
	consoles.control = control
	add_child(consoles)
	consoles.build()
	var beeps : Array = []
	consoles.beeped.connect(func(where : Vector2, powered : bool) -> void: beeps.append([where, powered]))
	consoles.beep_for(me, true)
	check(beeps.is_empty(), "nobody at a console: no beep")
	consoles._set_occupant(0, me)
	consoles.beep_for(me, false)
	check(beeps.size() == 1 and beeps[0][0] == consoles.panels[0].global_position and beeps[0][1] == false, "the console the player is at beeps, where it stands")
	consoles.queue_free()

	screen.queue_free()
	map.queue_free()
	await get_tree().process_frame

	print("RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _dummy(role : Role, at : Vector2) -> Node2D:
	var dummy : Node2D = DUMMY.new()
	dummy.role = role
	add_child(dummy)
	dummy.global_position = at #(the map is at the origin: its points are world points)
	dummies.append(dummy)
	return dummy


func _step(seconds : float) -> void:
	for i in maxi(1, roundi(seconds / DT)):
		system._physics_process(DT)
		for turret in system.turrets:
			turret._process(DT)


func _door_named(door_name : String) -> FacilityDoor:
	for door : FacilityDoor in map.doors:
		if door.name == door_name:
			return door
	return null


func _mouse(index : MouseButton, pressed : bool, at : Vector2) -> InputEventMouseButton:
	var event : InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = at
	return event
