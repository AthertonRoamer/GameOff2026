class_name CamerasLayer
extends MapLayer

##The rooms' cameras, on the door console's map. Right-click a room to ask `control` to switch its camera (the lobby decides and checks the power, then every peer
##switches it on the same tick, like a light). A camera that is on shows its room live, right on the map: a SubViewport that shares the game's world, with a
##Camera2D framing the room, drawn into the room's rectangles. Dark rooms look dark on camera; switch the light on to see more.
##
##A feed shows the world as it really is, so while feeds are up the rooms they show are handed to PlayerSight.watched (everything in them is seen, the way a dead
##player sees) and to the map streamer (their floor and walls stay loaded however far the console is). Feeds run only while the layer is on screen, only for
##rooms in the map's view, at most MAX_FEEDS at once (the nearest the middle), and never without a display (a dedicated server, the tests).

signal camera_toggled(index : int) #a right click asked for this camera to switch

const ON_COLOUR : Color = Palette.OK
const MAX_FEEDS : int = 6
const MAX_FEED_PX : float = 512.0 #a feed's longest side, in pixels

@export var interactive : bool = true

var control : FacilityControl
var _hover : int = -1
var _feeds : Dictionary = {} #camera index -> {"viewport": SubViewport, "camera": Camera2D, "bounds": Rect2 (map space), "scale": float}


##Asks for a camera to switch, the way a right click does. Returns false for no camera, no control, or one already switching.
func toggle_camera(index : int) -> bool:
	if control == null or index < 0 or index >= control.camera_count() or control.is_camera_pending(index):
		return false
	control.request_camera(index, not control.is_camera_on(index))
	camera_toggled.emit(index)
	queue_redraw()
	return true


##The camera of the room at a world position, or -1 (a room's camera has its light's index).
func camera_at(world : Vector2) -> int:
	var map : FacilityMap = facility()
	return map.light_of_room(map.room_at(world)) if map != null else -1


func map_hover(world : Vector2) -> void:
	var now : int = camera_at(world) if interactive else -1
	if now != _hover:
		_hover = now
		queue_redraw()


func map_right_click(world : Vector2) -> bool:
	if not interactive:
		return false
	var index : int = camera_at(world)
	if index < 0:
		return false
	toggle_camera(index)
	return true


##The cameras whose feeds are running now.
func feed_indices() -> Array:
	return _feeds.keys()


##Stops every feed and lets the rooms go (the console closed).
func stop_feeds() -> void:
	for index : int in _feeds.keys():
		_free_feed(index)
	_report_watched()


func _exit_tree() -> void:
	stop_feeds()


func _process(_delta : float) -> void:
	if not is_visible_in_tree():
		if not _feeds.is_empty():
			stop_feeds()
		return
	_sync_feeds()
	queue_redraw() #(feeds move, and a switching camera blinks)


## Which cameras should have a feed now: on, in a room in the map's view, the nearest the middle first.
func _wanted_feeds() -> Array[int]:
	var wanted : Array[int] = []
	var map : FacilityMap = facility()
	if map == null or control == null or view == null or DisplayServer.get_name() == "headless":
		return wanted
	var shown : Rect2 = Rect2(view.screen_to_world(Vector2.ZERO), view.size / maxf(view.zoom, 0.0001))
	var middle : Vector2 = view.center()
	var distance : Dictionary = {}
	for index in mini(control.camera_count(), map.light_rooms.size()):
		if not control.is_camera_on(index):
			continue
		var bounds : Rect2 = _bounds(map.light_rooms[index])
		if bounds.size == Vector2.ZERO or not bounds.intersects(shown):
			continue
		wanted.append(index)
		distance[index] = bounds.get_center().distance_squared_to(middle)
	wanted.sort_custom(func(a : int, b : int) -> bool: return distance[a] < distance[b])
	return wanted.slice(0, MAX_FEEDS)


func _sync_feeds() -> void:
	var wanted : Array[int] = _wanted_feeds()
	var changed : bool = false
	for index : int in _feeds.keys():
		if not wanted.has(index):
			_free_feed(index)
			changed = true
	for index : int in wanted:
		if not _feeds.has(index):
			_add_feed(index)
			changed = true
		_fit_feed(index)
	if changed:
		_report_watched()


func _add_feed(index : int) -> void:
	var viewport : SubViewport = SubViewport.new()
	viewport.name = "Feed%d" % index
	viewport.disable_3d = true
	viewport.world_2d = get_tree().root.world_2d #the game's own world: the feed is another view of it
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera : Camera2D = Camera2D.new()
	viewport.add_child(camera)
	add_child(viewport)
	camera.enabled = true
	camera.make_current()
	_feeds[index] = {"viewport": viewport, "camera": camera, "bounds": Rect2(), "scale": 1.0}


## Frames the room: the feed's pixels match the map's zoom (no more than MAX_FEED_PX on its longest side), and the camera sees exactly the room's bounds.
func _fit_feed(index : int) -> void:
	var feed : Dictionary = _feeds[index]
	var map : FacilityMap = facility()
	var bounds : Rect2 = _bounds(map.light_rooms[index])
	var scale_ : float = minf(view.zoom if view != null else 1.0, MAX_FEED_PX / maxf(bounds.size.x, bounds.size.y))
	var pixels : Vector2i = Vector2i(maxi(1, ceili(bounds.size.x * scale_)), maxi(1, ceili(bounds.size.y * scale_)))
	var viewport : SubViewport = feed["viewport"]
	if viewport.size != pixels:
		viewport.size = pixels
	var camera : Camera2D = feed["camera"]
	camera.global_position = map.to_global(bounds.get_center())
	camera.zoom = Vector2.ONE * scale_ / maxf(map.global_scale.x, 0.0001)
	feed["bounds"] = bounds
	feed["scale"] = scale_


func _free_feed(index : int) -> void:
	var feed : Dictionary = _feeds[index]
	_feeds.erase(index)
	var viewport : SubViewport = feed["viewport"]
	if is_instance_valid(viewport):
		viewport.queue_free()


## Tells PlayerSight and the map streamer which rooms the feeds show (in world space).
func _report_watched() -> void:
	var rects : Array[Rect2] = []
	var map : FacilityMap = facility()
	if map != null:
		for index : int in _feeds:
			for rect : Rect2 in room_rects(map.light_rooms[index]):
				rects.append(map.get_global_transform() * rect)
	var sight : Node = get_tree().get_first_node_in_group(PlayerSight.GROUP) if is_inside_tree() else null
	if sight is PlayerSight:
		(sight as PlayerSight).watched = rects
	if map != null and map.streamer != null:
		map.streamer.watched = rects


## The bounding box of a room's rectangles (map space).
func _bounds(room_id : String) -> Rect2:
	var rects : Array[Rect2] = room_rects(room_id)
	if rects.is_empty():
		return Rect2()
	var bounds : Rect2 = rects[0]
	for rect : Rect2 in rects:
		bounds = bounds.merge(rect)
	return bounds


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null or control == null:
		return
	for index : int in _feeds: #the live pictures, each clipped to its room's own rectangles
		var feed : Dictionary = _feeds[index]
		var texture : Texture2D = (feed["viewport"] as SubViewport).get_texture()
		var bounds : Rect2 = feed["bounds"]
		var scale_ : float = feed["scale"]
		for rect : Rect2 in room_rects(map.light_rooms[index]):
			draw_texture_rect_region(texture, rect, Rect2((rect.position - bounds.position) * scale_, rect.size * scale_))
	for index in mini(control.camera_count(), map.light_rooms.size()):
		var on : bool = control.is_camera_on(index)
		var pending : bool = control.is_camera_pending(index)
		var rects : Array[Rect2] = room_rects(map.light_rooms[index])
		if rects.is_empty():
			continue
		var bounds : Rect2 = _bounds(map.light_rooms[index])
		if on or pending:
			var alpha : float = 0.9 if on and not pending else 0.45 + 0.45 * sin(Time.get_ticks_msec() / 60.0) #(switching: blinks while the change is on its way)
			for rect : Rect2 in rects:
				draw_rect(rect, Color(ON_COLOUR, alpha * 0.6), false, px(1.5))
			var tag : Vector2 = bounds.position + Vector2(px(6.0), px(6.0)) #a recording light and CAM in the room's corner
			draw_circle(tag + Vector2(px(4.0), px(4.0)), px(3.5), Color(Palette.ALARM, alpha))
			draw_label(tag + Vector2(px(12.0), px(4.0)), "CAM", 10, Color(ON_COLOUR, alpha), 40.0, HORIZONTAL_ALIGNMENT_LEFT)
		if index == _hover:
			var no_power : bool = not on and control.power != null and not control.power.can_afford(control.light_region(index), control.power.camera_cost())
			if no_power: #switching it on would be refused: say so before the click
				draw_label(bounds.get_center() + Vector2(0.0, px(30.0)), "NO POWER FOR A CAMERA", 11, Palette.ALARM, 160.0)


func icon_label(world : Vector2) -> String:
	var map : FacilityMap = facility()
	if map == null or control == null:
		return ""
	for index in mini(control.camera_count(), map.light_rooms.size()):
		var on : bool = control.is_camera_on(index)
		if not on and not control.is_camera_pending(index):
			continue
		var bounds : Rect2 = _bounds(map.light_rooms[index])
		var tag : Rect2 = Rect2(bounds.position + Vector2(px(2.0), px(2.0)), Vector2(px(44.0), px(16.0))) #the recording light and CAM in the room's corner
		if tag.has_point(world):
			return "Camera: %s" % ("on" if on else "switching")
	return ""
