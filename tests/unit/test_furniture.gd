extends Node

# Offline test of the furnishing (game/furniture/ and the Furnishing node of game/environment/facility_map.tscn). Run as a scene so the autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_furniture.tscn

const SMALL_MAP : String = "res://game/environment/facility_map.tscn"
const ITEM_DIR : String = "res://game/furniture/items/"
const PLAYER_RADIUS : float = 12.0
var CELL : float = 3.0 #the walkability grid, px (coarser on a big map)

var failures : int = 0
var map_path : String = SMALL_MAP #the map to test: the first argument after -- (the big one is res://game/environment/facility_map_wings.tscn)


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	# every item scene: a picture, and a footprint that matches it
	var count : int = 0
	for file : String in DirAccess.get_files_at(ITEM_DIR):
		if not file.ends_with(".tscn"):
			continue
		count += 1
		var piece : Furniture = (load(ITEM_DIR + file) as PackedScene).instantiate()
		add_child(piece)
		var art : Sprite2D = piece.get_node("Art")
		var size : Vector2 = art.texture.get_size() * Furniture.ART_SCALE
		var fits : bool = piece.footprint_size.x <= size.x + 0.01 and piece.footprint_size.y <= size.y + 0.01 and piece.footprint_size.x >= size.x - 2.0 * (Furniture.ART_SCALE * 16.0 + 1.0) - 0.01
		if piece.footprint == Furniture.Footprint.NONE:
			check(not piece.has_node("Footprint") and piece.collision_layer == 0 and piece.z_index == Furniture.FLAT_Z, "%s lies on the floor: no collision, under bodies" % file)
		else:
			check(fits and piece.has_node("Footprint") and piece.has_node("Occluder") and piece.collision_layer == FacilityTileSet.WORLD_LAYER, "%s: footprint inside its picture, on the wall layer, with a light occluder" % file)
		piece.queue_free()
	check(count >= 40, "there are furniture scenes to drag into the map (%d)" % count)

	# the furnished map
	if not OS.get_cmdline_user_args().is_empty():
		map_path = OS.get_cmdline_user_args()[0]
	var started : int = Time.get_ticks_msec()
	var map : FacilityMap = (load(map_path) as PackedScene).instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().physics_frame
	print("  info the map loaded and built in %d ms" % (Time.get_ticks_msec() - started))
	var pieces : Array[Furniture] = []
	for node : Node in map.find_children("*", "Furniture", true, false):
		pieces.append(node as Furniture)
	check(pieces.size() > 40, "the map is furnished (%d pieces)" % pieces.size())
	var solids : int = 0
	var problems : int = 0
	for piece : Furniture in pieces:
		var problem : String = piece.placement_problem(map)
		if problem != "":
			problems += 1
			print("       %s/%s: %s" % [piece.get_parent().name, piece.name, problem])
		if piece.is_solid():
			solids += 1
	check(problems == 0, "no piece sticks out of its room, blocks a door or a marker, or overlaps another (%d problems)" % problems)
	var in_rooms : int = 0
	var rooms_with : Dictionary = {}
	for piece : Furniture in pieces:
		if map.room_at(map.to_local(piece.global_position)) != "":
			in_rooms += 1
			rooms_with[map.room_at(map.to_local(piece.global_position))] = true
	check(in_rooms == pieces.size(), "every piece stands on a room's floor")
	for id : String in (map.rooms if map_path == SMALL_MAP else {}):
		if map.rooms[id]["kind"] != "outdoor" and not map.rooms[id]["exterior"] or id in ["stairwell", "loading_dock", "maintenance_bay", "cafeteria"]:
			check(rooms_with.has(id) or id == "ring", "room %s has furniture" % id)

	# physics: a solid piece stops a body and a shot where its picture is, and is not there where it is not
	var space : PhysicsDirectSpaceState2D = map.get_world_2d().direct_space_state
	var stopped : int = 0
	var tight : int = 0
	for piece : Furniture in pieces:
		if not piece.is_solid():
			continue
		var inside : PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
		inside.position = piece.global_position
		inside.collision_mask = FacilityTileSet.WORLD_LAYER
		if not space.intersect_point(inside).is_empty():
			stopped += 1
		var outside : PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new() #a point 1.5 px past the footprint's right edge (and, for a rectangle, below its bottom edge)
		outside.collision_mask = FacilityTileSet.WORLD_LAYER
		outside.position = piece.global_position + Vector2(piece.footprint_size.x / 2.0 + 1.5, piece.footprint_size.y / 2.0 + 1.5 if piece.footprint != Furniture.Footprint.CIRCLE else 0.0)
		var hits : Array[Dictionary] = space.intersect_point(outside)
		var own : bool = false
		for hit : Dictionary in hits:
			if hit["collider"] == piece:
				own = true
		if not own:
			tight += 1
	check(stopped == solids, "every solid piece is on the walls' physics layer (%d of %d)" % [stopped, solids])
	check(tight == solids, "no piece's collision reaches past its footprint (%d of %d)" % [tight, solids])

	# light: every solid piece has an occluder the size of its footprint
	var occluders : int = 0
	for piece : Furniture in pieces:
		if piece.is_solid():
			var occ : LightOccluder2D = piece.get_node_or_null("Occluder")
			if occ != null and occ.occluder != null and occ.occluder.polygon.size() >= 4:
				occluders += 1
	check(occluders == solids, "every solid piece throws a flashlight shadow (%d of %d occluders)" % [occluders, solids])
	var unlit : int = 0
	var wrong_layer : PackedStringArray = []
	for piece : Furniture in pieces:
		var art : Sprite2D = piece.get_node("Art")
		var tier : int = piece.tier()
		var tall_material : bool = art.material is ShaderMaterial and (art.material as ShaderMaterial).shader.resource_path.ends_with("furniture_top.gdshader")
		if art.material != null and not tall_material or tall_material != (tier == LightLayers.Tier.TALL) or art.use_parent_material:
			unlit += 1 #(only a TALL piece has a material: the one that takes less of a light on its top)
		var occ : LightOccluder2D = piece.get_node_or_null("Occluder")
		if art.light_mask != LightLayers.receiver_layer(tier) or (occ != null and occ.occluder_light_mask != LightLayers.caster_layer(tier)):
			wrong_layer.append(piece.name)
	check(unlit == 0, "every piece is drawn lit by the scene's lights (no unshaded material; only the tall ones take less light on top)")
	check(wrong_layer.is_empty(), "every piece's picture and occluder are on the light layer of its height %s" % str(wrong_layer))
	var tiers : Dictionary = {}
	for piece : Furniture in pieces:
		tiers[piece.tier()] = true
	check(tiers.size() == 4, "the map has furniture of every height (flat, low, mid, tall)")

	# heights: the flashlight is one beam for each height, each lights one layer of pictures and takes the shadows of what is taller
	var probe : PointLight2D = PointLight2D.new()
	probe.name = "Cone"
	add_child(probe)
	var cones : Array[PointLight2D] = LightLayers.add_height_cones(probe)
	check(cones.size() == 4, "the flashlight has a beam for each height (%d)" % cones.size())
	var lit_by : Dictionary = {}
	var shadow_ok : bool = true
	for tier : int in 4:
		var layer : int = LightLayers.receiver_layer(tier)
		for light : PointLight2D in cones:
			if light.range_item_cull_mask & layer != 0:
				lit_by[tier] = lit_by.get(tier, 0) + 1
		var shadows : int = cones[tier].shadow_item_cull_mask
		shadow_ok = shadow_ok and shadows & LightLayers.FLOOR != 0 and shadows & layer != 0 #walls always shade, and the beam has shadows on its own pictures at all
		for caster : int in range(1, 4):
			var shades : bool = shadows & LightLayers.caster_layer(caster) != 0
			shadow_ok = shadow_ok and shades == (caster > tier) #a shadow falls on a picture only from something taller
	check(lit_by.size() == 4 and lit_by.values().all(func(n : int) -> bool: return n == 1), "every height of picture is lit by exactly one beam (so lighting costs what one beam does)")
	check(shadow_ok, "a beam takes shadows from walls and from furniture taller than the pictures it lights, never from lower or equal furniture")
	probe.get_parent().remove_child(probe)
	probe.free()
	for cone_light : PointLight2D in cones:
		if is_instance_valid(cone_light):
			cone_light.free()
	var skin : Node = (load("res://game/player/skin/player_skin.tscn") as PackedScene).instantiate()
	add_child(skin)
	var flashlights : Array[Node] = skin.find_children("*", "Flashlight", true, false)
	check(flashlights.size() == 1 and (flashlights[0] as Flashlight).cones.size() == 4, "a player's flashlight builds its four beams")
	if flashlights.size() == 1:
		(flashlights[0] as Flashlight).set_on(true)
		var all_on : bool = true
		for beam : PointLight2D in (flashlights[0] as Flashlight).cones:
			all_on = all_on and beam.enabled
		check(all_on, "switching the flashlight on lights all four beams")
		(flashlights[0] as Flashlight).set_on(false)
		var any_on : bool = false
		for beam : PointLight2D in (flashlights[0] as Flashlight).cones:
			any_on = any_on or beam.enabled
		check(not any_on, "and off puts them all out")
	skin.queue_free()
	var occluder_layers_ok : bool = true
	for occ : Node in map.wall_body.get_children():
		if occ is LightOccluder2D and (occ as LightOccluder2D).occluder_light_mask & LightLayers.FLOOR == 0:
			occluder_layers_ok = false
	check(occluder_layers_ok, "walls shade every height of picture (their occluders are on the floor layer)")
	var shadowed_top : int = 0
	for piece : Furniture in pieces:
		var occ : LightOccluder2D = piece.get_node_or_null("Occluder")
		if occ != null and occ.occluder.cull_mode != OccluderPolygon2D.CULL_COUNTER_CLOCKWISE:
			shadowed_top += 1
	check(shadowed_top == 0, "every piece's occluder shades only behind it, so its own top is lit")

	# players are stood side by side round a spawn marker (SpawnSelectPhase.spread_px apart) and dropped on random floor in a deathmatch: never inside a piece
	var crowded : PackedStringArray = []
	for marker : SpawnRoomMarker in map.spawn_markers():
		if not marker is GuardSpawn: #(the intruders start outside the building, which is not furnished)
			continue
		for n in range(1, 5):
			for i in n:
				var spot : Vector2 = marker.global_position + Vector2((i - (n - 1) / 2.0) * 40.0, 0.0)
				if not map.is_clear(map.to_local(spot), 12.0):
					crowded.append("%s (%d players, number %d)" % [marker.name, n, i])
	check(crowded.is_empty(), "up to four players fit side by side at every spawn %s" % str(crowded))
	var stuck : int = 0
	for i in 400:
		if not map.is_clear(map.random_floor_point(), 12.0):
			stuck += 1
	check(stuck == 0, "a deathmatch respawn never lands inside furniture (%d of 400)" % stuck)

	# walking: from the first door every door, spawn, item location and console is still reachable round the furniture (a player is 24 px wide)
	_check_reachable(map, pieces)
	get_tree().quit(0 if failures == 0 else 1)


func _check_reachable(map : FacilityMap, pieces : Array[Furniture]) -> void:
	var bounds : Rect2 = map.map_bounds_px().grow(40.0)
	CELL = 3.0 if bounds.get_area() < 4000000.0 else 4.0
	var cols : int = int(ceilf(bounds.size.x / CELL))
	var rows : int = int(ceilf(bounds.size.y / CELL))
	var blocked : PackedByteArray = PackedByteArray()
	blocked.resize(cols * rows)
	for wall : Rect2i in map.wall_rects():
		_block_rect(blocked, bounds, cols, rows, Rect2(Vector2(wall.position * FacilityTileSet.TILE), Vector2(wall.size * FacilityTileSet.TILE)).grow(PLAYER_RADIUS))
	for cell : Vector2i in map.barrier_cells:
		_block_rect(blocked, bounds, cols, rows, Rect2(Vector2(cell * FacilityTileSet.TILE), Vector2.ONE * FacilityTileSet.TILE).grow(PLAYER_RADIUS))
	for piece : Furniture in pieces:
		if piece.is_solid():
			var polygon : PackedVector2Array = piece.footprint_polygon()
			var box : Rect2 = polygon_bounds(polygon).grow(PLAYER_RADIUS)
			var x0 : int = maxi(0, int(floorf((box.position.x - bounds.position.x) / CELL)))
			var x1 : int = mini(cols - 1, int(ceilf((box.end.x - bounds.position.x) / CELL)))
			var y0 : int = maxi(0, int(floorf((box.position.y - bounds.position.y) / CELL)))
			var y1 : int = mini(rows - 1, int(ceilf((box.end.y - bounds.position.y) / CELL)))
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var at : Vector2 = bounds.position + Vector2(x + 0.5, y + 0.5) * CELL
					if distance_to_polygon(at, polygon) < PLAYER_RADIUS:
						blocked[y * cols + x] = 1
	var start : Vector2 = map.doors[0].global_position
	var seen : PackedByteArray = PackedByteArray()
	seen.resize(cols * rows)
	var queue : Array[int] = [_index_of(start, bounds, cols)]
	seen[queue[0]] = 1
	var head : int = 0
	while head < queue.size():
		var i : int = queue[head]
		head += 1
		var x : int = i % cols
		var y : int = i / cols
		for step : Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx : int = x + step.x
			var ny : int = y + step.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var j : int = ny * cols + nx
			if seen[j] == 0 and blocked[j] == 0:
				seen[j] = 1
				queue.append(j)
	var unreachable : PackedStringArray = []
	for door : FacilityDoor in map.doors:
		if seen[_index_of(door.global_position, bounds, cols)] == 0:
			unreachable.append(door.name)
	for marker : Node in map.find_children("*", "Marker2D", true, false):
		var spot : Vector2 = (marker as Marker2D).global_position
		if map.vents.has(map.world_to_cell(map.to_local(spot))) or marker.get_parent() == map.vents_node or marker.get_parent().name == "Rooms":
			continue
		if seen[_index_of(spot, bounds, cols)] == 0:
			unreachable.append(marker.name)
	for panel : Node in map.find_children("*", "ControlPanel", true, false):
		var stand : Vector2 = (panel as Node2D).global_position + Vector2(0, 30)
		if seen[_index_of(stand, bounds, cols)] == 0:
			unreachable.append(panel.name + " (where a player stands)")
	check(unreachable.is_empty(), "every door, spawn, item location and console can be walked to round the furniture %s" % str(unreachable))


func _index_of(world : Vector2, bounds : Rect2, cols : int) -> int:
	return int((world.y - bounds.position.y) / CELL) * cols + int((world.x - bounds.position.x) / CELL)


func _block_rect(blocked : PackedByteArray, bounds : Rect2, cols : int, rows : int, rect : Rect2) -> void:
	var x0 : int = maxi(0, int(ceilf((rect.position.x - bounds.position.x) / CELL - 0.5))) #(the cells whose middle is inside the rectangle)
	var x1 : int = mini(cols - 1, int(floorf((rect.end.x - bounds.position.x) / CELL - 0.5)))
	var y0 : int = maxi(0, int(ceilf((rect.position.y - bounds.position.y) / CELL - 0.5)))
	var y1 : int = mini(rows - 1, int(floorf((rect.end.y - bounds.position.y) / CELL - 0.5)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			blocked[y * cols + x] = 1

func polygon_bounds(polygon : PackedVector2Array) -> Rect2:
	var rect : Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point : Vector2 in polygon:
		rect = rect.expand(point)
	return rect


func distance_to_polygon(point : Vector2, polygon : PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, polygon):
		return 0.0
	var best : float = INF
	for i in polygon.size():
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])))
	return best
