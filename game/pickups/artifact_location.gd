class_name ArtifactLocation
extends Marker2D

##A spot where an artifact can be. Place these anywhere in the map; ArtifactPlacer puts a different artifact on each one every match.

const GROUP : StringName = &"artifact_locations"


func _ready() -> void:
	add_to_group(GROUP)
