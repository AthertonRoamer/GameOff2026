class_name PickupControl
extends Node

##Every item lying on the floor, owned by the lobby the same way FacilityControl owns the doors. A peer asks with request_pickup(); the lobby checks
##the player is alive, in reach, allowed and has a free slot and, if so, stamps it with a tick a little in the future and tells every peer. Every peer
##then moves the item into that player's inventory on the same tick. Peers must spawn() the same pickups in the same order: that is how they agree on ids.

@export var pickup_scene : PackedScene
@export var apply_delay_ticks : int = 8 #how far ahead an accepted pickup is scheduled. Should cover the lobby -> client delay
@export var reach_slack : float = 1.5 #the lobby's view of a player can be a few ticks behind, so its reach check is a little looser

var spawn_parent : Node #where pickups are added: y-sorted with the players
var player_lookup : Callable = Callable() #(peer_id : int) -> Player, or null

var _pickups : Dictionary = {} #pickup id -> Pickup, everything still on the floor
var _pending : Array[Dictionary] = [] #{tick, id, peer, slot}, in the order they were accepted
var _next_id : int = 0
var _active : bool = true


func _ready() -> void:
	NetworkTime.before_tick.connect(_on_before_tick)


func _exit_tree() -> void:
	if NetworkTime.before_tick.is_connected(_on_before_tick):
		NetworkTime.before_tick.disconnect(_on_before_tick)


func spawn(item : Item, world_position : Vector2, can_take : Callable = Callable()) -> Pickup:
	var pickup : Pickup = pickup_scene.instantiate()
	pickup.item = item
	pickup.control = self
	pickup.can_take = can_take
	pickup.pickup_id = _next_id
	_next_id += 1
	_pickups[pickup.pickup_id] = pickup
	spawn_parent.add_child(pickup)
	pickup.global_position = world_position
	return pickup


func get_pickups() -> Array:
	return _pickups.values()


##Ask for this pickup for the local player. Safe to call on any peer; only the lobby decides.
func request_pickup(pickup : Pickup) -> void:
	if not _active:
		return
	if _is_lobby():
		_decide(multiplayer.get_unique_id(), pickup.pickup_id)
	else:
		_request_pickup.rpc_id(1, pickup.pickup_id)


##Stops sending and applying pickups. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false
	_pending.clear()


func _decide(peer_id : int, id : int) -> void:
	var pickup : Pickup = _pickups.get(id)
	if pickup == null or _pending.any(func(change : Dictionary) -> bool: return change["id"] == id or change["peer"] == peer_id):
		return
	var player : Player = player_lookup.call(peer_id)
	if player == null or not player.is_alive() or not pickup.is_in_reach(player.global_position, reach_slack) or not pickup.can_interact(player):
		return
	var slot : int = player.inventory.first_free_slot()
	if slot < 0:
		return
	var tick : int = NetworkTime.tick + apply_delay_ticks
	_schedule(tick, id, peer_id, slot)
	if not multiplayer.get_peers().is_empty():
		_schedule_remote.rpc(tick, id, peer_id, slot)


func _schedule(tick : int, id : int, peer_id : int, slot : int) -> void:
	_pending.append({"tick": tick, "id": id, "peer": peer_id, "slot": slot})
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
			_apply(change)
		else:
			still_pending.append(change)
	_pending = still_pending


func _apply(change : Dictionary) -> void:
	var player : Player = player_lookup.call(change["peer"])
	var pickup : Pickup = _pickups.get(change["id"])
	if player == null or pickup == null: #the player left first: the item stays on the floor
		return
	player.inventory.put_in_slot(change["slot"], pickup.item)
	_pickups.erase(change["id"])
	pickup.queue_free()


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(id : int) -> void:
	if _active and multiplayer.is_server():
		_decide(multiplayer.get_remote_sender_id(), id)


@rpc("authority", "call_remote", "reliable")
func _schedule_remote(tick : int, id : int, peer_id : int, slot : int) -> void:
	if _active and _pickups.has(id):
		_schedule(tick, id, peer_id, slot)
