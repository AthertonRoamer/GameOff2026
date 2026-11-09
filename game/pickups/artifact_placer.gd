class_name ArtifactPlacer
extends Node

##Puts a different, randomly chosen artifact on every ArtifactLocation in the map, and decides who may carry artifacts.
##The lobby rolls the picks once and sends them to every peer, so everyone places the same artifacts in the same spots.
##Intruders can always take artifacts; the exports cover the guards. Teams are only known where they may be, but that is enough here: a player only
##needs their own team to see the prompt, and the lobby, which decides, knows every team.

@export var artifacts : Array[Artifact] = []
@export var pickups : PickupControl
@export var attacking_guards_can_pick_up : bool = true
@export var defenders_can_pick_up : bool = false


##Lobby only. Which artifact goes on each location: indices into artifacts, one per location, all different.
func roll(rng : RandomNumberGenerator) -> PackedInt32Array:
	var location_count : int = get_tree().get_node_count_in_group(ArtifactLocation.GROUP)
	if location_count > artifacts.size():
		push_warning("ArtifactPlacer: %d locations but only %d artifacts, some locations stay empty" % [location_count, artifacts.size()])
	var pool : Array = range(artifacts.size())
	var picks : PackedInt32Array = PackedInt32Array()
	for i in mini(location_count, artifacts.size()):
		picks.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return picks


func place(picks : PackedInt32Array) -> void:
	var locations : Array[Node] = get_tree().get_nodes_in_group(ArtifactLocation.GROUP)
	for i in picks.size():
		pickups.spawn(artifacts[picks[i]], (locations[i] as ArtifactLocation).global_position, _can_player_carry)


func can_carry(team : int, is_intruder : bool) -> bool:
	if team != Team.ATTACKERS:
		return defenders_can_pick_up
	return is_intruder or attacking_guards_can_pick_up


func _can_player_carry(player : Player) -> bool:
	return can_carry(player.team, player.role != null and player.role.is_intruder())
