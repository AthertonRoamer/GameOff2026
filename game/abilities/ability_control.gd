class_name AbilityControl
extends Node

##What the roles can do that changes the shared game, decided by the lobby (the same way FacilityControl owns the doors and PickupControl the items):
##  revive   a medic (Role.can_revive) brings a fallen player back to their feet
##  vent     a ventrat (Role.can_vent) travels from one vent of the map to another
##  medicine a medic (Role.medicine_item) has a dose of medicine ready to make every so often (start_medicine); holding Q makes it, and it goes into their
##           inventory through PickupControl like any item
## A peer asks (request_revive, request_vent); the lobby checks the asker is who they say (alive, with the role, within reach as the lobby sees them) and that the
## ability is not on cooldown, and then does it. The result needs no message of its own: a revived player's health and a moved player's position are what the lobby
## already syncs to every peer. Offline (the playground) the local peer is the lobby, so the same path runs with no network.
## The vents are the Marker2D nodes under the map's `Vents` node: build() makes an interactable Vent of each.

const SCREEN_LAYER : int = 20
const VENT_SCREEN : String = "res://game/abilities/vent_screen.tscn" #(loaded when needed: the screen's map knows MapIntel, which knows this script, so a preload would go round in a circle)

@export_group("Revive")
@export_range(0.05, 1.0, 0.05) var revive_health_fraction : float = 0.5 ## the share of their health a revived player comes back with
@export_range(5.0, 300.0, 1.0, "suffix:s") var revive_window_seconds : float = 45.0 ## how long after falling a player can still be revived
@export_range(0.0, 60.0, 0.5, "suffix:s") var revive_cooldown_seconds : float = 8.0
@export_range(0.5, 4.0, 0.1, "suffix:m") var revive_reach_m : float = 1.4
@export_group("Vents")
@export_range(0.0, 60.0, 0.5, "suffix:s") var vent_cooldown_seconds : float = 5.0
@export_range(0.5, 4.0, 0.1) var reach_slack : float = 1.5 ## the lobby's view of a player is a few ticks behind, so its reach checks are a little looser

var player_lookup : Callable = Callable() ## (peer_id : int) -> Player or null. Set by the game
var facility : FacilityMap
var vents : Array[Vent] = []
var vent_screen : VentScreen
var pickups : PickupControl ## where a medic's medicine is handed over (set by the game)
var players : Callable = Callable() ## () -> Array of Player (set by the game)

var _active : bool = true
var _ready_at : Dictionary = {} #lobby: "revive" or "vent" + peer id -> the time (msec) the ability can be used again
var _medicine_clock : Dictionary = {} #lobby: player -> seconds towards their next dose
var _making_medicine : bool = false
var _medicine_sync_in : float = 0.0
var _make_holds : Dictionary = {} #lobby: peer id -> when (msec) they began holding Q to make medicine
const MAKE_HOLD_SLACK_SECONDS : float = 0.6 #the lobby lets the hold be this much shorter than it should, for the time the messages take
const GROUP : StringName = &"ability_control"
const MEDICINE_SYNC_SECONDS : float = 0.5 #how often the lobby tells each medic how far along their next dose is

## This peer's own player's next dose of medicine, as the lobby last said (the HUD's bar). own_medicine_ready: the bar is full, and holding Q makes the dose
var own_medicine_known : bool = false
var own_medicine_clock : float = 0.0
var own_medicine_seconds : float = 60.0
var own_medicine_ready : bool = false
var own_player : Callable = Callable() ## () -> this peer's own Player or null (set by the game): its bar stands still while it is dead


func _ready() -> void:
	add_to_group(GROUP)


## Once the map is built: makes the vents and their screen.
func build(map : FacilityMap) -> void:
	facility = map
	var markers : Node = map.get_node_or_null("Vents")
	if markers != null:
		for marker : Node in markers.get_children():
			if marker is Node2D:
				var vent : Vent = Vent.new()
				vent.name = "Vent%d" % vents.size()
				vent.index = vents.size()
				vent.control = self
				add_child(vent)
				vent.global_position = (marker as Node2D).global_position
				vents.append(vent)
	var layer : CanvasLayer = CanvasLayer.new()
	layer.name = "Screens"
	layer.layer = SCREEN_LAYER
	add_child(layer)
	vent_screen = (load(VENT_SCREEN) as PackedScene).instantiate()
	vent_screen.facility = map
	vent_screen.control = self
	layer.add_child(vent_screen)


## Stops sending and acting. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false
	_making_medicine = false


## Lobby: from now on every living player whose role makes medicine (Role.medicine_item) has a dose ready to make every medicine_seconds. The bar then waits, full, until
## they hold Q to make it (request_make_medicine), and starts over once it is in their inventory.
func start_medicine() -> void:
	_making_medicine = true


func _process(delta : float) -> void:
	if own_medicine_known and not own_medicine_ready and _own_alive(): #(between the lobby's word, this peer's own bar moves on by itself)
		own_medicine_clock = minf(own_medicine_clock + delta, own_medicine_seconds)
	if not _making_medicine or not _active or not players.is_valid() or not _is_lobby():
		return
	_medicine_sync_in -= delta
	var sync_now : bool = _medicine_sync_in <= 0.0
	if sync_now:
		_medicine_sync_in = MEDICINE_SYNC_SECONDS
	for entry : Variant in players.call():
		if not is_instance_valid(entry):
			continue
		var player : Player = entry
		if player.role == null or player.role.medicine_item == null:
			continue
		var clock : float = float(_medicine_clock.get(player, 0.0))
		if player.is_alive(): #(a dead medic's time stands still)
			clock = minf(clock + delta, player.role.medicine_seconds)
		_medicine_clock[player] = clock
		if sync_now:
			_send_medicine(player)


## A medic began holding Q to make their dose (started), or let go before it was done. Safe to call on any peer; only the lobby keeps it.
func request_make_hold(started : bool) -> void:
	if not _active:
		return
	if _is_lobby():
		_decide_make_hold(multiplayer.get_unique_id(), started)
	else:
		_request_make_hold.rpc_id(1, started)


## The medic's hold on Q is done: make the dose. This peer's bar starts over at once; the lobby has the last word.
func request_make_medicine() -> void:
	if not _active:
		return
	own_medicine_ready = false
	own_medicine_clock = 0.0
	if _is_lobby():
		_decide_make(multiplayer.get_unique_id())
	else:
		_request_make.rpc_id(1)


func _decide_make_hold(peer_id : int, started : bool) -> void:
	if started:
		_make_holds[peer_id] = Time.get_ticks_msec()
	else:
		_make_holds.erase(peer_id)


## Lobby: a living medic whose dose is ready, who held Q long enough, with a free slot: the dose goes into their inventory and their time starts over.
func _decide_make(peer_id : int) -> void:
	var medic : Player = _player(peer_id)
	var since : int = int(_make_holds.get(peer_id, -1))
	_make_holds.erase(peer_id)
	if medic == null or not medic.is_alive() or medic.role == null or medic.role.medicine_item == null or since < 0 or pickups == null:
		if medic != null and medic.role != null and medic.role.medicine_item != null:
			_send_medicine(medic) #(put this peer's bar right)
		return
	var held : float = (Time.get_ticks_msec() - since) / 1000.0
	var ready : bool = float(_medicine_clock.get(medic, 0.0)) >= medic.role.medicine_seconds
	var dose : Array[Item] = [medic.role.medicine_item]
	if ready and held >= medic.role.medicine_make_seconds - MAKE_HOLD_SLACK_SECONDS and pickups.give(medic, dose):
		_medicine_clock[medic] = 0.0
	_send_medicine(medic)


## Lobby: tells a medic's own peer how far along their next dose is (only they see the bar).
func _send_medicine(player : Player) -> void:
	var clock : float = float(_medicine_clock.get(player, 0.0))
	var seconds : float = player.role.medicine_seconds
	var ready : bool = clock >= seconds
	var peer_id : int = player.member_id()
	if multiplayer.multiplayer_peer == null or peer_id == multiplayer.get_unique_id():
		_medicine_sync(clock, seconds, ready)
	elif multiplayer.get_peers().has(peer_id):
		_medicine_sync.rpc_id(peer_id, clock, seconds, ready)


## How far this peer's own player is towards their next dose of medicine, 0 to 1 (the HUD's bar). Only known once the lobby has said (own_medicine_known).
func own_medicine_progress() -> float:
	return clampf(own_medicine_clock / maxf(own_medicine_seconds, 0.001), 0.0, 1.0)


func own_medicine_seconds_left() -> float:
	return maxf(own_medicine_seconds - own_medicine_clock, 0.0)


func _own_alive() -> bool:
	var player : Variant = own_player.call() if own_player.is_valid() else null
	return not is_instance_valid(player) or (player as Player).is_alive()


@rpc("authority", "call_remote", "unreliable_ordered")
func _medicine_sync(clock : float, seconds : float, ready : bool) -> void:
	own_medicine_known = true
	own_medicine_clock = clock
	own_medicine_seconds = seconds
	own_medicine_ready = ready


@rpc("any_peer", "call_remote", "reliable")
func _request_make_hold(started : bool) -> void:
	if _active and multiplayer.is_server():
		_decide_make_hold(multiplayer.get_remote_sender_id(), started)


@rpc("any_peer", "call_remote", "reliable")
func _request_make() -> void:
	if _active and multiplayer.is_server():
		_decide_make(multiplayer.get_remote_sender_id())


## A medic asks to revive a fallen player. Safe to call on any peer; only the lobby decides.
func request_revive(target : Player) -> void:
	if not _active or not is_instance_valid(target):
		return
	if _is_lobby():
		_decide_revive(multiplayer.get_unique_id(), target.member_id())
	else:
		_request_revive.rpc_id(1, target.member_id())


## A ventrat asks to go from one vent to another (indexes into `vents`).
func request_vent(from : Vent, to : Vent) -> void:
	if not _active or from == null or to == null:
		return
	if _is_lobby():
		_decide_vent(multiplayer.get_unique_id(), from.index, to.index)
	else:
		_request_vent.rpc_id(1, from.index, to.index)


## Is this player's revive ready, as far as the peer knows (the prompt hides while it is not)? The lobby's answer is the real one.
func revive_window_open(target : Player) -> bool:
	return not target.is_alive() and (Time.get_ticks_msec() - target.died_at_msec) <= revive_window_seconds * 1000.0


func _decide_revive(peer_id : int, target_id : int) -> void:
	var medic : Player = _player(peer_id)
	var target : Player = _player(target_id)
	if medic == null or target == null or medic == target or not medic.is_alive() or medic.role == null or not medic.role.can_revive:
		return
	if target.is_alive() or not revive_window_open(target) or not _off_cooldown("revive", peer_id):
		return
	if medic.global_position.distance_to(target.skin.body_position()) > revive_reach_m * Acoustics.PX_PER_METRE * reach_slack:
		return
	_start_cooldown("revive", peer_id, revive_cooldown_seconds)
	target.health = target.starting_health * revive_health_fraction #the health sync tells everyone: the body gets up on every peer (Player._on_health_changed)


func _decide_vent(peer_id : int, from_index : int, to_index : int) -> void:
	var player : Player = _player(peer_id)
	if player == null or not player.is_alive() or player.role == null or not player.role.can_vent:
		return
	if from_index < 0 or from_index >= vents.size() or to_index < 0 or to_index >= vents.size() or from_index == to_index:
		return
	if not vents[from_index].is_in_reach(player.global_position, reach_slack) or not _off_cooldown("vent", peer_id):
		return
	_start_cooldown("vent", peer_id, vent_cooldown_seconds)
	player.teleport(vents[to_index].global_position) #the position is synced like any movement


func _player(peer_id : int) -> Player:
	var player : Variant = player_lookup.call(peer_id) if player_lookup.is_valid() else null
	return player if is_instance_valid(player) else null


func _off_cooldown(ability : String, peer_id : int) -> bool:
	return Time.get_ticks_msec() >= _ready_at.get(ability + str(peer_id), 0)


func _start_cooldown(ability : String, peer_id : int, seconds : float) -> void:
	_ready_at[ability + str(peer_id)] = Time.get_ticks_msec() + int(seconds * 1000.0)


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("any_peer", "call_remote", "reliable")
func _request_revive(target_id : int) -> void:
	if _active and multiplayer.is_server():
		_decide_revive(multiplayer.get_remote_sender_id(), target_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_vent(from_index : int, to_index : int) -> void:
	if _active and multiplayer.is_server():
		_decide_vent(multiplayer.get_remote_sender_id(), from_index, to_index)
