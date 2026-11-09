class_name TargetArtifactChooser
extends Node

##Picks which of the placed artifacts the attackers are after. Secret: the lobby chooses, and only attackers are told, so `target` stays null on a
##defender's game. Intruders and secretly attacking guards are both attackers.

@export var placer : ArtifactPlacer

var target : Artifact #null where this peer may not know it


##Lobby only. picks is ArtifactPlacer.roll()'s result. Returns the chosen index into placer.artifacts, -1 if nothing was placed.
func choose(picks : PackedInt32Array, rng : RandomNumberGenerator) -> int:
	return picks[rng.randi_range(0, picks.size() - 1)] if not picks.is_empty() else -1


func set_target(artifact_index : int) -> void:
	target = placer.artifacts[artifact_index] if artifact_index >= 0 else null
