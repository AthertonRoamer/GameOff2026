extends Node

# Offline test for dropping and using items, on the real game scene: G drops, everything falls when a player dies (the gunner's shotgun, the shade's pistol), a dropped
# relic keeps its rule, medicine heals half, the medic is handed medicine every minute, the technician's portable generator powers its region while it is down, intruders
# start generators, generators are heard, and the maps name the icon under the mouse. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_items.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const GUARD : Role = preload("res://game/roles/guard.tres")
const SHADE : Role = preload("res://game/roles/shade.tres")
const GUNNER : Role = preload("res://game/roles/gunner.tres")
const MEDIC : Role = preload("res://game/roles/medic.tres")
const TECHNICIAN : Role = preload("res://game/roles/technician.tres")
const INFILTRATOR : Role = preload("res://game/roles/infiltrator.tres")
const SHOTGUN : Gun = preload("res://game/items/guns/shotgun.tres")
const SUPPRESSED : Gun = preload("res://game/items/guns/pistol_suppressed.tres")
const MEDICINE : Medicine = preload("res://game/items/medicine/medicine.tres")

var failures : int = 0
var game : Game
var pickups : PickupControl
var players : Dictionary = {}


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func make_player(id : int, role : Role, at : Vector2) -> Player:
	var player : Player = game.spawner.player_scene.instantiate()
	player.name = str(id)
	player.role = role
	role.apply(player)
	game.level.actors.add_child(player)
	player.global_position = at
	players[id] = player
	return player


func settle() -> void:
	pickups._apply_due(NetworkTime.tick + pickups.apply_delay_ticks + 1)


func pickups_of(item_class : Variant) -> Array:
	return pickups.get_pickups().filter(func(p : Variant) -> bool: return is_instance_valid(p) and is_instance_of((p as Pickup).item, item_class))


func slot_of(player : Player, item : Item) -> int:
	return player.inventory.slots.find(item)


## A floor point in a room that is in a power region, and the region.
func region_spot() -> Array:
	var map : FacilityMap = game.level.facility
	for id : String in map.rooms:
		var at : Vector2 = map.to_global(map.room_center_px(id))
		var region : String = map.region_at(map.to_local(at))
		if region != "" and map.room_at(map.to_local(at)) == id:
			return [at, region]
	return [Vector2.ZERO, ""]


func _ready() -> void:
	game = GAME_SCENE.instantiate()
	add_child(game)
	pickups = game.pickups
	pickups.player_lookup = func(id : int) -> Player: return players.get(id)
	game.abilities.player_lookup = pickups.player_lookup
	game.abilities.players = func() -> Array: return players.values()
	await get_tree().process_frame
	var spot : Array = region_spot()
	var here : Vector2 = spot[0]
	var region : String = spot[1]
	check(region != "", "found a room in a power region to test in (%s)" % region)

	#dying drops everything: the gunner's shotgun and the shade's suppressed pistol
	var gunner : Player = make_player(1, GUNNER, here)
	var shade : Player = make_player(2, SHADE, here + Vector2(60, 0))
	gunner.health = 0.0
	shade.health = 0.0
	pickups.drop_all(gunner)
	pickups.drop_all(shade)
	settle()
	check(gunner.inventory.slots.all(func(i : Item) -> bool: return i == null), "a dead gunner carries nothing")
	check(shade.inventory.slots.all(func(i : Item) -> bool: return i == null), "nor a dead shade")
	var floor_guns : Array = pickups_of(Gun)
	var shotgun_pickup : Pickup = null
	for p : Pickup in floor_guns:
		if p.item == SHOTGUN:
			shotgun_pickup = p
	check(shotgun_pickup != null and shotgun_pickup.global_position.distance_to(here) < 80.0, "the shotgun lies by the gunner's body")
	check(floor_guns.any(func(p : Pickup) -> bool: return p.item == SUPPRESSED), "the suppressed pistol lies by the shade's")
	check(shotgun_pickup != null and shotgun_pickup.pickup_id >= PickupControl.DROP_ID_BASE, "a dropped item is numbered by the lobby")

	#anyone can pick a dropped gun up, and drop it again with G
	var guard : Player = make_player(3, GUARD, here + Vector2(0, 30))
	guard.global_position = shotgun_pickup.global_position + Vector2(10, 0)
	pickups._decide(3, shotgun_pickup.pickup_id)
	settle()
	var shotgun_slot : int = slot_of(guard, SHOTGUN)
	check(shotgun_slot >= 0, "a guard picks the shotgun up")
	pickups._decide_drop(3, shotgun_slot)
	settle()
	check(slot_of(guard, SHOTGUN) < 0 and pickups_of(Gun).any(func(p : Pickup) -> bool: return p.item == SHOTGUN), "G drops it again")
	pickups._decide_drop(3, 3) #(an empty slot)
	check(pickups._pending.is_empty(), "an empty slot drops nothing")
	guard.inventory.magazine = 12
	guard.inventory.put_in_slot(1, SHOTGUN)
	guard.inventory.active_slot = 1
	guard.inventory._rollback_tick(0.0, NetworkTime.tick, true)
	check(guard.inventory.magazine <= SHOTGUN.magazine_size, "a shotgun picked up holds no more than its two shells")
	guard.inventory.put_in_slot(1, null)

	#ammo dropped takes the supply with it
	var ammo : AmmoItem = preload("res://game/items/ammo/ammo_box.tres")
	ammo.put_into(guard.inventory, 2, NetworkTime.tick)
	var supply : int = guard.inventory.reserve_now()
	pickups._decide_drop(3, 2)
	settle()
	var boxes : Array = pickups_of(AmmoItem)
	check(guard.inventory.reserve_at(NetworkTime.tick + pickups.apply_delay_ticks + 1) == 0 and boxes.any(func(p : Pickup) -> bool: return (p.item as AmmoItem).rounds == supply), "dropped ammo takes all %d rounds with it" % supply)

	#a dropped relic keeps its rule: defenders still can't take it
	var relic : Artifact = game.artifact_placer.artifacts[0]
	var intruder : Player = make_player(4, INFILTRATOR, here + Vector2(-40, 0))
	intruder.team = Team.ATTACKERS
	guard.team = Team.DEFENDERS
	intruder.inventory.put_in_slot(1, relic)
	pickups._decide_drop(4, 1)
	settle()
	var relic_pickups : Array = pickups_of(Artifact).filter(func(p : Pickup) -> bool: return p.item == relic)
	check(relic_pickups.size() == 1, "an intruder drops the relic")
	if relic_pickups.size() == 1:
		var dropped_relic : Pickup = relic_pickups[0]
		guard.global_position = dropped_relic.global_position + Vector2(10, 0)
		check(not dropped_relic.can_interact(guard), "a defending guard still can't pick the relic up")
		pickups._decide(3, dropped_relic.pickup_id)
		check(pickups._pending.is_empty(), "and the lobby refuses it")
		check(dropped_relic.can_interact(intruder), "an intruder can")

	#medicine: half the health back, and never past full
	var medic : Player = make_player(5, MEDIC, here + Vector2(0, -40))
	medic.health = 10.0
	medic.inventory.put_in_slot(2, MEDICINE)
	pickups._decide_use(5, 2)
	settle()
	check(is_equal_approx(medic.health, 10.0 + medic.starting_health * 0.5) and medic.inventory.slots[2] == null, "medicine gives half the health back and is used up (%.0f of %.0f)" % [medic.health, medic.starting_health])
	medic.health = medic.starting_health
	medic.inventory.put_in_slot(2, MEDICINE)
	pickups._decide_use(5, 2)
	settle()
	check(medic.inventory.slots[2] == MEDICINE, "at full health it can't be used")
	var interactor : PlayerInteractor = medic.interactor
	medic.inventory.active_slot = 2
	medic.input.active = true
	interactor._find_target()
	check(interactor.target != interactor.item_use, "and at full health it offers no heal")
	medic.health = medic.starting_health - 2.0
	interactor._find_target()
	check(interactor.target == interactor.item_use and interactor.target.get_prompt() == "Hold E to heal", "chosen while hurt, the HUD says \"Hold E to heal\"")
	check(interactor.target.hold_seconds(medic) > 0.5, "it has to be held (%.1f s, with a progress bar)" % interactor.target.hold_seconds(medic))
	var progress : Array[float] = []
	interactor.hold_progress_changed.connect(func(p : float) -> void: progress.append(p))
	interactor.start_hold(interactor.target)
	check(not medic.input.active and progress == [0.0], "holding E starts the bar and keeps the player still")
	interactor._end_hold()
	var lookup : Callable = pickups.player_lookup
	pickups.player_lookup = func(id : int) -> Player: return medic if id == multiplayer.get_unique_id() else players.get(id) #(offline, the asker is this peer: the medic)
	interactor.target.interact(medic) #(the hold finishing: a hold needs E really held, so the test finishes it by hand)
	settle()
	pickups.player_lookup = lookup
	check(medic.inventory.slots[2] == null, "when the bar is full the medicine is used up")
	pickups._decide_use(5, 2)
	settle()
	check(is_equal_approx(medic.health, medic.starting_health), "and it never heals past full")
	medic.inventory.active_slot = 0

	#the medic can make a dose every minute, by holding Q
	var abilities : AbilityControl = game.abilities
	abilities.start_medicine()
	abilities._process(MEDIC.medicine_seconds - 1.0)
	check(pickups._pending.is_empty(), "no medicine before the minute is up")
	abilities._process(2.0)
	settle()
	check(slot_of(medic, MEDICINE) < 0 and abilities._medicine_clock[medic] >= MEDIC.medicine_seconds, "after a minute a dose is ready, but not made by itself")
	abilities._decide_make(5)
	settle()
	check(slot_of(medic, MEDICINE) < 0, "it is not made without holding Q")
	abilities._decide_make_hold(5, true)
	abilities._decide_make(5)
	settle()
	check(slot_of(medic, MEDICINE) < 0, "nor with Q only tapped")
	abilities._decide_make_hold(5, true)
	abilities._make_holds[5] = Time.get_ticks_msec() - int(MEDIC.medicine_make_seconds * 1000.0) - 50
	abilities._decide_make(5)
	settle()
	check(slot_of(medic, MEDICINE) >= 0 and abilities._medicine_clock[medic] == 0.0, "held %.0f s, the dose is made and the time starts over" % MEDIC.medicine_make_seconds)
	var maker : MedicineMaker = medic.interactor.medicine_maker
	abilities._medicine_sync(MEDIC.medicine_seconds, MEDIC.medicine_seconds, true)
	check(maker.can_interact(medic) and is_equal_approx(maker.hold_seconds(medic), MEDIC.medicine_make_seconds), "with the bar full, the medic can hold Q (a %.0f s progress bar)" % MEDIC.medicine_make_seconds)
	maker.interact(medic)
	check(not abilities.own_medicine_ready and abilities.own_medicine_clock == 0.0, "making it starts the bar over at once")
	abilities._medicine_sync(10.0, MEDIC.medicine_seconds, false)
	check(not maker.can_interact(medic), "before the bar is full, Q does nothing")
	check(slot_of(guard, MEDICINE) < 0, "a guard who is not a medic gets none")
	var hud : CanvasLayer = game.player_hud
	hud._player = medic
	abilities._medicine_sync(30.0, MEDIC.medicine_seconds, false) #(what the lobby tells the medic's own peer)
	hud._show_medicine()
	check(hud._medicine_bar.visible and is_equal_approx(hud._medicine_bar.value, 30.0 / MEDIC.medicine_seconds), "the medic's HUD bar shows how far along the next dose is")
	check(hud._medicine_label.text.contains("%ds" % ceili(MEDIC.medicine_seconds - 30.0)), "and how many seconds are left (%s)" % hud._medicine_label.text)
	abilities._process(1.0)
	check(is_equal_approx(abilities.own_medicine_clock, 31.0), "it counts on between the lobby's updates")
	abilities._medicine_sync(MEDIC.medicine_seconds, MEDIC.medicine_seconds, true)
	hud._show_medicine()
	check(hud._medicine_bar.value == 1.0 and hud._medicine_label.text.contains("hold Q"), "full, it says to hold Q (%s)" % hud._medicine_label.text)
	hud._player = guard
	hud._show_medicine()
	check(not hud._medicine_bar.visible, "a guard who is not a medic has no bar")
	hud._player = null

	#the technician's portable generator: put down, it powers the region; picked up, it stops
	var grid : PowerGrid = game.level.power
	var technician : Player = make_player(6, TECHNICIAN, here)
	var generator_item : Item = null
	for item : Item in technician.inventory.slots:
		if item is PortableGeneratorItem:
			generator_item = item
	check(generator_item != null, "the technician starts with a portable generator in a slot")
	var before : float = grid.local_supply(region)
	var hums_before : int = game.level.sound.hum_count()
	var heard : Array = []
	grid.generator_switched.connect(func(key : String, _at : Vector2, running : bool, announce : bool) -> void: heard.append([key, running, announce]))
	pickups._decide_use(6, slot_of(technician, generator_item))
	settle()
	var placed : Array = pickups_of(PortableGeneratorItem)
	check(placed.size() == 1 and slot_of(technician, generator_item) < 0, "a click puts it down, out of the slot")
	var normal : float = grid.settings.region_generator_output
	check(is_equal_approx(grid.local_supply(region), before + normal), "it adds %.0f pts/s to the region it stands in, the same as a facility generator" % normal)
	check(heard.any(func(e : Array) -> bool: return e[1] and e[2]), "it is heard starting up")
	check(game.level.sound.hum_count() == hums_before + 1, "and it hums")
	if placed.size() == 1:
		var down : Pickup = placed[0]
		check(down.get_prompt().contains("pick up"), "E picks it up (%s)" % down.get_prompt())
		technician.input.active = true
		technician.interactor._find_target()
		check(technician.interactor.target == down, "standing on it, the technician is shown the prompt to pick it up")
		pickups._decide(6, down.pickup_id)
		settle()
		check(slot_of(technician, generator_item) >= 0 and grid.portables.is_empty() and is_equal_approx(grid.local_supply(region), before), "picked up, it is back in a slot and the region loses its power")
		check(game.level.sound.hum_count() == hums_before, "and its hum stops")

	#the technician opens and closes the door they stand next to; closing needs power
	var control : FacilityControl = game.level.control
	game.level.player_lookup = pickups.player_lookup
	var door_to_work : FacilityDoor = null
	for candidate : FacilityDoor in game.level.facility.doors:
		if candidate.state != FacilityDoor.State.LOCKED:
			door_to_work = candidate
			break
	var door_switch : DoorSwitch = door_to_work.get_node("DoorSwitch")
	var door_region : String = game.level.facility.region_of_door(door_to_work)
	control._decide(6, door_to_work.door_index, FacilityDoor.State.OPEN, true) #(far off: refused)
	check(not control.is_pending(door_to_work) or door_to_work.state == FacilityDoor.State.OPEN, "a technician far from a door can't work it")
	technician.global_position = door_to_work.global_position + Vector2(0, 30)
	guard.global_position = door_to_work.global_position + Vector2(0, -30)
	check(door_switch.can_interact(technician) and door_switch.is_in_reach(technician.global_position), "next to a door, the technician can work it")
	check(not door_switch.can_interact(guard), "a guard can't (they use the door console)")
	door_to_work.state = FacilityDoor.State.CLOSED
	check(door_switch.get_prompt() == "E   open the door", "a shut door: E opens it")
	control._decide(6, door_to_work.door_index, FacilityDoor.State.OPEN, true)
	control._apply_due(NetworkTime.tick + control.apply_delay_ticks + 1)
	check(door_to_work.state == FacilityDoor.State.OPEN, "and it opens")
	control._decide(3, door_to_work.door_index, FacilityDoor.State.CLOSED, true)
	control._apply_due(NetworkTime.tick + control.apply_delay_ticks + 1)
	check(door_to_work.state == FacilityDoor.State.OPEN, "the lobby refuses a guard working it by hand")
	for generator : Generator in grid.generators:
		grid.set_generator(generator, Generator.State.OFF)
	var portables_before : Dictionary = grid.portables.duplicate()
	grid.portables.clear()
	grid._recount()
	check(door_switch.get_prompt().begins_with("No power"), "with no power in its region, it says it can't be closed (%s)" % door_switch.get_prompt())
	control._decide(6, door_to_work.door_index, FacilityDoor.State.CLOSED, true)
	control._apply_due(NetworkTime.tick + control.apply_delay_ticks + 1)
	check(door_to_work.state == FacilityDoor.State.OPEN, "and the lobby won't close it")
	grid.add_portable("test", door_region, 50.0, door_to_work.global_position)
	check(door_switch.get_prompt() == "E   close the door", "with power, E closes it")
	control._decide(6, door_to_work.door_index, FacilityDoor.State.CLOSED, true)
	control._apply_due(NetworkTime.tick + control.apply_delay_ticks + 1)
	check(door_to_work.state == FacilityDoor.State.CLOSED, "and it closes")
	grid.remove_portable("test")
	grid.portables.merge(portables_before)

	#generators: intruders turn them on and off, guards repair them; starting one is heard
	var fixed : Generator = grid.generators[0] if not grid.generators.is_empty() else null
	check(fixed != null, "the map has generators")
	if fixed != null:
		grid.set_generator(fixed, Generator.State.OFF)
		check(fixed.can_interact(intruder), "an intruder can start a generator that is off")
		heard.clear()
		grid.set_generator(fixed, Generator.State.RUNNING)
		check(fixed.can_interact(intruder), "and turn a running one off")
		check(heard.any(func(e : Array) -> bool: return e[0] == PowerGrid.generator_key(fixed) and e[1] and e[2]), "a generator starting is heard")
		check(game.level.sound._hums.has(PowerGrid.generator_key(fixed)), "and it hums while it runs")
		grid.set_generator(fixed, Generator.State.DESTROYED, 0.0)
		check(not fixed.can_interact(intruder) and fixed.can_interact(guard), "only a guard repairs a shot-down one")
		check(not game.level.sound._hums.has(PowerGrid.generator_key(fixed)), "a stopped generator is quiet")

	#the maps name the icon under the mouse
	var minimap : Minimap = game.player_hud.minimap
	minimap.size = Vector2(240, 240)
	var map : FacilityMap = game.level.facility
	var door : FacilityDoor = map.doors[0]
	minimap.center_on(door.position)
	check(minimap.icon_label_at(minimap.world_to_screen(door.position)).begins_with("Door"), "the minimap names a door under the mouse (%s)" % minimap.icon_label_at(minimap.world_to_screen(door.position)))
	if fixed != null:
		(minimap.get_node("Generators") as GeneratorsLayer).grid = grid
		var at : Vector2 = map.to_local(fixed.global_position)
		minimap.center_on(at)
		check(minimap.icon_label_at(minimap.world_to_screen(at)).begins_with("Generator"), "and a generator (%s)" % minimap.icon_label_at(minimap.world_to_screen(at)))
	minimap.center_on(Vector2(-90000, -90000))
	check(minimap.icon_label_at(Vector2(2, 2)) == "", "and nothing where there is nothing")
	var door_screen : Node = load("res://game/utility/door_map_screen.tscn").instantiate()
	add_child(door_screen)
	var door_view : FacilityMapView = door_screen.find_children("*", "FacilityMapView", true, false)[0]
	door_view.size = Vector2(500, 400)
	door_view.facility = map
	door_view.center_on(door.position)
	check(door_view.icon_label_at(door_view.world_to_screen(door.position)).begins_with("Door: "), "the door panel's map says the door's state (%s)" % door_view.icon_label_at(door_view.world_to_screen(door.position)))

	print("RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)
