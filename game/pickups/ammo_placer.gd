class_name AmmoPlacer
extends Node

##Puts a box of ammo on every AmmoLocation in the map. Every peer calls place() in the same order as the other placers (the pickups are numbered as they are made).
##In a deathmatch nobody has a supply but what they carry, so the lobby also brings a new box to an empty location every trickle_seconds (start_trickle). That
##is the lobby's decision, told to every peer in one reliable message, so the pickups keep the same numbers everywhere.

@export var ammo : AmmoItem
@export var pickups : PickupControl
@export var trickle_seconds : float = 30.0 ## in a deathmatch: how often a box turns up at a location that has none

var _boxes : Dictionary = {} #location index -> the Pickup lying there
var _trickling : bool = false
var _since_box : float = 0.0


func place() -> void:
	var locations : Array[Node] = get_tree().get_nodes_in_group(AmmoLocation.GROUP)
	for i in locations.size():
		_put(i)


## Lobby only: from now on a box turns up every trickle_seconds, at a location that is empty.
func start_trickle() -> void:
	_trickling = true
	_since_box = 0.0


func quiesce() -> void:
	_trickling = false


func _process(delta : float) -> void:
	if not _trickling:
		return
	_since_box += delta
	if _since_box < trickle_seconds:
		return
	_since_box = 0.0
	var empty : Array[int] = empty_locations()
	if empty.is_empty():
		return
	var index : int = empty[randi() % empty.size()]
	if multiplayer.multiplayer_peer != null and not multiplayer.get_peers().is_empty():
		_put_remote.rpc(index)
	_put(index)


## The locations with no box on them now.
func empty_locations() -> Array[int]:
	var empty : Array[int] = []
	for i in get_tree().get_nodes_in_group(AmmoLocation.GROUP).size():
		if not is_instance_valid(_boxes.get(i)):
			empty.append(i)
	return empty


func _put(index : int) -> void:
	var locations : Array[Node] = get_tree().get_nodes_in_group(AmmoLocation.GROUP)
	if index >= 0 and index < locations.size():
		_boxes[index] = pickups.spawn(ammo, (locations[index] as AmmoLocation).global_position)


@rpc("authority", "call_remote", "reliable")
func _put_remote(index : int) -> void:
	_put(index)
