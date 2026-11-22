extends Node

# Offline test of the facility map scene (game/environment/facility_map.tscn): the things that can silently break when it is edited in the
# editor. Run as a scene so the project autoloads exist (the map has consoles that use them):
#   Godot_console.exe --headless --path . res://tests/unit/test_facility_map.tscn

const MAP_SCENE : PackedScene = preload("res://game/environment/facility_map.tscn")

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

	#exit zones: outside the walls with no tiles of their own, a door into each, invisible walls round them
	check(map.exits.size() > 0, "the map has exit zones (%d)" % map.exits.size())
	await get_tree().physics_frame
	var space : PhysicsDirectSpaceState2D = map.get_world_2d().direct_space_state
	var door_cells : Dictionary = {}
	for door : FacilityDoor in map.doors:
		var cells : Rect2i = door.cell_rect(map)
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				door_cells[Vector2i(x, y)] = true
	for id : String in map.exits:
		check(not map.rooms.has(id), "exit %s is not counted as a room" % id)
		var only_through_doors : bool = true
		var enclosed : bool = true
		for cell : Vector2i in map.exit_cells:
			if map.exit_cells[cell] != id:
				continue
			if map.floor_cells.has(cell) or map.wall_cells.has(cell):
				only_through_doors = false
			for offset in FacilityTileSet.NEIGHBOURS:
				var next : Vector2i = cell + offset
				if map.floor_cells.has(next) and not door_cells.has(next):
					only_through_doors = false
				if not (map.floor_cells.has(next) or map.exit_cells.has(next) or map.wall_cells.has(next) or map.barrier_cells.has(next)):
					enclosed = false
		check(only_through_doors, "exit %s is behind a whole wall, touching floor only at a door" % id)
		check(enclosed, "exit %s is closed in by walls, doors or invisible walls" % id)
		var into : Array = map.doors.filter(func(door : FacilityDoor) -> bool: return door.room_a == id or door.room_b == id)
		check(into.size() > 0, "a door leads into exit %s" % id)
		for door : FacilityDoor in into:
			var other : String = door.room_b if door.room_a == id else door.room_a
			check(map.rooms.has(other) and door.exterior, "door %s joins exit %s to a room (%s) and is an exterior door" % [door.name, id, other])
			check(map.rooms.has(map.floor_cells.get(door.cell_rect(map).position, "")), "the floor under door %s belongs to the room, not the exit" % door.name)
		var rect : Rect2i = map.exits[id][0]
		var centre : Vector2 = Vector2(rect.position * FacilityTileSet.TILE) + Vector2(rect.size * FacilityTileSet.TILE) / 2.0
		check(map.is_in_exit(centre) and map.exit_at(centre) == id, "the middle of exit %s is in it" % id)
	check(not map.is_in_exit(map.room_center_px("ring")), "the middle of the ring is not an exit")
	#spawn rooms: each GuardSpawn / IntruderSpawn marker makes the room it stands on a spawn room of its kind
	var markers : Array[SpawnRoomMarker] = map.spawn_markers()
	check(markers.size() > 0, "the map has spawn markers (%d)" % markers.size())
	for marker : SpawnRoomMarker in markers:
		var room : String = map.room_at(map.to_local(marker.global_position))
		check(room != "" and map.exit_at(marker.position) == "", "spawn marker %s stands on a room's floor (%s)" % [marker.name, room])
		check(map.spawn_rooms(marker.kind).has(room), "and %s is a spawn room for %ss" % [room, SpawnRoomMarker.name_of(marker.kind)])
	for spawn_kind in [SpawnRoomMarker.Kind.GUARD, SpawnRoomMarker.Kind.INTRUDER]:
		check(not map.spawn_rooms(spawn_kind).is_empty(), "there is at least one spawn room for %ss" % SpawnRoomMarker.name_of(spawn_kind))
		check(not map.spawn_rooms(spawn_kind).any(func(r : String) -> bool: return map.exits.has(r)), "no exit is a spawn room for %ss" % SpawnRoomMarker.name_of(spawn_kind))

	check(map.barrier_cells.size() > 0, "the exits have invisible walls (%d cells)" % map.barrier_cells.size())
	var barriers_ok : bool = true
	for cell : Vector2i in map.barrier_cells:
		if map.floor_cells.has(cell) or map.wall_cells.has(cell) or map.exit_cells.has(cell) or map.walls.get_cell_source_id(cell) != -1:
			barriers_ok = false
	check(barriers_ok, "invisible walls are never floor, wall or exit, and draw no tile")
	var solid : bool = true
	for cell : Vector2i in map.barrier_cells:
		var query : PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
		query.position = map.to_global(map.cell_to_world(cell))
		query.collision_mask = FacilityTileSet.WORLD_LAYER
		if space.intersect_point(query).is_empty():
			solid = false
	check(solid, "every invisible wall cell blocks players")

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
	check(map.wall_cells.size() != walls_before, "the walls are rebuilt around the smaller room (%d -> %d)" % [walls_before, map.wall_cells.size()])
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