extends Node

# Offline test of the reusable map view (FacilityMapView, MapLayer and the layers) and of the door console screen built on it. Run as a scene so the
# project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_map_view.tscn

const MAP_SCENE : PackedScene = preload("res://game/environment/facility_map.tscn")
const DOOR_SCREEN : PackedScene = preload("res://game/utility/door_map_screen.tscn")

var failures : int = 0


class ClickCounter extends MapLayer:
	var clicks : Array = [] #world positions it was clicked at

	func map_click(world : Vector2) -> bool:
		clicks.append(world)
		return true


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func near(a : Vector2, b : Vector2, tolerance : float = 0.01) -> bool:
	return a.distance_to(b) <= tolerance


func mouse_button(index : MouseButton, pressed : bool, at : Vector2) -> InputEventMouseButton:
	var event : InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = at
	return event


func mouse_motion(at : Vector2, relative : Vector2) -> InputEventMouseMotion:
	var event : InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	return event


func _ready() -> void:
	var facility : FacilityMap = MAP_SCENE.instantiate()
	add_child(facility)
	await get_tree().process_frame

	var view : FacilityMapView = FacilityMapView.new()
	var rooms : RoomsLayer = RoomsLayer.new()
	var doors : DoorsLayer = DoorsLayer.new()
	var counter : ClickCounter = ClickCounter.new()
	view.add_child(rooms)
	view.add_child(doors)
	view.add_child(counter)
	view.size = Vector2(800, 500)
	add_child(view)
	view.facility = facility
	await get_tree().process_frame

	check(Array(view.layers()) == [rooms, doors, counter] and rooms.view == view, "its layers are the MapLayer children, in drawing order, and know their view")
	var bounds : Rect2 = view.map_bounds()
	check(bounds.has_point(facility.room_center_px(facility.start_room())) and bounds.size.x > 1000.0, "the map bounds take in the whole facility")
	var world : Vector2 = Vector2(700, 500)
	check(near(view.screen_to_world(view.world_to_screen(world)), world), "screen and world positions convert both ways")
	check(rooms.scale.is_equal_approx(Vector2.ONE * view.zoom) and doors.position.is_equal_approx(rooms.position), "every layer gets the same scroll and zoom")

	#zoom limits
	view.set_zoom(1000.0)
	check(is_equal_approx(view.zoom, view.max_zoom), "it zooms in no further than max_zoom")
	view.set_zoom(0.0001)
	check(is_equal_approx(view.zoom, view.min_zoom()), "it zooms out no further than the whole map")
	view.fit_all()
	var top_left : Vector2 = view.world_to_screen(bounds.position)
	var bottom_right : Vector2 = view.world_to_screen(bounds.end)
	check(top_left.x >= -0.5 and top_left.y >= -0.5 and bottom_right.x <= view.size.x + 0.5 and bottom_right.y <= view.size.y + 0.5, "zoomed all the way out, the whole map fits")
	view.reset_view()
	check(is_equal_approx(view.zoom, clampf(view.default_zoom, view.min_zoom(), view.max_zoom)), "it opens at the default zoom (readable however big the map is)")

	#zooming with the wheel keeps the point under the mouse where it is
	view.set_zoom(1.0)
	view.center_on(bounds.get_center())
	var mouse : Vector2 = Vector2(300, 200)
	var under_mouse : Vector2 = view.screen_to_world(mouse)
	var before : float = view.zoom
	view._gui_input(mouse_button(MOUSE_BUTTON_WHEEL_UP, true, mouse))
	check(view.zoom > before and near(view.screen_to_world(mouse), under_mouse, 0.5), "the wheel zooms in around the mouse")
	before = view.zoom
	view._gui_input(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, mouse))
	check(view.zoom < before and near(view.screen_to_world(mouse), under_mouse, 0.5), "and out again around the mouse")
	var pinch : InputEventMagnifyGesture = InputEventMagnifyGesture.new()
	pinch.position = mouse
	pinch.factor = 1.5
	before = view.zoom
	view._gui_input(pinch)
	check(is_equal_approx(view.zoom, before * 1.5), "a trackpad pinch zooms too")

	#the + and - buttons zoom around the middle
	view.set_zoom(1.0)
	view.center_on(bounds.get_center())
	var buttons : Array = view.find_children("*", "Button", true, false)
	check(buttons.size() == 2, "it has a zoom out and a zoom in button")
	var middle : Vector2 = view.center()
	(buttons[1] as Button).pressed.emit()
	check(view.zoom > 1.0 and near(view.center(), middle, 0.5), "+ zooms in around the middle")
	(buttons[0] as Button).pressed.emit()
	check(is_equal_approx(view.zoom, 1.0), "- zooms back out")

	#scrolling: drag, middle-drag, trackpad pan
	var start : Vector2 = view.center()
	view._gui_input(mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(400, 250)))
	view._gui_input(mouse_motion(Vector2(300, 250), Vector2(-100, 0)))
	view._gui_input(mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(300, 250)))
	check(near(view.center(), start + Vector2(100.0 / view.zoom, 0.0), 0.5), "dragging scrolls the map with the mouse")
	check(counter.clicks.is_empty(), "a drag is not a click")
	start = view.center()
	view._gui_input(mouse_button(MOUSE_BUTTON_MIDDLE, true, Vector2(400, 250)))
	view._gui_input(mouse_motion(Vector2(402, 250), Vector2(2, 0)))
	view._gui_input(mouse_button(MOUSE_BUTTON_MIDDLE, false, Vector2(402, 250)))
	check(near(view.center(), start - Vector2(2.0 / view.zoom, 0.0), 0.5) and counter.clicks.is_empty(), "the middle button always drags, even a little")
	start = view.center()
	var pan : InputEventPanGesture = InputEventPanGesture.new()
	pan.delta = Vector2(0, 1)
	view._gui_input(pan)
	check(near(view.center(), start + Vector2(0.0, FacilityMapView.PAN_GESTURE_SPEED / view.zoom), 0.5), "a trackpad pan scrolls")
	for i in 50: #far past the edge
		view.scroll_by(Vector2(1000, 0))
	check(view.world_to_screen(bounds.end).x >= view.size.x - view.scroll_margin_px - 0.5, "it can't be scrolled off the map")

	#a click goes to the top layer that takes it
	var click_at : Vector2 = Vector2(420, 260)
	view._gui_input(mouse_button(MOUSE_BUTTON_LEFT, true, click_at))
	view._gui_input(mouse_button(MOUSE_BUTTON_LEFT, false, click_at))
	check(counter.clicks.size() == 1 and near(counter.clicks[0], view.screen_to_world(click_at)), "a click reaches the layers, at the world position under the mouse")
	counter.visible = false
	var door : FacilityDoor = facility.doors[0]
	var state_before : FacilityDoor.State = door.state
	view.click(view.world_to_screen(door.position))
	check(door.state != state_before, "a click on a door flips it (the doors layer, with no control in a bare test)")
	doors.interactive = false
	view.click(view.world_to_screen(door.position))
	check(door.state != state_before, "a doors layer that isn't interactive ignores clicks")

	#the door console screen, built on the view: the API the harness and the playground use still works
	var screen : DoorMapScreen = DOOR_SCREEN.instantiate()
	screen.facility = facility
	add_child(screen)
	screen.size = Vector2(1280, 720)
	screen.open()
	await get_tree().process_frame
	check(screen.map.facility == facility and screen.map.size.x > 600.0, "the door screen has a map of the facility")
	var all_found : bool = true
	for each : FacilityDoor in facility.doors:
		if screen.door_at(screen.screen_position_of(each)) != each:
			all_found = false
	check(all_found, "every door is found where the screen says it is")
	var second : FacilityDoor = facility.doors[1]
	var second_before : FacilityDoor.State = second.state
	check(screen.toggle_door(second) and second.state != second_before, "toggle_door flips a door")
	second.state = FacilityDoor.State.LOCKED
	check(not screen.toggle_door(second) and second.state == FacilityDoor.State.LOCKED, "a locked door can't be changed")
	screen.close()
	check(not screen.visible, "close() hides it")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
