extends Node

# Offline test for the found gadgets (knife, smoke bomb, tripwire, coms hacker, night vision, radar) and the rooms' own item lists, on the real level.
# Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_gadgets.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const PLAYER_SCENE : PackedScene = preload("res://game/player/player.tscn")
const KNIFE : Knife = preload("res://game/items/knife/knife.tres")
const SMOKE : Item = preload("res://game/items/smoke_bomb/smoke_bomb.tres")
const TRIPWIRE : Item = preload("res://game/items/tripwire/tripwire.tres")
const HACKER : Item = preload("res://game/items/coms_hacker/coms_hacker.tres")
const NIGHT_VISION : Item = preload("res://game/items/night_vision/night_vision.tres")
const RADAR : Item = preload("res://game/items/radar/radar.tres")

var failures : int = 0
var game : Game
var pickups : PickupControl
var gadgets : GadgetSystem
var me : Player #member 1: this peer (offline, the lobby)
var other : Player #member 2


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func make_rng(seed_value : int) -> RandomNumberGenerator:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func make_player(id : int, at : Vector2) -> Player:
	var player : Player = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.starting_items = [] as Array[Item]
	player.position = at
	game.level.actors.add_child(player)
	return player


## Lets a change the lobby accepted arrive.
func settle() -> void:
	pickups._apply_due(NetworkTime.tick + pickups.apply_delay_ticks)


func newest_pickup() -> Pickup:
	var best : Pickup = null
	for entry in pickups.get_pickups():
		if is_instance_valid(entry) and (best == null or (entry as Pickup).pickup_id > best.pickup_id):
			best = entry
	return best


func _ready() -> void:
	game = GAME_SCENE.instantiate()
	add_child(game)
	pickups = game.pickups
	gadgets = game.gadgets
	var map : FacilityMap = game.level.facility
	var spot : Vector2 = map.to_global(map.room_center_px(map.start_room()))
	me = make_player(1, spot)
	other = make_player(2, spot + Vector2(300, 0))
	var everyone : Array = [me, other]
	var lookup : Callable = func(id : int) -> Player: return me if id == 1 else (other if id == 2 else null)
	pickups.player_lookup = lookup
	gadgets.players = func() -> Array: return everyone
	gadgets.player_lookup = lookup
	gadgets.local_player = func() -> Player: return me
	var sight : PlayerSight = gadgets.sight
	sight.players = func() -> Array: return everyone
	sight.local_player = func() -> Player: return me
	await get_tree().physics_frame
	await get_tree().physics_frame

	#the items
	check(KNIFE is Knife and KNIFE.drawable, "the knife is a weapon held out like a gun")
	check(SMOKE.click_use == Item.ClickUse.THROW, "a smoke bomb is thrown")
	check(TRIPWIRE.click_use == Item.ClickUse.PLACE and HACKER.click_use == Item.ClickUse.PLACE, "a tripwire and a coms hacker are put down")
	check(NIGHT_VISION.click_use == Item.ClickUse.NONE and RADAR.click_use == Item.ClickUse.NONE, "night vision and the radar work while carried")
	var listed : Array[Item] = game.item_spawner.items()
	check([KNIFE, SMOKE, TRIPWIRE, HACKER, NIGHT_VISION, RADAR].all(func(item : Item) -> bool: return listed.has(item)), "all six can be found on the map")

	#the rooms' own lists
	var rooms : Array[FacilityRoom] = map.room_nodes().filter(func(room : FacilityRoom) -> bool: return not room.is_exit() and map.has_room(room.room_id()))
	for room : FacilityRoom in rooms:
		room.spawns_items = true
		room.item_chance = 100
		room.item_pool = [] as Array[Item]
	var armory : FacilityRoom = rooms[0]
	armory.item_pool = [KNIFE] as Array[Item]
	map.build()
	check(armory.has_own_pool() and not rooms[1].has_own_pool(), "a room can have a list of its own")
	var spawner : ItemSpawner = game.item_spawner
	check(spawner.all_items().has(KNIFE) and spawner.all_items().size() == listed.size(), "every item that can turn up is listed once")
	var only_knives : bool = true
	var others_vary : Dictionary = {}
	for i in 20:
		var rolled : Dictionary = spawner.roll(make_rng(i))
		for j in rolled["items"].size():
			var room_id : String = map.room_at(map.to_local(rolled["at"][j]))
			var item : Item = spawner.all_items()[rolled["items"][j]]
			if room_id == armory.room_id():
				only_knives = only_knives and item == KNIFE
			else:
				others_vary[item] = true
	check(only_knives, "a room with its own list only gets items from it")
	check(others_vary.size() > 1, "the other rooms still get the map's items")
	for room : FacilityRoom in rooms:
		room.spawns_items = false
	armory.item_pool = [] as Array[Item]
	map.build()

	#knife: silent, and a blow from behind is the deadly one
	var hitscan : HitscanManager = game.level.hitscan
	other.skin.torso.global_rotation = PI / 2.0 #faces +x (Vector2.from_angle(rotation - PI/2))
	check(HitscanManager.is_from_behind(other, Vector2.RIGHT), "a blow travelling the way they face is from behind")
	check(not HitscanManager.is_from_behind(other, Vector2.LEFT), "one to their face is not")
	check(not HitscanManager.is_from_behind(other, Vector2.UP), "nor one from the side")
	check(KNIFE.damage * KNIFE.backstab_multiplier >= other.starting_health and KNIFE.damage < other.starting_health, "a backstab kills a fresh player, a blow from the front does not")
	var shots_before : int = hitscan.shots_seen
	var tracers_before : int = hitscan.get_child_count()
	var doors_opened : Array = [0]
	var count_door : Callable = func(_door : FacilityDoor) -> void: doors_opened[0] += 1
	hitscan.door_shot.connect(count_door)
	var shot : bool = hitscan.fire(me, 1, me.global_position, Vector2.UP, NetworkTime.tick + 500, KNIFE.damage, 60.0, 0, Color.TRANSPARENT, 1, 0.0, true, 2.0)
	check(shot and hitscan.get_child_count() == tracers_before and hitscan.shots_seen == shots_before, "a blow draws no tracer")
	hitscan.door_shot.disconnect(count_door)
	check(doors_opened[0] == 0, "and opens no door")

	#smoke bomb: thrown, it lands short of walls, and its cloud hides what is behind it
	me.inventory.put_in_slot(0, SMOKE)
	me.inventory.active_slot = 0
	me.input.aim = me.global_position + Vector2(200, 0)
	pickups.request_use(0)
	settle()
	check(me.inventory.slots[0] == null, "throwing it takes it out of the inventory")
	var clouds : Array[Node] = get_tree().get_nodes_in_group(SmokeCloud.GROUP)
	check(clouds.size() == 1, "and a cloud bursts where it lands")
	var cloud : SmokeCloud = clouds[0] if not clouds.is_empty() else null
	if cloud != null:
		check(cloud.global_position.distance_to(me.global_position) <= SMOKE.throw_range_px + 1.0, "no further than it can be thrown (%.0f px)" % cloud.global_position.distance_to(me.global_position))
		cloud.age = cloud.grow_seconds + 0.5 #(fully grown)
		var c : Vector2 = cloud.global_position
		var r : float = cloud.reach()
		check(SmokeCloud.blocks(get_tree(), c - Vector2(r + 50, 0), c + Vector2(r + 50, 0)), "a line of sight through the cloud is blocked")
		check(not SmokeCloud.blocks(get_tree(), c + Vector2(-r - 50, r + 10), c + Vector2(r + 50, r + 10)), "one past it is not")
		check(not SmokeCloud.blocks(get_tree(), c, c + Vector2(20, 0)), "someone in it sees who is right next to them")
		cloud.age = cloud.lifetime() - 0.01
		check(not SmokeCloud.blocks(get_tree(), c - Vector2(r + 50, 0), c + Vector2(r + 50, 0)), "it thins away at the end")
		cloud.age = cloud.grow_seconds + 0.5
		var turret : Turret = null
		for node : Node in map.find_children("*", "Turret", true, false):
			turret = node
			break
		if turret != null:
			var target : Vector2 = turret.global_position + Vector2.from_angle(turret.global_rotation) * 120.0
			var saw : bool = turret.can_see(target)
			cloud.global_position = turret.global_position.lerp(target, 0.5)
			check(not turret.can_see(target), "a turret can't see through it (saw before: %s)" % saw)
		cloud.queue_free()
	var thrown_far : Vector2 = pickups._landing_of(me, SMOKE)
	check(thrown_far.distance_to(me.global_position) <= SMOKE.throw_range_px + 0.5, "a throw is cut to its range")

	#tripwire: put down, it is strung across the way they face, and tells only its owner
	me.global_position = spot
	other.global_position = spot + Vector2(300, 0)
	me.inventory.put_in_slot(0, TRIPWIRE)
	me.input.aim = me.global_position + Vector2(0, -100) #facing up: the wire runs left to right
	pickups.request_use(0)
	settle()
	var wire_pickup : Pickup = newest_pickup()
	check(wire_pickup != null and wire_pickup.item == TRIPWIRE and wire_pickup.placed_by == 1, "putting it down leaves it armed for its owner")
	check(gadgets.tripwire_count() == 1, "and the gadgets know of it")
	var wire : Dictionary = gadgets._tripwires.values()[0] if gadgets.tripwire_count() > 0 else {}
	if not wire.is_empty():
		var a : Vector2 = wire["a"]
		var b : Vector2 = wire["b"]
		check(absf(a.y - b.y) < 1.0 and a.distance_to(b) > 40.0, "the wire runs across the way they faced (%s to %s)" % [a, b])
		var pings_before : int = game.map_intel.pings.size()
		var trips_before : int = gadgets.trips_sent
		var cross_x : float = (a.x + b.x) / 2.0
		me.global_position = Vector2(cross_x, a.y - 30.0)
		gadgets._physics_process(0.0)
		me.global_position = Vector2(cross_x, a.y + 30.0)
		gadgets._physics_process(0.0)
		check(gadgets.trips_sent == trips_before, "its owner crossing it trips nothing")
		other.global_position = Vector2(cross_x, a.y - 30.0)
		gadgets._physics_process(0.0)
		other.global_position = Vector2(cross_x, a.y + 30.0)
		gadgets._physics_process(0.0)
		check(gadgets.trips_sent == trips_before + 1, "someone else crossing it trips it")
		check(game.map_intel.pings.size() == pings_before + 1 and game.map_intel.pings[-1]["label"] == "Tripwire", "and its owner gets a ping where it is")
		other.global_position = Vector2(cross_x, a.y - 30.0)
		gadgets._physics_process(0.0)
		check(gadgets.trips_sent == trips_before + 1, "it is quiet for a moment after")
	me.global_position = wire_pickup.global_position + Vector2(20, 0)
	pickups.request_pickup(wire_pickup)
	settle()
	check(gadgets.tripwire_count() == 0 and me.inventory.slots.has(TRIPWIRE), "taking it back up disarms it")
	var found_wire : Pickup = pickups.spawn(TRIPWIRE, spot + Vector2(0, 60))
	check(gadgets.tripwire_count() == 0 and found_wire.get_node_or_null("Wire") == null, "a tripwire found lying about is not armed")

	#coms hacker: hears messages near it, on channels its owner is not on
	me.global_position = spot
	me.inventory.put_in_slot(1, HACKER)
	pickups.request_use(1)
	settle()
	var hacker : Pickup = newest_pickup()
	check(hacker != null and hacker.item == HACKER and gadgets.hacker_count() == 1, "putting a coms hacker down sets it listening")
	other.global_position = hacker.global_position + Vector2(100, 0)
	var heard : Array = []
	var on_notice : Callable = func(text : String) -> void: heard.append(text)
	game.chat_relay.notice.connect(on_notice)
	var told : Array[int] = gadgets.intercept(2, ChatRules.Channel.INTRUDERS, "Bob", "the relic is in the vault", [2])
	check(told == ([1] as Array[int]), "a message near it, on a channel its owner is not on, goes to its owner")
	check(heard.size() == 1 and heard[0].contains("Bob") and heard[0].contains("the relic is in the vault"), "with who said it (%s)" % [heard])
	check(gadgets.intercept(2, ChatRules.Channel.GUARDS, "Bob", "hi", [1, 2]).is_empty(), "a message its owner was sent anyway is not doubled")
	other.global_position = hacker.global_position + Vector2(gadgets.listen_radius_m * Acoustics.PX_PER_METRE + 50.0, 0)
	check(gadgets.intercept(2, ChatRules.Channel.INTRUDERS, "Bob", "far away", [2]).is_empty(), "one said out of its reach is not heard")
	game.chat_relay.notice.disconnect(on_notice)
	var found_hacker : Pickup = pickups.spawn(HACKER, spot + Vector2(0, -60))
	check(gadgets.hacker_count() == 1, "a coms hacker found lying about listens for nobody")
	var body : ComsHackerBody = hacker.get_node("Hacker/Body")
	check(body.is_in_group(HitscanManager.SHOOTABLE_GROUP) and body.collision_layer == FacilityTileSet.GADGET_LAYER, "it can be shot")
	check(hitscan.world_collision_mask & FacilityTileSet.GADGET_LAYER != 0, "and shots test for it")
	check(me.collision_mask & FacilityTileSet.GADGET_LAYER == 0, "but it does not stop anyone walking")
	body.take_damage(10.0)
	settle()
	check(not is_instance_valid(hacker) or hacker.is_queued_for_deletion(), "a shot breaks it")
	check(gadgets.hacker_count() == 0, "and it stops listening")
	found_hacker.queue_free()
	found_wire.queue_free()

	#night vision: carried and switched on, the dark counts as lit; a bright light blinds it
	var nv : NightVision = gadgets.night_vision
	nv._process(0.016)
	check(not nv.is_carried() and not sight.night_vision, "without the helmet there is no night vision")
	me.inventory.put_in_slot(2, NIGHT_VISION)
	nv.toggle()
	other.flashlight.on = false
	nv._process(0.016)
	check(nv.is_working() and sight.night_vision, "carried and switched on, it works")
	other.global_position = me.global_position + Vector2(150, 0)
	other.flashlight.on = true
	other.flashlight.global_rotation = (me.global_position - other.flashlight.global_position).angle()
	await get_tree().physics_frame
	check(sight.bright_light_on(me), "another player's beam in the face is a bright light")
	nv._process(0.016)
	check(not nv.is_working() and not sight.night_vision, "which blinds it")
	other.flashlight.on = false
	nv._process(nv.blind_seconds + 0.1)
	nv._process(0.016)
	check(nv.is_working(), "and it comes back once the light is gone")
	nv.toggle()
	nv._process(0.016)
	check(not sight.night_vision, "switched off, it stops")
	me.inventory.put_in_slot(2, null)

	#radar: a pulse shows the players moving round you, not the still or sneaking ones
	var radar : RadarDisplay = gadgets.radar
	me.inventory.put_in_slot(3, RADAR)
	check(radar.is_carried(), "the radar works while carried")
	other.global_position = me.global_position + Vector2(400, 0) #(through walls is fine: it is radar)
	radar._speeds[other] = 250.0
	check(radar.scan(me).size() == 1, "someone walking nearby shows")
	radar._speeds[other] = 100.0
	check(radar.scan(me).is_empty(), "someone sneaking does not")
	radar._speeds[other] = 250.0
	other.global_position = me.global_position + Vector2(radar.range_px + 50.0, 0)
	check(radar.scan(me).is_empty(), "nor someone out of range")
	other.global_position = me.global_position + Vector2(300, 0)
	radar.since_pulse = radar.pulse_seconds
	radar._process(0.0)
	check(radar.since_pulse < 0.1 and radar.blips.size() <= 1, "it pulses every %.0f seconds" % radar.pulse_seconds)
	me.inventory.put_in_slot(3, null)
	radar._process(0.016)
	check(not radar.is_carried() and radar.blips.is_empty(), "without it nothing shows")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
