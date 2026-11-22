@tool
class_name GuardSpawn
extends SpawnRoomMarker

##Makes the room it stands on a guard spawn room (see SpawnRoomMarker).


func _init() -> void:
	kind = Kind.GUARD
