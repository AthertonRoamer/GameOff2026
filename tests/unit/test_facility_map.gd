extends Node

# Offline test of the facility map scene (night_shift/environment/facility_map.tscn): the things that can silently break when it is edited in the
# editor. Run as a scene so the project autoloads exist (the map has consoles that use them):
#   Godot_console.exe --headless --path . res://tests/unit/test_facility_map.tscn

const MAP_SCENE : PackedScene = preload("res://night_shift/environment/facility_map.tscn")

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	var map : FacilityMap = MAP_SCENE.instantiate()
	add_child(map)
	await get_tree().process_frame

	check(map.rooms.size() > 0, "the map has rooms (%d)" % map.rooms.size())
	var owner_of : Dictionary = {} #cell -> room id, to catch two different rooms sharing a cell (one room's own rectangles may touch or overlap)
	var clashes : int = 0
	for id : String in map.rooms:
		var rects : Array = map.rooms[id]["rects"]
		check(not rects.is_empty(), "room %s has a floor" % id)
		for rect : Rect2i in rects:
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var cell : Vector2i = Vector2i(x, y)
					if owner_of.has(cell) and owner_of[cell] != id:
						clashes += 1
					owner_of[cell] = id
	check(clashes == 0, "no two rooms share a cell (%d clashes)" % clashes)
	check(map.floor_cells.size() == owner_of.size() + map.doors.size() * 4, "the floor is the rooms plus the door cells (%d cells)" % map.floor_cells.size())
	check(map.doors.size() > 0, "the map has doors (%d)" % map.doors.size())
	for i in map.doors.size():
		var door : FacilityDoor = map.doors[i]
		check(door.door_index == i, "door %s is number %d" % [door.name, i])
		check(door.room_a != "" and door.room_b != "" and door.room_a != door.room_b, "door %s joins two different rooms (%s, %s)" % [door.name, door.room_a, door.room_b])
		var cells : Rect2i = door.cell_rect(map)
		var centre : Vector2 = Vector2(cells.position * FacilityTileSet.TILE) + Vector2(cells.size * FacilityTileSet.TILE) / 2.0
		check(door.position.is_equal_approx(centre), "door %s sits on the cell grid" % door.name)
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				check(map.floor_cells.has(Vector2i(x, y)) and not map.wall_cells.has(Vector2i(x, y)), "door %s cell %d,%d is floor, not wall" % [door.name, x, y])

	check(map.wall_cells.size() > 0 and map.floors.get_used_cells().size() == map.floor_cells.size(), "the floor layer is painted from the rooms")
	check(map.walls.get_used_cells().size() == map.wall_cells.size(), "the wall layer is painted from the walls")
	check(map.actors != null and map.props_node != null, "the map has an Actors and a Props node")

	var panels : int = 0
	for node : Node in map.props_node.get_children():
		if node is ControlPanel:
			panels += 1
			check((node as ControlPanel).screen_scene != null, "console %s has a screen scene" % node.name)
			var room : String = map.room_at(node.position)
			check(room != "" and map.rooms[room]["function"] == (node as ControlPanel).function, "console %s stands in a room whose function is %s (in %s)" % [node.name, (node as ControlPanel).function, room])
	check(panels > 0, "there is at least one console (%d)" % panels)

	#resizing a room only changes its rectangle: the floor, walls and shadows follow, nothing else is touched
	check(map.floors.owner == null and map.walls.owner == null and map.shadows.owner == null, "the tile layers are made by the map, not part of the scene file")
	var archive : FacilityRoom = map.rooms_node.get_node("archive")
	var rect : FacilityRoomRect = archive.rects()[0]
	var original_size : Vector2 = rect.size
	var rows : int = roundi(rect.size.y / FacilityTileSet.TILE)
	var floor_before : int = map.floor_cells.size()
	var walls_before : int = map.wall_cells.size()
	rect.size = original_size - Vector2(2.0 * FacilityTileSet.TILE, 0.0) #two cells narrower
	map.build()
	check(map.floor_cells.size() == floor_before - 2 * rows, "a room two cells narrower loses two columns of floor (%d -> %d)" % [floor_before, map.floor_cells.size()])
	check(map.wall_cells.size() < walls_before, "the walls are rebuilt around the smaller room (%d -> %d)" % [walls_before, map.wall_cells.size()])
	check(map.floors.get_used_cells().size() == map.floor_cells.size() and map.walls.get_used_cells().size() == map.wall_cells.size(), "the tile layers match the resized room")
	rect.size = Vector2(50.0, 50.0)
	rect.position = Vector2(rect.position.x + 3.0, rect.position.y + 4.0)
	rect.snap_to_grid()
	check(is_equal_approx(rect.size.x, 55.0) and is_equal_approx(rect.size.y, 55.0) and is_equal_approx(fmod(rect.position.x, FacilityTileSet.TILE), 0.0) and is_equal_approx(fmod(rect.position.y, FacilityTileSet.TILE), 0.0), "a rectangle dragged off the grid snaps to whole cells")
	rect.size = original_size
	map.build()
	check(map.floor_cells.size() == floor_before and map.wall_cells.size() == walls_before, "putting the size back gives the same floor and walls")
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)