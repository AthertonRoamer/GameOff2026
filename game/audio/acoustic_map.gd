class_name AcousticMap
extends Node

##The facility as sound sees it: a grid with open floor and open doors easy to cross and walls and closed doors costly (see Acoustics). hear() finds the cheapest way
##from a sound to the listener. Door states are followed as they change. Every peer works this out for itself from the map and the door states it already has,
##so nothing about sound is sent over the network.

class Hearing extends RefCounted:
	var distance_px : float = 0.0 ## how far away the sound seems: the length of its way, in pixels
	var direction : Vector2 = Vector2.ZERO ## from the listener towards where it seems to come from
	var muffle : float = 0.0
	var room_kind : String = "" ## of the room it was made in, which decides its echo

const CACHE_LIMIT : int = 800

var acoustics : Acoustics
var _map : FacilityMap
var _grid : AStarGrid2D
var _door_at : Dictionary = {} #cell -> the door standing in it
var _cache : Dictionary = {} #(source cell, listener cell) -> the way between them; cleared when a door moves


func setup(map : FacilityMap, p_acoustics : Acoustics) -> void:
	_map = map
	acoustics = p_acoustics
	if map.floor_rects.is_empty():
		map.built.connect(_build, CONNECT_ONE_SHOT)
	else:
		_build()


func _build() -> void:
	_grid = AStarGrid2D.new()
	_grid.region = _map.map_cell_bounds().grow(1)
	_grid.cell_size = Vector2(FacilityMap.TILE, FacilityMap.TILE)
	_grid.offset = _grid.cell_size / 2.0
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.update()
	var wall_weight : float = 1.0 + acoustics.wall_extra_m * Acoustics.PX_PER_METRE / FacilityMap.TILE
	_grid.fill_solid_region(_grid.region, true) #outside the building: sound does not go round the outside of it...
	for rect : Rect2i in _map.floor_rects:
		_grid.fill_solid_region(rect.grow(1), false) #...but through the floor and the walls round it (which cost more to cross)
	for cell : Vector2i in _map.wall_cells:
		_grid.set_point_weight_scale(cell, wall_weight)
	for door : FacilityDoor in _map.doors:
		var rect : Rect2i = door.cell_rect(_map)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_door_at[Vector2i(x, y)] = door
		door.state_changed.connect(func(_state : FacilityDoor.State) -> void: _set_door_weight(door))
		_set_door_weight(door)


func _set_door_weight(door : FacilityDoor) -> void:
	var extra : float = acoustics.closed_door_extra_m if door.is_blocking() else acoustics.open_door_extra_m
	var rect : Rect2i = door.cell_rect(_map)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_grid.set_point_weight_scale(Vector2i(x, y), 1.0 + extra * Acoustics.PX_PER_METRE / FacilityMap.TILE)
	_cache.clear()


##How a sound made at `from` is heard at `to`, or null if it does not carry that far. range_px is the sound's reach.
func hear(from : Vector2, to : Vector2, range_px : float) -> Hearing:
	var straight : float = from.distance_to(to)
	if straight > range_px:
		return null
	var hearing : Hearing = Hearing.new()
	hearing.room_kind = _room_kind(from)
	var source : Vector2i = _map.world_to_cell(from)
	var listener : Vector2i = _map.world_to_cell(to)
	if _grid == null or source == listener or not _usable(source) or not _usable(listener):
		return _direct(hearing, from, to, straight)
	var way : Dictionary = _way(source, listener, to)
	if way["cost"] > range_px:
		return null
	if way["walls"] == 0 and way["doors"] == 0 and way["cost"] <= straight * 1.15:
		return _direct(hearing, from, to, straight) #a clear line: it is heard from where it is
	hearing.distance_px = way["cost"]
	hearing.direction = (way["lead"] - to).normalized()
	hearing.muffle = way["walls"] * acoustics.wall_muffle + way["doors"] * acoustics.closed_door_muffle + acoustics.indirect_muffle
	return hearing


func _direct(hearing : Hearing, from : Vector2, to : Vector2, straight : float) -> Hearing:
	hearing.distance_px = straight
	hearing.direction = (from - to).normalized()
	return hearing


func _usable(cell : Vector2i) -> bool:
	return _grid.is_in_boundsv(cell) and not _grid.is_point_solid(cell)


func _room_kind(world : Vector2) -> String:
	var room : String = _map.room_at(world)
	return _map.rooms[room]["kind"] if room != "" else ""


##The cheapest way between two cells: its cost in pixels, the walls and closed doors it goes through, and the point the sound seems to come from.
func _way(source : Vector2i, listener : Vector2i, listener_world : Vector2) -> Dictionary:
	var key : Vector4i = Vector4i(source.x, source.y, listener.x, listener.y)
	if _cache.has(key):
		return _cache[key]
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()
	var cells : Array[Vector2i] = _grid.get_id_path(source, listener)
	var way : Dictionary = {"cost": INF, "walls": 0, "doors": 0, "lead": listener_world}
	if not cells.is_empty():
		var cost : float = 0.0
		for i in range(1, cells.size()):
			var cell : Vector2i = cells[i]
			var diagonal : bool = cell.x != cells[i - 1].x and cell.y != cells[i - 1].y
			cost += FacilityMap.TILE * (1.4142 if diagonal else 1.0) * _grid.get_point_weight_scale(cell)
			if _map.wall_cells.has(cell):
				way["walls"] += 1
			elif _door_at.has(cell) and (_door_at[cell] as FacilityDoor).is_blocking():
				way["doors"] += 1
		way["cost"] = cost
		var lookahead : float = acoustics.lookahead_m * Acoustics.PX_PER_METRE
		way["lead"] = _map.cell_to_world(cells[0])
		for i in range(cells.size() - 1, -1, -1): #back from the listener to the first point far enough away to give a direction
			var point : Vector2 = _map.cell_to_world(cells[i])
			if point.distance_to(listener_world) >= lookahead:
				way["lead"] = point
				break
	_cache[key] = way
	return way
