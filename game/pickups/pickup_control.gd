class_name PickupControl
extends Node

##Every item lying on the floor, and every change to what players carry, owned by the lobby the same way FacilityControl owns the doors. A peer asks
##(request_pickup, request_drop, request_use); the lobby checks the player is alive, in reach, allowed and has room and, if so, stamps the change with a tick a
##little in the future and tells every peer. Every peer then makes the change on that same tick, in the order the lobby accepted them:
##  take      a pickup goes into a player's slot
##  drop      the item in a slot goes onto the floor where the player stands (G; also a placed item, like the portable generator)
##  drop_all  everything a player carries falls round them (they died)
##  consume   an item is used up (medicine): its effect is applied by the lobby, the item leaves the slot
##  give      items appear in a player's inventory (a medic's medicine; a respawn's kit, which also starts their ammunition over)
##  throw     an item is thrown (Item.ClickUse.THROW: a smoke bomb): it leaves the slot and Item.thrown() runs where it lands, on every peer
##  destroy   a pickup on the floor is gone (a coms hacker that was shot)
##A drop remembers who put the item down and which way they faced (Pickup.placed_by, placed_facing): a tripwire or a coms hacker works for whoever placed it.
##Pickups placed at the start (relics, ammo) are numbered in the order every peer spawn()s them; a dropped item is numbered by the lobby (from DROP_ID_BASE up)
##and the number is sent with the drop, so the two can never disagree.

const DROP_ID_BASE : int = 1 << 24 #dropped items' ids start here, far above the placed ones
const GROUP : StringName = &"pickup_control"

@export var pickup_scene : PackedScene
@export var apply_delay_ticks : int = 8 #how far ahead an accepted change is scheduled. Should cover the lobby -> client delay
@export var reach_slack : float = 1.5 #the lobby's view of a player can be a few ticks behind, so its reach check is a little looser
@export var drop_spread_px : float = 24.0 ## how far round a fallen player the things they carried land

var spawn_parent : Node #where pickups are added: y-sorted with the players
var player_lookup : Callable = Callable() #(peer_id : int) -> Player, or null
## (point) -> float, how well the local player sees that point, 0 to 1 (PlayerSight.visibility: inside the view, not behind a wall, lit or not). Set by the game:
## items on the floor (ammo, relics) are only drawn where they can be seen, like blood and other players. Unset: everywhere
var sight : Callable = Callable()
## (item : Item) -> Callable, who may take that item once it has been dropped (a relic keeps its rule: defenders can't take it). Unset, or an invalid Callable back: anyone
var rule_for : Callable = Callable()
var power : PowerGrid #a portable generator on the floor runs on it (see PortableGeneratorItem)

const SEEN_FADE_PER_SECOND : float = 8.0 #how quickly an item comes into view and goes out of it (the same as blood)

var _pickups : Dictionary = {} #pickup id -> Pickup, everything still on the floor
var _pending : Array[Dictionary] = [] #{kind, tick, peer, ...}, in the order they were accepted
var _next_id : int = 0
var _next_drop_id : int = DROP_ID_BASE #lobby
var _active : bool = true


func _ready() -> void:
	add_to_group(GROUP)
	NetworkTime.before_tick.connect(_on_before_tick)


func _exit_tree() -> void:
	if NetworkTime.before_tick.is_connected(_on_before_tick):
		NetworkTime.before_tick.disconnect(_on_before_tick)


##Puts an item on the floor. id: the lobby's number for a dropped item; -1 numbers it in spawn order (every peer places the same pickups in the same order).
func spawn(item : Item, world_position : Vector2, can_take : Callable = Callable(), id : int = -1, placed_by : int = -1, placed_facing : float = 0.0) -> Pickup:
	var pickup : Pickup = pickup_scene.instantiate()
	pickup.item = item
	pickup.control = self
	pickup.can_take = can_take
	pickup.placed_by = placed_by
	pickup.placed_facing = placed_facing
	if id < 0:
		id = _next_id
		_next_id += 1
	pickup.pickup_id = id
	_pickups[id] = pickup
	spawn_parent.add_child(pickup)
	pickup.global_position = world_position
	if sight.is_valid():
		pickup.seen = sight.call(world_position) #(one out of sight does not flash in for a moment)
	item.on_floor(pickup, self)
	return pickup


func _process(delta : float) -> void:
	if not sight.is_valid():
		return
	for entry in _pickups.values(): #(untyped: one freed by someone else is a freed object, which a typed variable refuses)
		if is_instance_valid(entry):
			var pickup : Pickup = entry
			pickup.seen = move_toward(pickup.seen, sight.call(pickup.global_position), SEEN_FADE_PER_SECOND * delta)


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


##Ask to drop the item in this slot of the local player's inventory where they stand.
func request_drop(slot : int) -> void:
	if not _active:
		return
	if _is_lobby():
		_decide_drop(multiplayer.get_unique_id(), slot)
	else:
		_request_drop.rpc_id(1, slot)


##The local player clicked with the item in this slot chosen (one that is not drawn: see Item.click_use). Placing is dropping; using up goes through consume.
func request_use(slot : int) -> void:
	if not _active:
		return
	if _is_lobby():
		_decide_use(multiplayer.get_unique_id(), slot)
	else:
		_request_use.rpc_id(1, slot)


##Lobby: everything this player carries falls round them (they died). Safe to call for anyone; the changes go to every peer.
func drop_all(player : Player) -> void:
	if not _active or not _is_lobby() or not is_instance_valid(player):
		return
	var peer_id : int = player.member_id()
	var first_id : int = _next_drop_id
	_next_drop_id += Inventory.SLOT_COUNT
	_accept({"kind": "drop_all", "tick": _after_pending(peer_id), "peer": peer_id, "id": first_id, "at": _body_position(player), "rounds": player.inventory.reserve_now()})


##Lobby: puts these items in the player's free slots (those that do not fit are not given). reset: the inventory is set to exactly these instead, and the
##ammunition starts over on the same tick everywhere (a respawn: see Inventory.set_items). Returns false while another change for the player is on its way: try later.
func give(player : Player, items : Array[Item], reset : bool = false) -> bool:
	if not _active or not _is_lobby() or not is_instance_valid(player) or _has_pending(player.member_id()):
		return false
	var paths : PackedStringArray = PackedStringArray()
	for item in items:
		if item != null and item.resource_path != "":
			paths.append(item.resource_path)
	if not reset and (paths.is_empty() or player.inventory.first_free_slot() < 0):
		return false
	_accept({"kind": "give", "tick": NetworkTime.tick + apply_delay_ticks, "peer": player.member_id(), "paths": paths, "reset": reset})
	return true


##Lobby: gives a player back their starting kit (a respawn after dying: what they carried was dropped where they fell).
func restock(player : Player) -> void:
	if not is_instance_valid(player):
		return
	if not give(player, player.starting_items, true): #(a change still on its way: tried again shortly)
		get_tree().create_timer(0.3).timeout.connect(restock.bind(player))


##Stops sending and applying changes. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false
	_pending.clear()


# ------------------------------------------------------------------ the lobby decides
func _decide(peer_id : int, id : int) -> void:
	var found : Variant = _pickups.get(id) #(untyped until checked: one freed by someone else is a freed object, which a typed variable refuses)
	if not is_instance_valid(found):
		return
	var pickup : Pickup = found
	if _pending.any(func(change : Dictionary) -> bool: return change.get("id", -1) == id or change["peer"] == peer_id):
		return
	var player : Player = player_lookup.call(peer_id)
	if player == null or not player.is_alive() or not pickup.is_in_reach(player.global_position, reach_slack) or not pickup.can_interact(player):
		return
	var slot : int = pickup.item.slot_for(player.inventory)
	if slot < 0:
		return
	_accept({"kind": "take", "tick": NetworkTime.tick + apply_delay_ticks, "id": id, "peer": peer_id, "slot": slot})


func _decide_drop(peer_id : int, slot : int) -> void:
	var player : Player = _living(peer_id)
	if player == null or slot < 0 or slot >= Inventory.SLOT_COUNT or player.inventory.slots[slot] == null or _has_pending(peer_id):
		return
	var id : int = _next_drop_id
	_next_drop_id += 1
	_accept({"kind": "drop", "tick": NetworkTime.tick + apply_delay_ticks, "peer": peer_id, "slot": slot, "id": id, "at": player.global_position, "rounds": player.inventory.reserve_now(), "facing": _facing_of(player)})


## The way a player faces (towards their aim), in radians.
func _facing_of(player : Player) -> float:
	var aim : Vector2 = player.input.aim - player.global_position
	return aim.angle() if not aim.is_zero_approx() else 0.0


## Where a thrown item lands: towards the player's aim, no further than its throw range, and short of the first wall or shut door.
func _landing_of(player : Player, item : Item) -> Vector2:
	var from : Vector2 = player.global_position
	var aim : Vector2 = player.input.aim - from
	if aim.is_zero_approx():
		return from
	var to : Vector2 = from + aim.limit_length(item.throw_range_px)
	if not player.is_inside_tree():
		return to
	var hit : Dictionary = player.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER))
	return to if hit.is_empty() else (hit["position"] as Vector2) - aim.normalized() * 10.0


##Lobby: takes a pickup off the floor on every peer (a coms hacker that was shot). Safe to call for one already gone.
func destroy(pickup : Pickup) -> void:
	if not _active or not _is_lobby() or not is_instance_valid(pickup) or not _pickups.has(pickup.pickup_id):
		return
	if _pending.any(func(change : Dictionary) -> bool: return change.get("id", -1) == pickup.pickup_id):
		return
	_accept({"kind": "destroy", "tick": NetworkTime.tick + apply_delay_ticks, "peer": -1, "id": pickup.pickup_id})


func _decide_use(peer_id : int, slot : int) -> void:
	var player : Player = _living(peer_id)
	if player == null or slot < 0 or slot >= Inventory.SLOT_COUNT or player.inventory.slots[slot] == null or _has_pending(peer_id):
		return
	var item : Item = player.inventory.slots[slot]
	match item.click_use:
		Item.ClickUse.PLACE:
			_decide_drop(peer_id, slot)
		Item.ClickUse.CONSUME:
			if item.can_consume(player):
				_accept({"kind": "consume", "tick": NetworkTime.tick + apply_delay_ticks, "peer": peer_id, "slot": slot})
		Item.ClickUse.THROW:
			_accept({"kind": "throw", "tick": NetworkTime.tick + apply_delay_ticks, "peer": peer_id, "slot": slot, "at": _landing_of(player, item)})


func _living(peer_id : int) -> Player:
	var player : Variant = player_lookup.call(peer_id) if player_lookup.is_valid() else null
	return player if is_instance_valid(player) and (player as Player).is_alive() else null


func _has_pending(peer_id : int) -> bool:
	return _pending.any(func(change : Dictionary) -> bool: return change["peer"] == peer_id)


## The tick a change for this player can go on: after every change already on its way for them.
func _after_pending(peer_id : int) -> int:
	var tick : int = NetworkTime.tick + apply_delay_ticks
	for change in _pending:
		if change["peer"] == peer_id:
			tick = maxi(tick, int(change["tick"]))
	return tick


## Where a fallen player's things land round: their body, not where they stood (the body falls a little way).
func _body_position(player : Player) -> Vector2:
	return player.skin.body_position() if player.skin != null else player.global_position


func _accept(change : Dictionary) -> void:
	_schedule(change)
	if multiplayer.multiplayer_peer != null and not multiplayer.get_peers().is_empty():
		_schedule_remote.rpc(change)


# ------------------------------------------------------------------ every peer applies
func _schedule(change : Dictionary) -> void:
	_pending.append(change)
	if int(change["tick"]) <= NetworkTime.tick: #arrived late: catch up now rather than wait for a tick that has passed
		_apply_due(NetworkTime.tick)


func _on_before_tick(_delta : float, tick : int) -> void:
	_apply_due(tick)


func _apply_due(tick : int) -> void:
	if _pending.is_empty() or not _active:
		return
	var still_pending : Array[Dictionary] = []
	var due : Array[Dictionary] = []
	for change in _pending:
		if int(change["tick"]) <= tick:
			due.append(change)
		else:
			still_pending.append(change)
	_pending = still_pending
	for change in due:
		_apply(change)


func _apply(change : Dictionary) -> void:
	if String(change.get("kind", "")) == "destroy": #(nobody's change: no player to look up)
		var found : Variant = _pickups.get(change["id"])
		if is_instance_valid(found):
			(found as Pickup).item.off_floor(found, self)
			_pickups.erase(change["id"])
			(found as Pickup).queue_free()
		return
	var player : Player = player_lookup.call(change["peer"]) if player_lookup.is_valid() else null
	if not is_instance_valid(player): #the player left first: nothing moves
		return
	match String(change.get("kind", "take")):
		"take": _apply_take(change, player)
		"drop": _apply_drop(change, player)
		"drop_all": _apply_drop_all(change, player)
		"consume": _apply_consume(change, player)
		"give": _apply_give(change, player)
		"throw": _apply_throw(change, player)


func _apply_take(change : Dictionary, player : Player) -> void:
	var found : Variant = _pickups.get(change["id"]) #(untyped until checked, as in _decide)
	if not is_instance_valid(found):
		return
	var pickup : Pickup = found
	pickup.item.off_floor(pickup, self)
	pickup.item.put_into(player.inventory, change["slot"], change["tick"])
	_pickups.erase(change["id"])
	pickup.queue_free()


func _apply_drop(change : Dictionary, player : Player) -> void:
	_drop_slot(player, int(change["slot"]), int(change["id"]), change["at"], int(change["rounds"]), int(change["tick"]), int(change["peer"]), float(change.get("facing", 0.0)))


func _apply_throw(change : Dictionary, player : Player) -> void:
	var slot : int = change["slot"]
	var item : Item = player.inventory.slots[slot]
	if item == null:
		return
	player.inventory.put_in_slot(slot, null)
	item.thrown(change["at"], self)


func _apply_drop_all(change : Dictionary, player : Player) -> void:
	var at : Vector2 = change["at"]
	var carried : Array[int] = []
	for slot in Inventory.SLOT_COUNT:
		if player.inventory.slots[slot] != null:
			carried.append(slot)
	for i in carried.size():
		var offset : Vector2 = Vector2.ZERO if carried.size() == 1 else Vector2.from_angle(TAU * i / carried.size() + 0.4) * drop_spread_px
		_drop_slot(player, carried[i], int(change["id"]) + carried[i], _clear_spot(at, at + offset), int(change["rounds"]), int(change["tick"]))


func _apply_consume(change : Dictionary, player : Player) -> void:
	var slot : int = change["slot"]
	var item : Item = player.inventory.slots[slot]
	if item == null:
		return
	if _is_lobby() and item.can_consume(player): #(its effect is the lobby's to make: the health it changes is synced to everyone)
		item.consume_on(player)
	player.inventory.put_in_slot(slot, null)


func _apply_give(change : Dictionary, player : Player) -> void:
	var items : Array[Item] = []
	for path : String in change["paths"]:
		var item : Item = load(path) as Item
		if item != null:
			items.append(item)
	if change.get("reset", false):
		player.inventory.set_items(items, int(change["tick"]))
		return
	for item in items:
		var slot : int = item.slot_for(player.inventory)
		if slot >= 0:
			item.put_into(player.inventory, slot, int(change["tick"]))


## Takes the item out of a slot and puts it on the floor. The ammunition box takes the supply with it (rounds: the lobby's count of it).
func _drop_slot(player : Player, slot : int, id : int, at : Vector2, rounds : int, tick : int, placed_by : int = -1, facing : float = 0.0) -> void:
	var item : Item = player.inventory.slots[slot]
	if item == null:
		return
	var on_floor : Item = item
	if item is AmmoItem:
		if rounds <= 0:
			player.inventory.put_in_slot(slot, null)
			return
		player.inventory.add_supply(tick, -rounds)
		var box : AmmoItem = item.duplicate() as AmmoItem
		box.rounds = rounds
		on_floor = box
	player.inventory.put_in_slot(slot, null)
	var rule : Variant = rule_for.call(item) if rule_for.is_valid() else Callable()
	spawn(on_floor, at, rule if rule is Callable else Callable(), id, placed_by, facing)


## `to`, unless a wall or a shut door stands between it and `from`: then `from` (a fallen player's things never land on the far side of a wall).
func _clear_spot(from : Vector2, to : Vector2) -> Vector2:
	if not is_inside_tree() or from == to:
		return to
	var space : PhysicsDirectSpaceState2D = (spawn_parent as Node2D).get_world_2d().direct_space_state if spawn_parent is Node2D else null
	if space == null:
		return to
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to + (to - from).normalized() * 8.0, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER)
	return to if space.intersect_ray(query).is_empty() else from


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(id : int) -> void:
	if _active and multiplayer.is_server():
		_decide(multiplayer.get_remote_sender_id(), id)


@rpc("any_peer", "call_remote", "reliable")
func _request_drop(slot : int) -> void:
	if _active and multiplayer.is_server():
		_decide_drop(multiplayer.get_remote_sender_id(), slot)


@rpc("any_peer", "call_remote", "reliable")
func _request_use(slot : int) -> void:
	if _active and multiplayer.is_server():
		_decide_use(multiplayer.get_remote_sender_id(), slot)


@rpc("authority", "call_remote", "reliable")
func _schedule_remote(change : Dictionary) -> void:
	if not _active:
		return
	if change.get("kind", "take") == "take" and not _pickups.has(change["id"]):
		return
	_schedule(change)
