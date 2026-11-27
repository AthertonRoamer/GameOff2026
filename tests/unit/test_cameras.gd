extends Node

# Offline test of the rooms' cameras: switched from the door console like a light (FacilityControl, the lobby decides), 5 pts/s from the room's region,
# refused without power, switched off before lights when power runs short, sent in the lobby's snapshot, toggled by a right click on the console's map,
# and the rooms a feed shows are seen by PlayerSight.
# Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_cameras.tscn

const MAP_SCENE : PackedScene = preload("res://game/environment/facility_map.tscn")
const GENERATOR_SCENE : PackedScene = preload("res://game/power/generator.tscn")
const DOOR_SCREEN : PackedScene = preload("res://game/utility/door_map_screen.tscn")
const SETTLE : int = 100000 #a tick far ahead: every scheduled change is due

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	var map : FacilityMap = MAP_SCENE.instantiate()
	map.doors_start = FacilityDoor.State.OPEN
	add_child(map)
	await get_tree().process_frame

	var generator : Generator = GENERATOR_SCENE.instantiate() #a whole-map generator of our own: powers every region through the pool
	generator.name = "TestGenerator"
	generator.scope = Generator.Scope.WHOLE_MAP
	map.props_node.add_child(generator)
	generator.global_position = map.to_global(Vector2(-4000, -4000))
	var grid : PowerGrid = PowerGrid.new()
	grid.facility = map
	grid.settings = PowerGrid.DEFAULT_SETTINGS.duplicate()
	add_child(grid)
	var control : FacilityControl = FacilityControl.new()
	control.facility = map
	control.power = grid
	add_child(control)
	grid.control = control
	grid.build()
	for each : Generator in grid.generators:
		grid.set_generator(each, Generator.State.OFF)

	#one camera per lit room, all off
	check(control.camera_count() == map.light_rooms.size() and control.camera_count() > 0, "a camera switch for every lit room (%d)" % control.camera_count())
	var all_off : bool = true
	for index in control.camera_count():
		all_off = all_off and not control.is_camera_on(index)
	check(all_off, "every camera starts off")
	check(is_equal_approx(grid.camera_cost(), 5.0), "a camera costs 5 pts/s")

	#refused without power, accepted with it, paid for by the room's region
	var room : String = map.light_rooms[0]
	var camera : int = map.light_of_room(room)
	var region : String = control.light_region(camera)
	var refusals : Array = []
	control.camera_refused.connect(func(index : int, reason : String) -> void: refusals.append([index, reason]))
	control.request_camera(camera, true)
	check(refusals.size() == 1 and refusals[0][1] == "power" and not control.is_camera_pending(camera), "switching a camera on with no power is refused")
	grid.set_generator(generator, Generator.State.RUNNING)
	var free_before : float = grid.available(region)
	control.request_camera(camera, true)
	check(control.is_camera_pending(camera) and grid.has_load(PowerGrid.camera_key(camera)), "with power it is accepted, and its power is counted at once")
	check(is_equal_approx(grid.available(region), free_before - 5.0), "it takes 5 pts/s from its room's region")
	check(not control.is_light_on(camera) and not control.is_light_pending(camera), "the room's light is not touched")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.is_camera_on(camera) and not control.is_camera_pending(camera), "on its tick the camera comes on")
	control.request_camera(camera, false)
	check(not grid.has_load(PowerGrid.camera_key(camera)) and is_equal_approx(grid.available(region), free_before), "switching it off frees its power at once")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(not control.is_camera_on(camera), "and on its tick it goes off")

	#short of power: cameras go before lights (shed_order: turrets, cameras, lights, doors)
	grid.settings.shed_order = [PowerSettings.Category.TURRETS, PowerSettings.Category.CAMERAS, PowerSettings.Category.LIGHTS, PowerSettings.Category.DOORS] as Array[PowerSettings.Category]
	control.request_camera(camera, true)
	control.request_light(camera, true)
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.is_camera_on(camera) and control.is_light_on(camera), "a camera and a light both on")
	generator.output_override = grid.light_cost() + grid.camera_cost() - 0.5 #a little short
	grid.set_generator(generator, Generator.State.RUNNING)
	check(not grid.has_load(PowerGrid.camera_key(camera)) and grid.has_load(PowerGrid.light_key(camera)), "short of power, the camera goes before the light")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(not control.is_camera_on(camera) and control.is_light_on(camera), "the camera goes off and the light stays on")
	generator.output_override = -1.0
	grid.set_generator(generator, Generator.State.RUNNING)

	#the lobby's snapshot carries the cameras
	var door_states : PackedByteArray = PackedByteArray()
	for door : FacilityDoor in map.doors:
		door_states.append(door.state)
	var cameras : PackedByteArray = control.cameras_on.duplicate()
	cameras[camera] = 1
	control._receive_snapshot(door_states, control.lights_on.duplicate(), cameras)
	check(control.is_camera_on(camera) and grid.has_load(PowerGrid.camera_key(camera)), "a snapshot from the lobby switches the cameras it has on, and their power is counted")
	control._receive_snapshot(door_states, control.lights_on.duplicate()) #(an older lobby, with no cameras in its snapshot)
	check(control.is_camera_on(camera), "a snapshot without cameras leaves them as they are")
	control.set_camera_now(camera, false)
	check(not grid.has_load(PowerGrid.camera_key(camera)), "a camera set off directly frees its power")

	#the door console: a right click on a room switches its camera, a left click its light
	var screen : DoorMapScreen = DOOR_SCREEN.instantiate()
	screen.facility = map
	screen.control = control
	add_child(screen)
	screen.size = Vector2(1280, 720)
	screen.open()
	await get_tree().process_frame
	var view : FacilityMapView = screen.map
	var spot : Vector2 = _open_floor(map, room)
	view.center_on(spot)
	var at : Vector2 = view.world_to_screen(spot)
	check(screen.cameras_layer.camera_at(spot) == camera, "the cameras layer finds the room's camera under the mouse")
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, true, at))
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, false, at))
	check(control.is_camera_pending(camera) and not control.is_light_pending(camera), "a right click on a room asks for its camera, not its light")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.is_camera_on(camera), "and the camera comes on")
	var light_before : bool = control.is_light_on(camera)
	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, true, at))
	view._gui_input(_mouse(MOUSE_BUTTON_LEFT, false, at))
	check(control.is_light_pending(camera) and not control.is_camera_pending(camera), "a left click still switches the light")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(control.is_light_on(camera) != light_before and control.is_camera_on(camera), "the light switched and the camera stayed on")
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, true, at))
	view._gui_input(_mouse(MOUSE_BUTTON_RIGHT, false, at + Vector2(40, 0)))
	check(not control.is_camera_pending(camera), "a right press that moves away is not a click")
	check(screen.toggle_camera(camera) and control.is_camera_pending(camera), "toggle_camera asks for it the way a right click does")
	control._apply_due(NetworkTime.tick + SETTLE)
	check(not control.is_camera_on(camera), "and switches it back off")
	check(screen.cameras_layer.feed_indices().is_empty(), "with no display (headless) no feed is made")
	screen.close()

	#PlayerSight: everything in a watched room is seen
	var sight : PlayerSight = PlayerSight.new()
	add_child(sight)
	check(sight.is_in_group(PlayerSight.GROUP), "PlayerSight can be found by the camera feeds")
	var watched_rect : Rect2 = Rect2(Vector2(100, 100), Vector2(200, 100))
	sight.watched = [watched_rect]
	check(sight.is_watched(Vector2(150, 150)) and not sight.is_watched(Vector2(50, 50)), "is_watched tells a point in a watched room from one outside")
	sight._view = PackedVector2Array([Vector2(-10, -10), Vector2(-5, -10), Vector2(-5, -5)]) #(a tiny view far from the room)
	sight._apex = Vector2(-8, -8)
	check(sight.visibility(Vector2(150, 150)) == 1.0, "a point in a watched room is fully seen, wherever the player looks")
	check(sight.visibility(Vector2(500, 500)) == 0.0, "a point outside it is still seen only as the view allows")
	sight.watched = []
	check(sight.visibility(Vector2(150, 150)) == 0.0, "once the feed stops it is not")
	sight.queue_free()
	screen.queue_free()
	map.queue_free()
	await get_tree().process_frame

	print("RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _mouse(index : MouseButton, pressed : bool, at : Vector2) -> InputEventMouseButton:
	var event : InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = at
	return event


##A point on a room's floor away from its doors, so a click there lands on the room and not a door.
func _open_floor(map : FacilityMap, room : String) -> Vector2:
	var best : Vector2 = map.room_center_px(room)
	var best_gap : float = -1.0
	for rect : Rect2 in map.room_rects_px(room):
		for fx in [0.25, 0.5, 0.75]:
			for fy in [0.25, 0.5, 0.75]:
				var point : Vector2 = rect.position + rect.size * Vector2(fx, fy)
				var gap : float = INF
				for door : FacilityDoor in map.doors:
					gap = minf(gap, door.position.distance_to(point))
				if gap > best_gap and map.room_at(point) == room:
					best_gap = gap
					best = point
	return best
