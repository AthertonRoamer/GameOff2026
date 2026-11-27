extends Node

# Offline test of the rooms' ceiling lights (game/lights): every room but an outdoor one has a light sized from its rectangles, the light fills the room and stops at
# walls and shut doors, spills out through an open doorway, never shows behind a solid wall, and follows the room when it is resized.
# Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_room_lights.tscn

const MAP_SCENE : PackedScene = preload("res://game/environment/facility_map.tscn")
const TILE : float = FacilityTileSet.TILE

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	var map : FacilityMap = MAP_SCENE.instantiate()
	map.doors_start = FacilityDoor.State.CLOSED
	add_child(map)
	await get_tree().process_frame

	#which rooms have a light, and its sources match the rooms' rectangles
	var sources_expected : int = 0
	for id : String in map.rooms:
		var outdoor : bool = map.rooms[id]["kind"] == "outdoor"
		check((map.light_of_room(id) < 0) == outdoor, "%s %s a light" % [id, "has no" if outdoor else "has"])
		if not outdoor:
			sources_expected += (map.rooms[id]["rects"] as Array).size()
	check(map.light_sources.size() == sources_expected, "one light source per rectangle of a lit room (%d)" % map.light_sources.size())
	for source in map.light_sources.size():
		var entry : Dictionary = map.light_sources[source]
		check((map.rooms[entry["room"]]["rects"] as Array).has(entry["rect"]) and map.light_rooms[entry["light"]] == entry["room"], "source %d is a rectangle of %s" % [source, entry["room"]])

	var control : FacilityControl = FacilityControl.new()
	control.facility = map
	add_child(control)
	var shapes : RoomLightShapes = RoomLightShapes.new()
	shapes.facility = map
	shapes.control = control
	add_child(shapes)
	await _physics(3)

	var room : String = "cafeteria"
	var light : int = map.light_of_room(room)
	var source : int = _source_of(map, room)
	var rect : Rect2 = map.light_source_rect_px(source)
	var centre : Vector2 = map.to_global(rect.get_center())
	check(light >= 0 and source >= 0, "the cafeteria has a light and a source")
	check(shapes.light_at(centre) == 0.0, "a light that is off lights nothing")
	var lamp : PointLight2D = shapes.get_node_or_null("Lamp%d" % source)
	check(lamp != null and not lamp.enabled and lamp.global_position.distance_to(centre) < FacilityTileSet.TILE, "its lamp is a light over the middle of the room, off")
	check(lamp != null and lamp.shadow_enabled and lamp.shadow_item_cull_mask & (LightLayers.CAST_LOW | LightLayers.CAST_MID | LightLayers.CAST_TALL) == 0 and lamp.shadow_item_cull_mask & RoomLightShapes.WALL_SHADOWS and lamp.range_item_cull_mask == LightLayers.ALL_PICTURES, "walls shadow the lamp, furniture does not, and it lights furniture of every height")
	var lamp_size : Vector2 = Vector2(lamp.texture.get_size()) * lamp.texture_scale if lamp != null else Vector2.ZERO
	check(lamp_size.distance_to(rect.size + Vector2.ONE * shapes.spill_px() * 2.0) < RoomLightShapes.TEXTURE_STEP * 2.0, "the lamp's light is the room's size and its spill (%s)" % lamp_size)
	control.set_light_now(light, true)
	check(is_equal_approx(shapes.light_at(centre), 1.0), "switched on, it lights the middle of its room fully")
	check(lamp != null and lamp.enabled, "and its lamp comes on")

	#every door shut: the light stays in the room
	var inside : bool = true
	for polygon : PackedVector2Array in shapes.polygons(source):
		for point : Vector2 in polygon:
			inside = inside and rect.grow(2.0).has_point(map.to_local(point))
	check(inside, "with every door shut, the light stays inside the room")
	var corner : Vector2 = map.to_global(rect.end - Vector2.ONE * 4.0)
	check(shapes.light_at(corner) > 0.5, "it reaches the room's corners")

	#a door opened: the light spills out through it, and only through it
	var door : FacilityDoor = map.doors_of_room(room)[0]
	var out_dir : Vector2 = Vector2(0.0, signf(door.global_position.y - centre.y)) if door.horizontal else Vector2(signf(door.global_position.x - centre.x), 0.0)
	var past_door : Vector2 = door.global_position + out_dir * (TILE * 0.5 + 22.0)
	check(shapes.light_at(past_door) == 0.0, "past a shut door it is dark")
	door.state = FacilityDoor.State.OPEN
	await _physics(3)
	check(shapes.light_at(past_door) > 0.0, "the door opened, the light spills out through it (%.2f)" % shapes.light_at(past_door))
	var reaches_out : bool = false
	for polygon : PackedVector2Array in shapes.polygons(source):
		for point : Vector2 in polygon:
			reaches_out = reaches_out or not rect.grow(TILE * 2.0).has_point(map.to_local(point))
	check(reaches_out, "its shape reaches out past the room's wall")
	var far_corner : Vector2 = _far_corner(rect, map.to_local(door.global_position))
	var behind_wall : Vector2 = map.to_global(far_corner + (far_corner - rect.get_center()).normalized() * (TILE * 3.0))
	check(shapes.light_at(behind_wall) == 0.0, "behind a solid wall it is still dark")
	#furniture: no shadow in a ceiling light, a shadow in a flashlight beam
	var generator : Generator = preload("res://game/power/generator.tscn").instantiate()
	map.props_node.add_child(generator)
	generator.global_position = past_door + out_dir * 30.0
	await _physics(3)
	shapes.rebuild() #(the shapes are worked out again, with the generator standing in the spill)
	await _physics(3)
	var behind_generator : Vector2 = past_door + out_dir * 70.0
	var occluder : LightOccluder2D = generator.get_node_or_null("Occluder")
	check(generator.collision_layer & FacilityTileSet.PROP_LAYER and occluder != null and occluder.occluder_light_mask == LightLayers.caster_layer(LightLayers.tier_of(generator.height)) and occluder.occluder_light_mask != 0, "a generator is furniture, with a light occluder on the cast layer of its height")
	var floor_shadows : int = LightLayers.shadow_layers(LightLayers.Tier.FLAT)
	check(floor_shadows & occluder.occluder_light_mask and floor_shadows & RoomLightShapes.WALL_SHADOWS, "the flashlight's floor beam is shadowed by walls and the generator")
	check(shapes.light_at(behind_generator) > 0.0, "a generator in the doorway's spill casts no shadow in the room light (%.2f)" % shapes.light_at(behind_generator))
	var space : PhysicsDirectSpaceState2D = shapes.get_world_2d().direct_space_state
	var beam_hit : Dictionary = space.intersect_ray(PhysicsRayQueryParameters2D.create(past_door, behind_generator, SightFan.BEAMS))
	check(not beam_hit.is_empty() and beam_hit["collider"] == generator, "but it stops a flashlight beam")
	generator.free()
	door.state = FacilityDoor.State.CLOSED
	await _physics(3)
	check(shapes.light_at(past_door) == 0.0, "the door shut again, the spill is gone")

	#the light follows the room when it is resized
	var rect_node : FacilityRoomRect = (map.rooms_node.get_node(room) as FacilityRoom).rects()[0]
	var old_size : Vector2 = rect_node.size
	rect_node.size = old_size - Vector2(TILE * 2.0, 0.0)
	map.build()
	var resized : Rect2 = map.light_source_rect_px(_source_of(map, room))
	check(is_equal_approx(resized.size.x, rect.size.x - TILE * 2.0), "resized in the editor, the light's rectangle follows (%s)" % resized)
	await get_tree().process_frame #(the old lamps are freed at the end of the frame)
	var new_lamp : PointLight2D = shapes.get_node_or_null("Lamp%d" % _source_of(map, room))
	var new_size : Vector2 = Vector2(new_lamp.texture.get_size()) * new_lamp.texture_scale if new_lamp != null else Vector2.ZERO
	check(new_lamp != null and absf(new_size.x - (resized.size.x + shapes.spill_px() * 2.0)) < RoomLightShapes.TEXTURE_STEP * 2.0, "and so does its lamp (%s)" % new_size)
	rect_node.size = old_size
	map.build()

	print("RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _physics(frames : int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _source_of(map : FacilityMap, room : String) -> int:
	for source in map.light_sources.size():
		if map.light_sources[source]["room"] == room:
			return source
	return -1


##The corner of a rectangle furthest from a point.
func _far_corner(rect : Rect2, from : Vector2) -> Vector2:
	var best : Vector2 = rect.position
	for corner : Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		if corner.distance_to(from) > best.distance_to(from):
			best = corner
	return best
