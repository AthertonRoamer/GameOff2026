class_name FacilityControl
extends Node

##The facility's shared, changeable state, owned by the lobby: the doors, the rooms' ceiling lights and the rooms' cameras (turrets belong here too, later).
##A light or a camera is switched exactly like a door, from the same console ("doors"), and costs power while it is on (PowerSettings.light_cost, camera_cost).
##Lights and cameras are named by their index in FacilityMap.light_rooms (a room's camera has its light's index) and are all off when the game starts.
##A camera that is on shows its room live on the door console's map (CamerasLayer).
##
##Nobody changes a door directly. A peer asks with request_door(); the lobby checks the request (the door exists, is not locked, and the asking
##player is standing at a console that works doors, see can_operate) and, if it agrees, stamps the change with a tick a little in the future and
##tells every peer. Every peer, the lobby included, then switches the door on that same tick, so the door shuts at the same point in everyone's
##simulation instead of a round trip later on the clients. A change that arrives after its tick (a slow connection) is applied at once.
##Offline (the playground) the local peer is the lobby, so the same path runs with no network.

signal door_scheduled(door : FacilityDoor, state : FacilityDoor.State) #a change was accepted and will happen on its tick
signal door_refused(door : FacilityDoor, reason : String) #on the peer that asked: the lobby said no ("power": not enough power in the door's region)
signal light_changed(index : int, on : bool) #a room's light went on or off, on this peer
signal light_refused(index : int, reason : String) #on the peer that asked: the lobby said no ("power")
signal camera_changed(index : int, on : bool) #a room's camera went on or off, on this peer
signal camera_refused(index : int, reason : String) #on the peer that asked: the lobby said no ("power")

const LIGHTS_FUNCTION : String = "doors" #lights and cameras are worked from the door console
const KIND_DOOR : int = 0 #what a scheduled change is about, as sent to the clients
const KIND_LIGHT : int = 1
const KIND_CAMERA : int = 2
const KIND_NAMES : Array[String] = ["door", "light", "camera"]

@export var facility : FacilityMap
@export var power : PowerGrid ## a door is held shut by power: closing one needs enough power free in its region (PowerGrid.can_afford). Unset: doors are free
@export var apply_delay_ticks : int = 8 #how far ahead an accepted change is scheduled. Should cover the lobby -> client delay

##(peer_id : int, function : String) -> bool. Lobby only: may this peer use the consoles of this utility function (like "doors") right now?
##Unset, every request is allowed.
var can_operate : Callable = Callable()

var lights_on : PackedByteArray = PackedByteArray() #light index -> 1 on, 0 off (see FacilityMap.light_rooms)
var cameras_on : PackedByteArray = PackedByteArray() #camera index -> 1 on, 0 off. A room's camera has the same index as its light

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
	_receive_snapshot.rpc(states, lights_on, cameras_on)


##Stops sending and applying changes. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false
	_pending.clear()


func _decide(peer_id : int, index : int, state : int) -> void:
	if index < 0 or index >= facility.doors.size():
		return
	if state != FacilityDoor.State.OPEN and state != FacilityDoor.State.CLOSED: #locking is not something a console does
		return
	var door : FacilityDoor = facility.doors[index]
	if door.state == FacilityDoor.State.LOCKED or (door.state == state and not is_pending(door)):
		return
	if can_operate.is_valid() and not can_operate.call(peer_id, "doors"):
		return
	if state == FacilityDoor.State.CLOSED and power != null and not power.has_load(PowerGrid.door_key(door)):
		if not power.can_afford(facility.region_of_door(door), power.door_cost()):
			_refuse(peer_id, index, "power")
			return
		power.reserve_door(door) #counted now, so a second request cannot take the same power before this door shuts
	elif state == FacilityDoor.State.OPEN and power != null:
		power.remove_load(PowerGrid.door_key(door)) #(free again at once, also if it was only reserved)
	_accept("door", index, state)


##Lobby: opens a door whatever the console rules say, because its region has run out of power (PowerGrid switching things off).
func force_open(door : FacilityDoor) -> void:
	if not _active or not _is_lobby() or door == null or door.state == FacilityDoor.State.LOCKED:
		return
	if door.state == FacilityDoor.State.OPEN and not is_pending(door):
		return
	_accept("door", door.door_index, FacilityDoor.State.OPEN)


# ------------------------------------------------------------------ room switches (a light or a camera), by kind
func _switch_count(kind : String) -> int:
	return lights_on.size() if kind == "light" else cameras_on.size()


func _is_switch_on(kind : String, index : int) -> bool:
	if index < 0 or index >= _switch_count(kind):
		return false
	return (lights_on[index] if kind == "light" else cameras_on[index]) != 0


func _request_switch(kind : String, index : int, on : bool) -> void:
	if not _active or index < 0 or index >= _switch_count(kind):
		return
	if _is_lobby():
		_decide_switch(multiplayer.get_unique_id(), kind, index, on)
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
	if kind == "light":
		lights_on[index] = 1 if on else 0
		light_changed.emit(index, on)
	else:
		cameras_on[index] = 1 if on else 0
		camera_changed.emit(index, on)


func _decide_switch(peer_id : int, kind : String, index : int, on : bool) -> void:
	if index < 0 or index >= _switch_count(kind):
		return
	if _is_switch_on(kind, index) == on and not _is_switch_pending(kind, index):
		return
	if can_operate.is_valid() and not can_operate.call(peer_id, LIGHTS_FUNCTION):
		return
	var key : String = PowerGrid.light_key(index) if kind == "light" else PowerGrid.camera_key(index)
	if on and power != null and not power.has_load(key):
		var cost : float = power.light_cost() if kind == "light" else power.camera_cost()
		if not power.can_afford(light_region(index), cost):
			_refuse_switch(peer_id, kind, index, "power")
			return
		if kind == "light": #counted now, so a second request cannot take the same power before it comes on
			power.reserve_light(index, light_region(index))
		else:
			power.reserve_camera(index, light_region(index))
	elif not on and power != null:
		power.remove_load(key)
	_accept(kind, index, 1 if on else 0)


func _refuse_switch(peer_id : int, kind : String, index : int, reason : String) -> void:
	if peer_id == multiplayer.get_unique_id():
		_emit_refused(kind, index, reason)
	elif not multiplayer.get_peers().is_empty():
		_room_switch_refused.rpc_id(peer_id, KIND_NAMES.find(kind), index, reason)


func _emit_refused(kind : String, index : int, reason : String) -> void:
	if kind == "light":
		light_refused.emit(index, reason)
	else:
		camera_refused.emit(index, reason)


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


@rpc("authority", "call_remote", "reliable")
func _room_switch_refused(kind : int, index : int, reason : String) -> void:
	if _active and (kind == KIND_LIGHT or kind == KIND_CAMERA) and index >= 0 and index < _switch_count(KIND_NAMES[kind]):
		_emit_refused(KIND_NAMES[kind], index, reason)


@rpc("any_peer", "call_remote", "reliable")
func _request_room_switch(kind : int, index : int, on : bool) -> void:
	if _active and multiplayer.is_server() and (kind == KIND_LIGHT or kind == KIND_CAMERA):
		_decide_switch(multiplayer.get_remote_sender_id(), KIND_NAMES[kind], index, on)


@rpc("authority", "call_remote", "reliable")
func _schedule_remote(tick : int, kind : int, index : int, state : int) -> void:
	if not _active:
		return
	if kind == KIND_DOOR and index >= 0 and index < facility.doors.size():
		_schedule(tick, "door", index, state)
	elif (kind == KIND_LIGHT or kind == KIND_CAMERA) and index >= 0 and index < _switch_count(KIND_NAMES[kind]):
		_schedule(tick, KIND_NAMES[kind], index, state)


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(states : PackedByteArray, lights : PackedByteArray, cameras : PackedByteArray = PackedByteArray()) -> void:
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
