extends Node

## Prints a summary of a built facility map (rooms, floor and wall cells, doors, vents) to compare one build of the map against another:
##   godot --headless --path . res://tools/art/dump_facility.tscn [-- <output file>]
##(a scene, not --script: the map's consoles use the game's autoloads)

func _ready() -> void:
	var map : FacilityMap = (load("res://night_shift/environment/facility_map.tscn") as PackedScene).instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	var lines : PackedStringArray = []
	var room_ids : Array = map.rooms.keys()
	room_ids.sort()
	for id : String in room_ids:
		var room : Dictionary = map.rooms[id]
		var rects : Array = []
		for rect : Rect2i in room["rects"]:
			rects.append("%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.end.x - 1, rect.end.y - 1])
		rects.sort()
		lines.append("room %s name=%s kind=%s function=%s exterior=%s rects=%s" % [id, room["name"], room["kind"], room["function"], room["exterior"], " ".join(rects)])
	var floor_keys : Array = map.floor_cells.keys()
	floor_keys.sort()
	var floor_text : PackedStringArray = []
	for cell : Vector2i in floor_keys:
		floor_text.append("%d,%d" % [cell.x, cell.y])
	lines.append("floor_cells %d hash=%d" % [floor_keys.size(), ",".join(floor_text).hash()])
	var wall_keys : Array = map.wall_cells.keys()
	wall_keys.sort()
	var wall_text : PackedStringArray = []
	for cell : Vector2i in wall_keys:
		wall_text.append("%d,%d" % [cell.x, cell.y])
	lines.append("wall_cells %d hash=%d" % [wall_keys.size(), ",".join(wall_text).hash()])
	lines.append("painted floors=%d walls=%d shadows=%d" % [map.floors.get_used_cells().size(), map.walls.get_used_cells().size(), map.shadows.get_used_cells().size()])
	var door_lines : Array = []
	for door : FacilityDoor in map.doors:
		var pair : Array = [door.room_a, door.room_b]
		pair.sort()
		door_lines.append("door pos=%s horizontal=%s exterior=%s rooms=%s" % [door.position, door.horizontal, door.exterior, "-".join(pair)])
	door_lines.sort()
	lines.append_array(PackedStringArray(door_lines))
	lines.append("doors %d" % map.doors.size())
	var vent_text : Array = []
	for vent : Vector2i in map.vents:
		vent_text.append("%d,%d" % [vent.x, vent.y])
	vent_text.sort()
	lines.append("vents %s" % " ".join(vent_text))
	lines.append("bounds %s" % map.map_bounds_px())
	var path : String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://facility_dump.txt"
	var file : FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("dump written: ", ProjectSettings.globalize_path(path))
	get_tree().quit()