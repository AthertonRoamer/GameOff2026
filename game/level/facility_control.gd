class_name FacilityControl
extends Node

##The facility's shared, changeable state, owned by the lobby. For now that is the doors; generator power, lights and turrets belong here too.
##
##Nobody changes a door directly. A peer asks with request_door(); the lobby checks the request (the door exists, is not locked, and the asking
##player is standing at a console that works doors, see can_operate) and, if it agrees, stamps the change with a tick a little in the future and
##tells every peer. Every peer, the lobby included, then switches the door on that same tick, so the door shuts at the same point in everyone's
##simulation instead of a round trip later on the clients. A change that arrives after its tick (a slow connection) is applied at once.
##Offline (the playground) the local peer is the lobby, so the same path runs with no network.

signal door_scheduled(door : FacilityDoor, state : FacilityDoor.State) #a change was accepted and will happen on its tick

@export var facility : FacilityMap
@export var apply_delay_ticks : int = 8 #how far ahead an accepted change is scheduled. Should cover the lobby -> client delay

##(peer_id : int, function : String) -> bool. Lobby only: may this peer use the consoles of this utility function (like "doors") right now?
##Unset, every request is allowed.
var can_operate : Callable = Callable()

var _pending : Array[Dictionary] = [] #{tick, index, state}, in the order they were accepted
var _active : bool = true


func _ready() -> void:
	NetworkTime.before_tick.connect(_on_before_tick)


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
		if change["index"] == door.door_index:
			return true
	return false


##Lobby only: sends every door's current state to every peer. Called when the game starts, so a peer that missed something before then agrees.
func broadcast_snapshot() -> void:
	if not _active or not _is_lobby() or multiplayer.get_peers().is_empty():
		return
	var states : PackedByteArray = PackedByteArray()
	for door in facility.doors:
		states.append(door.state)
	_receive_snapshot.rpc(states)


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
	var tick : int = NetworkTime.tick + apply_delay_ticks
	_schedule(tick, index, state)
	if not multiplayer.get_peers().is_empty():
		_schedule_remote.rpc(tick, index, state)


func _schedule(tick : int, index : int, state : int) -> void:
	_pending.append({"tick": tick, "index": index, "state": state})
	door_scheduled.emit(facility.doors[index], state)
	if tick <= NetworkTime.tick: #arrived late: catch up now rather than wait for a tick that has passed
		_apply_due(NetworkTime.tick)


func _on_before_tick(_delta : float, tick : int) -> void:
	_apply_due(tick)


func _apply_due(tick : int) -> void:
	if _pending.is_empty() or not _active:
		return
	var still_pending : Array[Dictionary] = []
	for change in _pending:
		if change["tick"] <= tick:
			facility.doors[change["index"]].state = change["state"]
		else:
			still_pending.append(change)
	_pending = still_pending


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("any_peer", "call_remote", "reliable")
func _request_door(index : int, state : int) -> void:
	if _active and multiplayer.is_server():
		_decide(multiplayer.get_remote_sender_id(), index, state)


@rpc("authority", "call_remote", "reliable")
func _schedule_remote(tick : int, index : int, state : int) -> void:
	if _active and index >= 0 and index < facility.doors.size():
		_schedule(tick, index, state)


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(states : PackedByteArray) -> void:
	if not _active:
		return
	for i in mini(states.size(), facility.doors.size()):
		if not is_pending(facility.doors[i]):
			facility.doors[i].state = states[i] as FacilityDoor.State
