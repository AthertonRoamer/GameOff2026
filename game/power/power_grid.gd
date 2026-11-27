class_name PowerGrid
extends Node

##The facility's power, owned by the lobby. Power is a flow, in points per second:
##  - Supply. Each running generator gives its output either to its region (the region of the room it stands in) or, if it is a whole-map
##    generator, to the shared pool that every region draws on.
##  - Load. Everything that is on takes its cost while it is on (PowerSettings: a closed door, a light, a camera, a turret). Doors, the rooms'
##    ceiling lights and the rooms' cameras exist so far; a light or a camera is paid for by the region of its room.
##  - A region first uses its own generators; what it needs beyond them it takes from the pool. So the power still free for a region is what its own
##    generators have left plus what the pool has left: available(region). Something can be switched on only if its cost fits in that (can_afford).
##  - When supply drops (a generator shot down), the lobby switches things off until what is left fits again: first the category that comes first
##    in PowerSettings.shed_order, and within it the thing that was switched on last, only in the regions that are short.
##  - A room in no region (region "") has no generators of its own: it runs on the pool alone.
##
##Every peer works out the same numbers itself, from the doors (FacilityControl already keeps them the same everywhere) and the generators' states,
##which only the lobby changes and which it sends to every peer when they change. Starting or repairing a generator: the player holds E on it
##(PlayerInteractor), and when the hold is done asks the lobby, which checks the player is a guard at the generator, alive, and has been holding for
##long enough, then starts it. Switching a door off when power runs short goes through FacilityControl.force_open, so the door opens on the same tick everywhere.
##Offline (the playground, tests) the local peer is the lobby, so the same path runs with no network.

signal changed #the supply or the load changed somewhere: numbers shown on screen should be read again

const DEFAULT_SETTINGS : PowerSettings = preload("res://game/power/power_settings.tres")
const HOLD_SLACK_SECONDS : float = 0.6 #the lobby lets a hold be this much shorter than it should, for the time the messages take
const REACH_SLACK : float = 1.5 #the lobby's view of a player can be a few ticks behind, so its reach check is a little looser

@export var facility : FacilityMap
@export var control : FacilityControl
@export var settings : PowerSettings = DEFAULT_SETTINGS

##(peer_id : int) -> Player or null. Set by the level; unset, the lobby does not check who works a generator (tests).
var player_of : Callable = Callable()

var generators : Array[Generator] = []

var _loads : Dictionary = {} #key (String) -> {category, region, order}. A door's key is "door:<index>"
var _order : int = 0 #counts switch-ons, so the last one switched on goes first
var _local : Dictionary = {} #region -> its running region generators' output
var _pool : float = 0.0 #the running whole-map generators' output
var _load : Dictionary = {} #region -> what its loads take
var _holds : Dictionary = {} #lobby: peer id -> {index, since (msec)}: who is holding E on which generator
var _active : bool = true
var _built : bool = false
var _watching : bool = false #the doors' state_changed are connected (once, however often build() runs)
var _lights_watched : FacilityControl = null #the control whose light_changed is connected


##Finds the generators (under the map's Props, in scene order: the same on every peer), starts the ones set to start running, and counts the doors
##that are shut. Call once the map is built.
func build() -> void:
	generators.clear()
	if facility == null:
		return
	for node : Node in _descendants(facility.props_node):
		if node is Generator:
			var generator : Generator = node
			generator.grid = self
			generator.index = generators.size()
			generator.region = facility.region_at(facility.to_local(generator.global_position))
			generator.health = generator.max_health()
			generator.state = Generator.State.RUNNING if generator.starts_running else Generator.State.OFF
			generators.append(generator)
	_loads.clear()
	for door : FacilityDoor in facility.doors:
		if not _watching:
			door.state_changed.connect(_on_door_changed.bind(door))
		_on_door_changed(door.state, door, false)
	_watching = true
	if control != null:
		if control.lights_on.size() != facility.light_rooms.size():
			control.build_lights()
		if _lights_watched != control:
			control.light_changed.connect(_on_light_changed)
			control.camera_changed.connect(_on_camera_changed)
			_lights_watched = control
		for index in control.light_count():
			if control.is_light_on(index):
				_on_light_changed(index, true, false)
		for index in control.camera_count():
			if control.is_camera_on(index):
				_on_camera_changed(index, true, false)
	_built = true
	_recount()


# ------------------------------------------------------------------ the numbers
##Region generators' output in this region now.
func local_supply(region : String) -> float:
	return _local.get(region, 0.0)


##Whole-map generators' output now.
func pool_supply() -> float:
	return _pool


func load_of(region : String) -> float:
	return _load.get(region, 0.0)


##What a region takes from the pool: what it uses beyond its own generators.
func pool_draw(region : String) -> float:
	return maxf(0.0, load_of(region) - local_supply(region))


##What is left in the pool after every region has taken what it needs from it (below zero while power is short).
func pool_free() -> float:
	var drawn : float = 0.0
	for region : String in _load:
		drawn += pool_draw(region)
	return _pool - drawn


##The power still free for something new in this region: what its own generators have left, plus what the pool has left.
func available(region : String) -> float:
	return maxf(0.0, local_supply(region) - load_of(region)) + maxf(0.0, pool_free())


##The most this region could have: its own generators and the whole pool.
func capacity(region : String) -> float:
	return local_supply(region) + _pool


func can_afford(region : String, cost : float) -> bool:
	return cost <= available(region) + 0.0001


func cost_of(category : PowerSettings.Category) -> float:
	return settings.cost_of(category)


func door_cost() -> float:
	return settings.door_cost


func light_cost() -> float:
	return settings.light_cost


func camera_cost() -> float:
	return settings.camera_cost


# ------------------------------------------------------------------ loads
##Something switched on. Safe to call again for something already on.
func add_load(key : String, category : PowerSettings.Category, region : String) -> void:
	if _loads.has(key):
		return
	_order += 1
	_loads[key] = {"category": category, "region": region, "order": _order}
	_recount()


func remove_load(key : String) -> void:
	if _loads.erase(key):
		_recount()


func has_load(key : String) -> bool:
	return _loads.has(key)


static func door_key(door : FacilityDoor) -> String:
	return "door:%d" % door.door_index


##Lobby: a door has been allowed to close and will on its tick. Its power is counted now, so two quick requests cannot both take the last of it.
func reserve_door(door : FacilityDoor) -> void:
	add_load(door_key(door), PowerSettings.Category.DOORS, facility.region_of_door(door))


static func light_key(index : int) -> String:
	return "light:%d" % index


##Lobby: a light has been allowed to come on and will on its tick. Its power is counted now (see reserve_door).
func reserve_light(index : int, region : String) -> void:
	add_load(light_key(index), PowerSettings.Category.LIGHTS, region)


static func camera_key(index : int) -> String:
	return "camera:%d" % index


##Lobby: a camera has been allowed to come on and will on its tick. Its power is counted now (see reserve_door).
func reserve_camera(index : int, region : String) -> void:
	add_load(camera_key(index), PowerSettings.Category.CAMERAS, region)


func _on_light_changed(index : int, on : bool, recount : bool = true) -> void:
	_on_room_switch_changed(light_key(index), PowerSettings.Category.LIGHTS, index, on, recount)


func _on_camera_changed(index : int, on : bool, recount : bool = true) -> void:
	_on_room_switch_changed(camera_key(index), PowerSettings.Category.CAMERAS, index, on, recount)


func _on_room_switch_changed(key : String, category : PowerSettings.Category, index : int, on : bool, recount : bool) -> void:
	if on:
		if not _loads.has(key):
			_order += 1
			_loads[key] = {"category": category, "region": control.light_region(index), "order": _order}
	else:
		_loads.erase(key)
	if recount:
		_recount()


func _on_door_changed(state : FacilityDoor.State, door : FacilityDoor, recount : bool = true) -> void:
	var key : String = door_key(door)
	if state == FacilityDoor.State.CLOSED: #a locked door is kept shut by its lock, not by power
		if not _loads.has(key):
			_order += 1
			_loads[key] = {"category": PowerSettings.Category.DOORS, "region": facility.region_of_door(door), "order": _order}
	else:
		_loads.erase(key)
	if recount:
		_recount()


# ------------------------------------------------------------------ generators: asked by any peer, decided by the lobby
##Holding E on a generator began (started = true) or stopped before it was done.
func request_hold(generator : Generator, started : bool) -> void:
	if not _active:
		return
	if _is_lobby():
		_decide_hold(multiplayer.get_unique_id(), generator.index, started)
	else:
		_hold_request.rpc_id(1, generator.index, started)


##The hold on a generator is done: start it (or repair it).
func request_finish(generator : Generator) -> void:
	if not _active:
		return
	if _is_lobby():
		_decide_finish(multiplayer.get_unique_id(), generator.index)
	else:
		_finish_request.rpc_id(1, generator.index)


##Lobby: a shot ended on a generator.
func damage_generator(generator : Generator, damage : float) -> void:
	if not _active or not _is_lobby() or generator.state == Generator.State.DESTROYED or damage <= 0.0:
		return
	var health : float = maxf(0.0, generator.health - damage)
	_set_generator(generator.index, Generator.State.DESTROYED if health <= 0.0 else generator.state, health)


##Lobby, and tests: sets a generator's state and health here and on every peer.
func set_generator(generator : Generator, state : Generator.State, health : float = -1.0) -> void:
	if _is_lobby():
		_set_generator(generator.index, state, generator.max_health() if health < 0.0 else health)


func _decide_hold(peer_id : int, index : int, started : bool) -> void:
	if index < 0 or index >= generators.size():
		return
	if started and _may_work(peer_id, generators[index]):
		_holds[peer_id] = {"index": index, "since": Time.get_ticks_msec(), "stop": generators[index].state == Generator.State.RUNNING}
	elif not started and _holds.has(peer_id) and _holds[peer_id]["index"] == index:
		_holds.erase(peer_id)


func _decide_finish(peer_id : int, index : int) -> void:
	if index < 0 or index >= generators.size() or not _holds.has(peer_id) or _holds[peer_id]["index"] != index:
		return
	var generator : Generator = generators[index]
	var held : float = (Time.get_ticks_msec() - int(_holds[peer_id]["since"])) / 1000.0
	var stopping : bool = _holds[peer_id].get("stop", false)
	_holds.erase(peer_id)
	if stopping != (generator.state == Generator.State.RUNNING): #(someone else started or stopped it while this hold ran)
		return
	if held < generator.hold_seconds(null) - HOLD_SLACK_SECONDS or not _may_work(peer_id, generator):
		return
	if stopping:
		_set_generator(index, Generator.State.OFF, generator.health) #(its damage stays)
	else:
		_set_generator(index, Generator.State.RUNNING, generator.max_health())


##Lobby: is this peer's player a living player who may work the generator (see Generator.can_interact) at it (as the lobby sees them)? Unchecked while there is no way to find the player.
func _may_work(peer_id : int, generator : Generator) -> bool:
	if not player_of.is_valid():
		return true
	var player : Player = player_of.call(peer_id)
	if player == null or not is_instance_valid(player) or not player.is_alive() or not generator.can_interact(player):
		return false
	return generator.global_position.distance_to(player.global_position) <= (generator.reach_m * 44.0 + Generator.SIZE.x / 2.0) * REACH_SLACK


func _set_generator(index : int, state : int, health : float) -> void:
	_apply_generator(index, state, health)
	if not multiplayer.get_peers().is_empty():
		_generator_changed.rpc(index, state, health)


func _apply_generator(index : int, state : int, health : float) -> void:
	if index < 0 or index >= generators.size():
		return
	var generator : Generator = generators[index]
	generator.health = health
	generator.state = state as Generator.State
	_recount() #(cheap; also picks up an output changed by hand, in a test or the debug console)


##Lobby only: sends every generator's state to every peer. Called when the game starts, next to FacilityControl.broadcast_snapshot().
func broadcast_snapshot() -> void:
	if not _active or not _is_lobby() or multiplayer.get_peers().is_empty():
		return
	var states : PackedByteArray = PackedByteArray()
	var healths : PackedFloat32Array = PackedFloat32Array()
	for generator in generators:
		states.append(generator.state)
		healths.append(generator.health)
	_receive_snapshot.rpc(states, healths)


##Stops sending and applying changes. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false
	_holds.clear()


# ------------------------------------------------------------------ counting, and switching off when short
func _recount() -> void:
	if not _built:
		return
	_local.clear()
	_pool = 0.0
	for generator in generators:
		if generator.scope == Generator.Scope.WHOLE_MAP:
			_pool += generator.supply()
		elif generator.region != "":
			_local[generator.region] = _local.get(generator.region, 0.0) + generator.supply()
	_load.clear()
	for key : String in _loads:
		var entry : Dictionary = _loads[key]
		_load[entry["region"]] = _load.get(entry["region"], 0.0) + settings.cost_of(entry["category"])
	if _active and _is_lobby():
		_shed()
	changed.emit()


##Lobby: while the regions need more from the pool than it has, switches off the load that goes first (shed_order, then the last switched on) among
##the regions drawing on the pool. A region that its own generators cover is never touched.
func _shed() -> void:
	var guard : int = _loads.size()
	while pool_free() < -0.0001 and guard > 0:
		guard -= 1
		var victim : String = ""
		var best_rank : int = 0
		var best_order : int = 0
		for key : String in _loads:
			var entry : Dictionary = _loads[key]
			if pool_draw(entry["region"]) <= 0.0:
				continue
			var rank : int = settings.shed_rank(entry["category"])
			if victim == "" or rank < best_rank or (rank == best_rank and int(entry["order"]) > best_order):
				victim = key
				best_rank = rank
				best_order = entry["order"]
		if victim == "":
			return
		_switch_off(victim)


func _switch_off(key : String) -> void:
	var entry : Dictionary = _loads[key]
	_loads.erase(key)
	_load[entry["region"]] = _load.get(entry["region"], 0.0) - settings.cost_of(entry["category"])
	if entry["category"] == PowerSettings.Category.DOORS:
		var index : int = int(key.get_slice(":", 1))
		if control != null and index >= 0 and index < facility.doors.size():
			control.force_open(facility.doors[index])
		elif index >= 0 and index < facility.doors.size():
			facility.doors[index].state = FacilityDoor.State.OPEN #(no control: a bare test)
	elif entry["category"] == PowerSettings.Category.LIGHTS and control != null:
		control.force_light_off(int(key.get_slice(":", 1))) #(only the lobby sheds, so this is the lobby)
	elif entry["category"] == PowerSettings.Category.CAMERAS and control != null:
		control.force_camera_off(int(key.get_slice(":", 1)))


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _descendants(node : Node) -> Array[Node]:
	var result : Array[Node] = []
	if node == null:
		return result
	for child : Node in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


@rpc("any_peer", "call_remote", "reliable")
func _hold_request(index : int, started : bool) -> void:
	if _active and multiplayer.is_server():
		_decide_hold(multiplayer.get_remote_sender_id(), index, started)


@rpc("any_peer", "call_remote", "reliable")
func _finish_request(index : int) -> void:
	if _active and multiplayer.is_server():
		_decide_finish(multiplayer.get_remote_sender_id(), index)


@rpc("authority", "call_remote", "reliable")
func _generator_changed(index : int, state : int, health : float) -> void:
	if _active:
		_apply_generator(index, state, health)


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(states : PackedByteArray, healths : PackedFloat32Array) -> void:
	if not _active:
		return
	for i in mini(states.size(), generators.size()):
		generators[i].health = healths[i] if i < healths.size() else generators[i].max_health()
		generators[i].state = states[i] as Generator.State
	_recount()
