@tool
class_name IntruderSpawn
extends SpawnRoomMarker

##Makes the room it stands on an intruder spawn room (see SpawnRoomMarker).


func _init() -> void:
	kind = Kind.INTRUDER
