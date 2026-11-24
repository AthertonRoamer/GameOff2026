class_name AbilityControl
extends Node

##What the roles can do that changes the shared game, decided by the lobby (the same way FacilityControl owns the doors and PickupControl the items):
##  revive   a medic (Role.can_revive) brings a fallen player back to their feet
##  vent     a ventrat (Role.can_vent) travels from one vent of the map to another
## A peer asks (request_revive, request_vent); the lobby checks the asker is who they say (alive, with the role, within reach as the lobby sees them) and that the
## ability is not on cooldown, and then does it. The result needs no message of its own: a revived player's health and a moved player's position are what the lobby
## already syncs to every peer. Offline (the playground) the local peer is the lobby, so the same path runs with no network.
## The vents are the Marker2D nodes under the map's `Vents` node: build() makes an interactable Vent of each.

const SCREEN_LAYER : int = 20
const VENT_SCREEN : PackedScene = preload("res://game/abilities/vent_screen.tscn")

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

var _active : bool = true
var _ready_at : Dictionary = {} #lobby: "revive" or "vent" + peer id -> the time (msec) the ability can be used again


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
	vent_screen = VENT_SCREEN.instantiate()
	vent_screen.facility = map
	vent_screen.control = self
	layer.add_child(vent_screen)


## Stops sending and acting. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false


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
