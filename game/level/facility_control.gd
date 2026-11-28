class_name FacilityControl
extends Node

##The facility's shared, changeable state, owned by the lobby: the doors, the rooms' ceiling lights, the rooms' cameras and the turrets' power switches.
##A turret is switched like a light, from the door console (TurretsLayer) or by a technician standing by it (TurretSwitch), and costs PowerSettings.turret_cost
##while it is on. Turrets are named by their index in TurretSystem.turrets (build_turrets sizes them); what a turret does while it is on is TurretSystem's.
##A light or a camera is switched exactly like a door, from the same console ("doors"), and costs power while it is on (PowerSettings.light_cost, camera_cost).
##Lights and cameras are named by their index in FacilityMap.light_rooms (a room's camera has its light's index) and are all off when the game starts.
##A camera that is on shows its room live on the door console's map (CamerasLayer).
##
##Nobody changes a door directly. A peer asks with request_door(); the lobby checks the request (the door exists, is not locked, and the asking
##player is standing at a console that works doors, see can_operate, or a technician is standing right by the door, see request_door_by_hand) and, if it agrees, stamps the change with a tick a little in the future and
##tells every peer. Every peer, the lobby included, then switches the door on that same tick, so the door shuts at the same point in everyone's
##simulation instead of a round trip later on the clients. A change that arrives after its tick (a slow connection) is applied at once.
##Offline (the playground) the local peer is the lobby, so the same path runs with no network.

signal door_scheduled(door : FacilityDoor, state : FacilityDoor.State) #a change was accepted and will happen on its tick
signal door_refused(door : FacilityDoor, reason : String) #on the peer that asked: the lobby said no ("power": not enough power in the door's region)
signal light_changed(index : int, on : bool) #a room's light went on or off, on this peer
signal light_refused(index : int, reason : String) #on the peer that asked: the lobby said no ("power")
signal camera_changed(index : int, on : bool) #a room's camera went on or off, on this peer
signal camera_refused(index : int, reason : String) #on the peer that asked: the lobby said no ("power")
signal turret_changed(index : int, on : bool) #a turret was switched on or off, on this peer
signal turret_refused(index : int, reason : String) #on the peer that asked: the lobby said no ("power", or "destroyed": it has to be repaired first)
signal operated(peer_id : int, powered : bool) #lobby only: a change asked for from a console was accepted. powered: it now takes power (a door shut, something switched on)

const LIGHTS_FUNCTION : String = "doors" #lights and cameras are worked from the door console
const KIND_DOOR : int = 0 #what a scheduled change is about, as sent to the clients
const KIND_LIGHT : int = 1
const KIND_CAMERA : int = 2
const KIND_TURRET : int = 3
const KIND_NAMES : Array[String] = ["door", "light", "camera", "turret"]

@export var facility : FacilityMap
@export var power : PowerGrid ## a door is held shut by power: closing one needs enough power free in its region (PowerGrid.can_afford). Unset: doors are free
@export var apply_delay_ticks : int = 8 #how far ahead an accepted change is scheduled. Should cover the lobby -> client delay

##(peer_id : int, function : String) -> bool. Lobby only: may this peer use the consoles of this utility function (like "doors") right now?
##Unset, every request is allowed.
var can_operate : Callable = Callable()
##(peer_id : int, door : FacilityDoor) -> bool. Lobby only: may this peer work this door by hand right now (a technician next to it, see DoorSwitch)? Unset: never.
var can_work_by_hand : Callable = Callable()
##(peer_id : int, index : int) -> bool. Lobby only: may this peer switch this turret by hand right now (a technician next to it, see TurretSwitch)? Unset: never.
var can_work_turret_by_hand : Callable = Callable()
##(index : int) -> bool. Lobby only: can this turret be switched on at all (not destroyed, see TurretSystem)? Unset: always.
var can_turret_switch_on : Callable = Callable()

var lights_on : PackedByteArray = PackedByteArray() #light index -> 1 on, 0 off (see FacilityMap.light_rooms)
var cameras_on : PackedByteArray = PackedByteArray() #camera index -> 1 on, 0 off. A room's camera has the same index as its light
var turrets_on : PackedByteArray = PackedByteArray() #turret index -> 1 on, 0 off (see TurretSystem.turrets)
var turret_regions : PackedStringArray = PackedStringArray() #turret index -> the region that pays for it

var _pending : Array[Dictionary] = [] #{tick, kind ("door", "light" or "camera"), index, state}, in the order they were accepted
var _active : bool = true


func _ready() -> void:
	NetworkTime.before_tick.connect(_on_before_tick)
	build_lights()


##Sizes the lights and cameras to the map's (all off). Called by _ready, and again if the map is built after it.
func build_lights() -> void:
	lights_on = PackedByteArray()
	cameras_on = PackedByteArray()
	if facility != null:
		lights_on.resize(facility.light_rooms.size())
		lights_on.fill(0)
		cameras_on.resize(facility.light_rooms.size())
		cameras_on.fill(0)


# ------------------------------------------------------------------ lights
func is_light_on(index : int) -> bool:
	return _is_switch_on("light", index)


func light_count() -> int:
	return lights_on.size()


##Ask for a room's light to be switched on or off. Safe to call on any peer; only the lobby decides.
func request_light(index : int, on : bool) -> void:
	_request_switch("light", index, on)


##True while a change to this light has been accepted but its tick has not come yet.
func is_light_pending(index : int) -> bool:
	return _is_switch_pending("light", index)


##The region that pays for a light (or a camera): its room's.
func light_region(index : int) -> String:
	return facility.region_of_room(facility.light_rooms[index]) if index >= 0 and index < facility.light_rooms.size() else ""


##Lobby: switches a light off whatever the console rules say, because its region has run out of power (PowerGrid switching things off).
func force_light_off(index : int) -> void:
	_force_switch_off("light", index)


##Sets a light here at once, with no lobby and no tick (tests, and PowerGrid with no control).
func set_light_now(index : int, on : bool) -> void:
	_set_switch_now("light", index, on)


# ------------------------------------------------------------------ turrets: switched like a light, worked by TurretSystem while on
##Sizes the turrets (all off): one per entry, each paid for by that region. Called by TurretSystem.build, before PowerGrid.build.
func build_turrets(regions : PackedStringArray) -> void:
	turret_regions = regions.duplicate()
	turrets_on = PackedByteArray()
	turrets_on.resize(regions.size())
	turrets_on.fill(0)


func is_turret_on(index : int) -> bool:
	return _is_switch_on("turret", index)


func turret_count() -> int:
	return turrets_on.size()


##Ask for a turret to be switched on or off from the door console. Safe to call on any peer; only the lobby decides.
func request_turret(index : int, on : bool) -> void:
	_request_switch("turret", index, on)


##Ask for a turret to be switched on or off by hand, by a technician standing next to it (see TurretSwitch). The lobby checks can_work_turret_by_hand instead of
##the console rule; the power rule is the same.
func request_turret_by_hand(index : int, on : bool) -> void:
	_request_switch("turret", index, on, true)


func is_turret_pending(index : int) -> bool:
	return _is_switch_pending("turret", index)


##The region that pays for a turret: the region of the room it stands in.
func turret_region(index : int) -> String:
	return turret_regions[index] if index >= 0 and index < turret_regions.size() else ""


##Lobby: switches a turret off whatever the console rules say (its region ran out of power, or it was shot down).
func force_turret_off(index : int) -> void:
	_force_switch_off("turret", index)


##Sets a turret here at once, with no lobby and no tick (tests).
func set_turret_now(index : int, on : bool) -> void:
	_set_switch_now("turret", index, on)


# ------------------------------------------------------------------ cameras: one per lit room, switched like its light, watched on the door console
func is_camera_on(index : int) -> bool:
	return _is_switch_on("camera", index)


func camera_count() -> int:
	return cameras_on.size()


##Ask for a room's camera to be switched on or off. Safe to call on any peer; only the lobby decides.
func request_camera(index : int, on : bool) -> void:
	_request_switch("camera", index, on)


##True while a change to this camera has been accepted but its tick has not come yet.
func is_camera_pending(index : int) -> bool:
	return _is_switch_pending("camera", index)


##Lobby: switches a camera off whatever the console rules say, because its region has run out of power.
func force_camera_off(index : int) -> void:
	_force_switch_off("camera", index)


##Sets a camera here at once, with no lobby and no tick (tests).
func set_camera_now(index : int, on : bool) -> void:
	_set_switch_now("camera", index, on)


func _exit_tree() -> void:
	if NetworkTime.before_tick.is_connected(_on_before_tick):
		NetworkTime.before_tick.disconnect(_on_before_tick)


##Ask for a door to be opened or closed. Safe to call on any peer; only the lobby decides.
func request_door(door : FacilityDoor, state : FacilityDoor.State) -> void:
	if not _active or door == null:
		return
	if _is_lobby():
		_decide(multiplayer.get_unique_id(), door.door_index, state)
	else:
		_request_door.rpc_id(1, door.door_index, state)


##Ask for a door to be opened or closed by hand, by a player standing next to it (a technician, see DoorSwitch). The lobby checks can_work_by_hand instead of
##the console rule; the power rule is the same.
func request_door_by_hand(door : FacilityDoor, state : FacilityDoor.State) -> void:
	if not _active or door == null:
		return
	if _is_lobby():
		_decide(multiplayer.get_unique_id(), door.door_index, state, true)
	else:
		_request_door_by_hand.rpc_id(1, door.door_index, state)


##True while a change to this door has been accepted but its tick has not come yet (the door screen shows it as switching).
func is_pending(door : FacilityDoor) -> bool:
	for change in _pending:
		if change["kind"] == "door" and change["index"] == door.door_index:
			return true
	return false


##Lobby only: sends every door's, light's and camera's current state to every peer. Called when the game starts, so a peer that missed something before then agrees.
func broadcast_snapshot() -> void:
	if not _active or not _is_lobby() or multiplayer.get_peers().is_empty():
		return
	var states : PackedByteArray = PackedByteArray()
	for door in facility.doors:
		states.append(door.state)
	_receive_snapshot.rpc(states, lights_on, cameras_on, turrets_on)


##Stops sending and applying changes. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false
	_pending.clear()


func _decide(peer_id : int, index : int, state : int, by_hand : bool = false) -> void:
	if index < 0 or index >= facility.doors.size():
		return
	if state != FacilityDoor.State.OPEN and state != FacilityDoor.State.CLOSED: #locking is not something a console does
		return
	var door : FacilityDoor = facility.doors[index]
	if door.state == FacilityDoor.State.LOCKED or (door.state == state and not is_pending(door)):
		return
	if by_hand:
		if not can_work_by_hand.is_valid() or not can_work_by_hand.call(peer_id, door):
			return
	elif can_operate.is_valid() and not can_operate.call(peer_id, "doors"):
		return
	if state == FacilityDoor.State.CLOSED and power != null and not power.has_load(PowerGrid.door_key(door)):
		if not power.can_afford(facility.region_of_door(door), power.door_cost()):
			_refuse(peer_id, index, "power")
			return
		power.reserve_door(door) #counted now, so a second request cannot take the same power before this door shuts
	elif state == FacilityDoor.State.OPEN and power != null:
		power.remove_load(PowerGrid.door_key(door)) #(free again at once, also if it was only reserved)
	_accept("door", index, state)
	if not by_hand:
		operated.emit(peer_id, state == FacilityDoor.State.CLOSED)


##Lobby: opens a door whatever the console rules say, because its region has run out of power (PowerGrid switching things off).
func force_open(door : FacilityDoor) -> void:
	if not _active or not _is_lobby() or door == null or door.state == FacilityDoor.State.LOCKED:
		return
	if door.state == FacilityDoor.State.OPEN and not is_pending(door):
		return
	_accept("door", door.door_index, FacilityDoor.State.OPEN)


# ------------------------------------------------------------------ switches (a light, a camera or a turret), by kind
func _switch_count(kind : String) -> int:
	match kind:
		"light": return lights_on.size()
		"camera": return cameras_on.size()
		"turret": return turrets_on.size()
	return 0


func _is_switch_on(kind : String, index : int) -> bool:
	if index < 0 or index >= _switch_count(kind):
		return false
	match kind:
		"light": return lights_on[index] != 0
		"camera": return cameras_on[index] != 0
	return turrets_on[index] != 0


static func _is_switch_kind(kind : int) -> bool:
	return kind == KIND_LIGHT or kind == KIND_CAMERA or kind == KIND_TURRET


##The region that pays for a switch: a light's or a camera's room's, a turret's own.
func _switch_region(kind : String, index : int) -> String:
	return turret_region(index) if kind == "turret" else light_region(index)


func _switch_key(kind : String, index : int) -> String:
	match kind:
		"light": return PowerGrid.light_key(index)
		"camera": return PowerGrid.camera_key(index)
	return PowerGrid.turret_key(index)


func _switch_cost(kind : String) -> float:
	match kind:
		"light": return power.light_cost()
		"camera": return power.camera_cost()
	return power.turret_cost()


func _request_switch(kind : String, index : int, on : bool, by_hand : bool = false) -> void:
	if not _active or index < 0 or index >= _switch_count(kind):
		return
	if _is_lobby():
		_decide_switch(multiplayer.get_unique_id(), kind, index, on, by_hand)
	elif by_hand:
		_request_turret_by_hand.rpc_id(1, index, on)
	else:
		_request_room_switch.rpc_id(1, KIND_NAMES.find(kind), index, on)


func _is_switch_pending(kind : String, index : int) -> bool:
	for change in _pending:
		if change["kind"] == kind and change["index"] == index:
			return true
	return false


func _force_switch_off(kind : String, index : int) -> void:
	if not _active or not _is_lobby() or index < 0 or index >= _switch_count(kind):
		return
	if not _is_switch_on(kind, index) and not _is_switch_pending(kind, index):
		return
	_accept(kind, index, 0)


func _set_switch_now(kind : String, index : int, on : bool) -> void:
	if index < 0 or index >= _switch_count(kind) or _is_switch_on(kind, index) == on:
		return
	match kind:
		"light":
			lights_on[index] = 1 if on else 0
			light_changed.emit(index, on)
		"camera":
			cameras_on[index] = 1 if on else 0
			camera_changed.emit(index, on)
		"turret":
			turrets_on[index] = 1 if on else 0
			turret_changed.emit(index, on)


func _decide_switch(peer_id : int, kind : String, index : int, on : bool, by_hand : bool = false) -> void:
	if index < 0 or index >= _switch_count(kind):
		return
	if _is_switch_on(kind, index) == on and not _is_switch_pending(kind, index):
		return
	if by_hand: #(only a turret is switched by hand this way: a door has its own path)
		if kind != "turret" or not can_work_turret_by_hand.is_valid() or not can_work_turret_by_hand.call(peer_id, index):
			return
	elif can_operate.is_valid() and not can_operate.call(peer_id, LIGHTS_FUNCTION):
		return
	if on and kind == "turret" and can_turret_switch_on.is_valid() and not can_turret_switch_on.call(index):
		_refuse_switch(peer_id, kind, index, "destroyed")
		return
	var key : String = _switch_key(kind, index)
	if on and power != null and not power.has_load(key):
		if not power.can_afford(_switch_region(kind, index), _switch_cost(kind)):
			_refuse_switch(peer_id, kind, index, "power")
			return
		match kind: #counted now, so a second request cannot take the same power before it comes on
			"light": power.reserve_light(index, light_region(index))
			"camera": power.reserve_camera(index, light_region(index))
			"turret": power.reserve_turret(index, turret_region(index))
	elif not on and power != null:
		power.remove_load(key)
	_accept(kind, index, 1 if on else 0)
	if not by_hand:
		operated.emit(peer_id, on)


func _refuse_switch(peer_id : int, kind : String, index : int, reason : String) -> void:
	if peer_id == multiplayer.get_unique_id():
		_emit_refused(kind, index, reason)
	elif not multiplayer.get_peers().is_empty():
		_room_switch_refused.rpc_id(peer_id, KIND_NAMES.find(kind), index, reason)


func _emit_refused(kind : String, index : int, reason : String) -> void:
	match kind:
		"light": light_refused.emit(index, reason)
		"camera": camera_refused.emit(index, reason)
		"turret": turret_refused.emit(index, reason)


# ------------------------------------------------------------------ scheduling
func _accept(kind : String, index : int, state : int) -> void:
	var tick : int = NetworkTime.tick + apply_delay_ticks
	_schedule(tick, kind, index, state)
	if not multiplayer.get_peers().is_empty():
		_schedule_remote.rpc(tick, KIND_NAMES.find(kind), index, state)


func _schedule(tick : int, kind : String, index : int, state : int) -> void:
	_pending.append({"tick": tick, "kind": kind, "index": index, "state": state})
	if kind == "door":
		door_scheduled.emit(facility.doors[index], state)
	if tick <= NetworkTime.tick: #arrived late: catch up now rather than wait for a tick that has passed
		_apply_due(NetworkTime.tick)


func _on_before_tick(_delta : float, tick : int) -> void:
	_apply_due(tick)


func _apply_due(tick : int) -> void:
	if _pending.is_empty() or not _active:
		return
	var due : Array[Dictionary] = []
	var still_pending : Array[Dictionary] = []
	for change in _pending:
		(still_pending if change["tick"] > tick else due).append(change)
	_pending = still_pending #(first: applying a change can make the power grid switch something else off, which schedules another change)
	for change in due:
		if change["kind"] == "door":
			facility.doors[change["index"]].state = change["state"]
		else:
			_set_switch_now(change["kind"], change["index"], change["state"] != 0)


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _refuse(peer_id : int, index : int, reason : String) -> void:
	if peer_id == multiplayer.get_unique_id():
		door_refused.emit(facility.doors[index], reason)
	elif not multiplayer.get_peers().is_empty():
		_door_refused.rpc_id(peer_id, index, reason)


@rpc("authority", "call_remote", "reliable")
func _door_refused(index : int, reason : String) -> void:
	if _active and index >= 0 and index < facility.doors.size():
		door_refused.emit(facility.doors[index], reason)


@rpc("any_peer", "call_remote", "reliable")
func _request_door(index : int, state : int) -> void:
	if _active and multiplayer.is_server():
		_decide(multiplayer.get_remote_sender_id(), index, state)


@rpc("any_peer", "call_remote", "reliable")
func _request_door_by_hand(index : int, state : int) -> void:
	if _active and multiplayer.is_server():
		_decide(multiplayer.get_remote_sender_id(), index, state, true)


@rpc("authority", "call_remote", "reliable")
func _room_switch_refused(kind : int, index : int, reason : String) -> void:
	if _active and _is_switch_kind(kind) and index >= 0 and index < _switch_count(KIND_NAMES[kind]):
		_emit_refused(KIND_NAMES[kind], index, reason)


@rpc("any_peer", "call_remote", "reliable")
func _request_room_switch(kind : int, index : int, on : bool) -> void:
	if _active and multiplayer.is_server() and _is_switch_kind(kind):
		_decide_switch(multiplayer.get_remote_sender_id(), KIND_NAMES[kind], index, on)


@rpc("any_peer", "call_remote", "reliable")
func _request_turret_by_hand(index : int, on : bool) -> void:
	if _active and multiplayer.is_server():
		_decide_switch(multiplayer.get_remote_sender_id(), "turret", index, on, true)


@rpc("authority", "call_remote", "reliable")
func _schedule_remote(tick : int, kind : int, index : int, state : int) -> void:
	if not _active:
		return
	if kind == KIND_DOOR and index >= 0 and index < facility.doors.size():
		_schedule(tick, "door", index, state)
	elif _is_switch_kind(kind) and index >= 0 and index < _switch_count(KIND_NAMES[kind]):
		_schedule(tick, KIND_NAMES[kind], index, state)


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(states : PackedByteArray, lights : PackedByteArray, cameras : PackedByteArray = PackedByteArray(), turrets : PackedByteArray = PackedByteArray()) -> void:
	if not _active:
		return
	for i in mini(states.size(), facility.doors.size()):
		if not is_pending(facility.doors[i]):
			facility.doors[i].state = states[i] as FacilityDoor.State
	for i in mini(lights.size(), lights_on.size()):
		if not is_light_pending(i):
			set_light_now(i, lights[i] != 0)
	for i in mini(cameras.size(), cameras_on.size()):
		if not is_camera_pending(i):
			set_camera_now(i, cameras[i] != 0)
	for i in mini(turrets.size(), turrets_on.size()):
		if not is_turret_pending(i):
			set_turret_now(i, turrets[i] != 0)
