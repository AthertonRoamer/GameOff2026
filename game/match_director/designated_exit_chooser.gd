class_name DesignatedExitChooser
extends Node

##Picks which exit zone counts this match: the attackers only win by carrying the target artifact out through this one (see ArtifactEscape).
##Secret, like the target: the lobby chooses, and only attackers are told, so `designated` stays "" on a defender's game. Attackers see it on the
##map while they choose where to start (SpawnSelectPhase).

var designated : String = "" #the exit's id (its FacilityRoom node name), or "" where this peer may not know it


##Lobby only. exit_ids: FacilityMap.exits' keys. Returns "" when the map has no exits.
func choose(exit_ids : Array, rng : RandomNumberGenerator) -> String:
	return exit_ids[rng.randi_range(0, exit_ids.size() - 1)] if not exit_ids.is_empty() else ""


func set_designated(exit_id : String) -> void:
	designated = exit_id
