extends Node

# Offline test of the map streaming (game/environment/map_streamer.gd) on the big map: tiles are painted only near the view and erased when it leaves, and Decor
# comes into the tree and goes out of it. Run as a scene:
#   Godot_console.exe --headless --path . res://tests/unit/test_map_streaming.tscn

var failures : int = 0


func check(condition : bool, what : String) -> void:
	print(("  ok   " if condition else "  FAIL ") + what)
	if not condition:
		failures += 1


func _ready() -> void:
	var map : FacilityMap = (load("res://game/environment/facility_map_wings.tscn") as PackedScene).instantiate()
	var near : Node2D = Node2D.new() #two pieces of decor, one in the atrium and one in the east
	near.name = "NearDecor"
	var far : Node2D = Node2D.new()
	far.name = "FarDecor"
	map.get_node("Decor").add_child(near)
	map.get_node("Decor").add_child(far)
	near.position = (map as FacilityMap).get_node("Rooms/atrium/Rect1").position + Vector2(200, 200)
	far.position = (map as FacilityMap).get_node("Rooms/east_generator/Rect1").position + Vector2(200, 200)
	add_child(map)
	await get_tree().process_frame
	check(map.rooms.size() > 50 and map.doors.size() > 100, "the big map is built (%d rooms, %d doors)" % [map.rooms.size(), map.doors.size()])
	check(map.floors.get_used_cells().is_empty(), "nothing is painted until there is a view")
	check(map.room_at(near.position) == "atrium" and map.room_at(far.position) == "east_generator", "room_at finds the rooms")
	check(map.is_floor(map.world_to_cell(near.position)) and not map.is_floor(Vector2i(-50, -50)), "is_floor tells floor from void")

	var atrium_view : Rect2 = Rect2(near.position - Vector2(320, 180), Vector2(640, 360))
	var streamer : MapStreamer = map.streamer
	streamer.work_in_headless = true
	streamer.focus = func() -> Rect2: return atrium_view
	for i in 8:
		await get_tree().process_frame
	var near_chunk : Vector2i = map.chunk_of_world(near.position)
	var far_chunk : Vector2i = map.chunk_of_world(far.position)
	check(map.is_chunk_painted(near_chunk), "the chunk in view is painted")
	check(not map.is_chunk_painted(far_chunk), "a chunk far from the view is not")
	check(map.floors.get_used_cells().size() > 1000 and map.floors.get_used_cells().size() < 40000, "a part of the floor is painted (%d cells of %d)" % [map.floors.get_used_cells().size(), map.floor_cell_count()])
	check(near.is_inside_tree() and not far.is_inside_tree(), "Decor near the view is in the tree and Decor far from it is not")

	var east_view : Rect2 = Rect2(far.position - Vector2(320, 180), Vector2(640, 360))
	streamer.focus = func() -> Rect2: return east_view
	for i in 60:
		await get_tree().process_frame
	check(map.is_chunk_painted(far_chunk) and not map.is_chunk_painted(near_chunk), "moving the view paints the new chunks and erases the old")
	check(far.is_inside_tree() and not near.is_inside_tree(), "and swaps the Decor")
	var before : int = map.floors.get_used_cells().size()
	map.paint_all()
	check(map.floors.get_used_cells().size() == map.floor_cell_count() and map.floors.get_used_cells().size() > before, "paint_all paints the whole floor (%d cells)" % map.floors.get_used_cells().size())
	map.clear_tiles()
	check(map.floors.get_used_cells().is_empty() and map.walls.get_used_cells().is_empty(), "clear_tiles empties the layers")
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
