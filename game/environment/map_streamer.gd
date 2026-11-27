@tool
class_name MapStreamer
extends Node

##Loads and unloads parts of the facility map as the view moves, so a map of any size costs only what is in front of the player. Made by the FacilityMap (a child
##of it called Streamer, not saved in the scene) and tuned with the map's Streaming settings.
##
##Tiles: the map is cut into chunks of 16 x 16 cells (4 m). The chunks within view_margin_cells of the view (the camera's, in the game; the 2D view's, in the editor) are
##painted, nearest first, a few milliseconds' worth each frame so moving never hitches; a chunk is erased once the view is unload_extra_cells further away than that.
##The first time, everything wanted is painted at once, so the game does not open on bare ground.
##Decor: if the map has a Decor node (furniture and clutter: sprites, lights, no collision), its children are taken out of the tree and put back as the view gets
##near, a decor_margin_cells margin round the view. Put anything that matters to the game (collision, consoles, things that block a shot) under Props instead,
##because the lobby needs those near every player, not just near this peer's camera.
##A dedicated server draws nothing, so it paints nothing.

var map : FacilityMap
var focus : Callable = Callable() ## optional () -> Rect2: the world rectangle to keep loaded, instead of the camera's view
var watched : Array[Rect2] = [] ## world rectangles kept loaded as well as the view: the rooms a camera feed shows (CamerasLayer)

const WATCHED_MARGIN_CELLS : int = 2 #round a watched room: its walls
var work_in_headless : bool = false ## tests: stream even without a display

var _settled : bool = false #the first paint has been done
var _tick : float = 0.0
var _wanted : Array[Vector2i] = [] #chunks to paint, nearest first
var _keep : Array[Rect2i] = [] #chunk ranges (as chunk coordinates) that stay painted: round the view, and round each watched room
var _decor : Dictionary = {} #chunk -> Array of the Decor children in it
var _decor_in : Dictionary = {} #chunk -> true while its children are in the tree
var _decor_node : Node2D
var _decor_ready : bool = false


##The map was rebuilt, nothing is painted: start over.
func refresh() -> void:
	_settled = false
	_wanted.clear()
	_tick = 0.0


func _process(delta : float) -> void:
	if map == null or map.floors == null or (DisplayServer.get_name() == "headless" and not work_in_headless):
		return
	if not _decor_ready:
		_setup_decor()
	if not map.stream_tiles:
		if not _settled:
			map.paint_all()
			_settled = true
		return
	_tick -= delta
	if _tick <= 0.0 or not _settled:
		_tick = 0.1
		if not _update() and not _settled:
			return #(no camera yet: nothing to load around)
	_work(not _settled)
	if _wanted.is_empty():
		_settled = true


func _exit_tree() -> void:
	for list : Array in _decor.values(): #Decor that is out of the tree is nobody's child any more: it has to be freed by hand
		for node : Node in list:
			if is_instance_valid(node) and not node.is_inside_tree():
				node.free()


## What is in view: sets which chunks to paint and which to keep, and which Decor is in the tree.
func _update() -> bool:
	var view : Rect2i = _view_cells()
	if view.size == Vector2i.ZERO:
		return false
	var margin : int = map.editor_margin_cells if Engine.is_editor_hint() else map.view_margin_cells
	var wants : Array[Rect2i] = [_chunk_range(view.grow(margin))]
	_keep = [_chunk_range(view.grow(margin + map.unload_extra_cells))]
	var decor : Array[Rect2i] = [_chunk_range(view.grow(map.decor_margin_cells))]
	for rect : Rect2 in watched: #(a room on a camera feed: just the room and its walls, painted like the view)
		var cells : Rect2i = _world_to_cells(rect).grow(WATCHED_MARGIN_CELLS)
		wants.append(_chunk_range(cells))
		_keep.append(_chunk_range(cells))
		decor.append(_chunk_range(cells))
	var centre : Vector2 = Vector2(view.get_center()) / float(1 << FacilityMap.CHUNK_SHIFT)
	_wanted.clear()
	var seen : Dictionary = {}
	for want : Rect2i in wants:
		for cy in range(want.position.y, want.end.y):
			for cx in range(want.position.x, want.end.x):
				var chunk : Vector2i = Vector2i(cx, cy)
				if not seen.has(chunk) and not map.is_chunk_painted(chunk) and map.chunk_has_tiles(chunk):
					seen[chunk] = true
					_wanted.append(chunk)
	_wanted.sort_custom(func(a : Vector2i, b : Vector2i) -> bool: return Vector2(a).distance_squared_to(centre) > Vector2(b).distance_squared_to(centre)) #(farthest first: popped from the back)
	if _decor_ready:
		_update_decor(decor)
	return true


## Is this chunk in one of the ranges?
static func _in_any(ranges : Array[Rect2i], chunk : Vector2i) -> bool:
	for range_ : Rect2i in ranges:
		if range_.has_point(chunk):
			return true
	return false


## Paints what is wanted (all of it when `all`, else within this frame's budget) and erases what is far from the view.
func _work(all : bool) -> void:
	var stop : int = Time.get_ticks_usec() + int(map.chunk_budget_ms * 1000.0)
	while not _wanted.is_empty() and (all or Time.get_ticks_usec() < stop):
		map.paint_chunk(_wanted.pop_back())
	if all or _keep.is_empty():
		return
	for chunk : Vector2i in map.painted_chunks():
		if Time.get_ticks_usec() >= stop:
			return
		if not _in_any(_keep, chunk):
			map.clear_chunk(chunk)


## The view in cells of the map: the camera's in the game, the editor's 2D view in the editor.
func _view_cells() -> Rect2i:
	var world : Rect2
	if Engine.is_editor_hint():
		var editor : Object = Engine.get_singleton(&"EditorInterface")
		if editor == null:
			return Rect2i()
		var viewport : Viewport = editor.call(&"get_editor_viewport_2d")
		if viewport == null or viewport.size == Vector2i.ZERO:
			return Rect2i()
		world = viewport.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, Vector2(viewport.size))
	elif focus.is_valid():
		world = focus.call()
	else:
		var viewport : Viewport = get_viewport()
		if viewport == null or viewport.get_camera_2d() == null:
			return Rect2i()
		world = viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	return _world_to_cells(world)


## A world rectangle as the cells of the map it covers.
func _world_to_cells(world : Rect2) -> Rect2i:
	var local : Rect2 = map.get_global_transform().affine_inverse() * world
	return Rect2i(floori(local.position.x / FacilityMap.TILE), floori(local.position.y / FacilityMap.TILE), ceili(local.size.x / FacilityMap.TILE) + 1, ceili(local.size.y / FacilityMap.TILE) + 1)


## A rectangle in cells as the chunks (chunk coordinates, end exclusive) that touch it.
func _chunk_range(cells : Rect2i) -> Rect2i:
	var first : Vector2i = Vector2i(cells.position.x >> FacilityMap.CHUNK_SHIFT, cells.position.y >> FacilityMap.CHUNK_SHIFT)
	var last : Vector2i = Vector2i((cells.end.x - 1) >> FacilityMap.CHUNK_SHIFT, (cells.end.y - 1) >> FacilityMap.CHUNK_SHIFT)
	return Rect2i(first, last - first + Vector2i.ONE)


# ------------------------------------------------------------------ decor
func _setup_decor() -> void:
	_decor_ready = true
	_decor_node = map.get_node_or_null("Decor") as Node2D
	if _decor_node == null or Engine.is_editor_hint(): #(in the editor everything is there to be edited)
		_decor_node = null
		return
	for child : Node in _decor_node.get_children():
		var chunk : Vector2i = map.chunk_of_world((child as Node2D).global_position) if child is Node2D else Vector2i.ZERO
		if not _decor.has(chunk):
			_decor[chunk] = []
		(_decor[chunk] as Array).append(child)
		_decor_node.remove_child(child)


func _update_decor(ranges : Array[Rect2i]) -> void:
	if _decor_node == null:
		return
	for chunk : Vector2i in _decor:
		var inside : bool = _in_any(ranges, chunk)
		if inside == _decor_in.has(chunk):
			continue
		for node : Node in _decor[chunk]:
			if not is_instance_valid(node):
				continue
			if inside:
				_decor_node.add_child(node)
			else:
				_decor_node.remove_child(node)
		if inside:
			_decor_in[chunk] = true
		else:
			_decor_in.erase(chunk)
