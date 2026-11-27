class_name RoomLightShapes
extends Node2D

## Where each room's ceiling light falls. A room has one light (FacilityMap.light_rooms, switched by FacilityControl) and one light source per rectangle of its floor
## (FacilityMap.light_sources), so the light always matches the room as it is drawn in the editor. A source's shape is a ring of rays from the middle of its
## rectangle (SightFan): it fills the rectangle, stops at walls and shut doors (not at furniture: the lamp is on the ceiling), and reaches spill_m further out wherever there is nothing in the way, which is out
## through the room's open doorways. The parts that fall on the room's other rectangles are cut away (they have their own source), so they do not light twice.
##
## Shapes are worked out only for lights that are on, and only again when a door near them opens or shuts. A door changes its collision a physics frame late
## (set_deferred), so a shape is redone once the physics has caught up. A body in one counts as lit (light_at).
##
## What lights the facility is a real PointLight2D per source (its lamp), like the flashlight, so the art under it keeps its colours: its texture is the
## room's rectangle with the light's falloff round it (falloff()), and it casts shadows from walls and shut doors only (LightLayers.make_ceiling: furniture's,
## generators' and consoles' occluders are on LightLayers' CAST layers, which only the flashlights use). The lamps are the same for everyone; PlayerSight then takes a lamp's
## light back off wherever the local player has no line of sight to it (room_light.gdshader), which is what the shapes are for.

const SETTLE_PHYSICS_FRAMES : int = 2 #a door's collision is in the physics space this many physics frames after it changed
const WALL_SHADOWS : int = LightLayers.FLOOR #light-occluder mask of walls and doors (the default)
const TEXTURE_STEP : float = 11.0 #world pixels per pixel of a lamp's texture (one map cell: the light is soft, so it needs no more, and the big map has 168 lamps to draw at load)

@export var facility : FacilityMap
@export var control : FacilityControl
@export_range(0.0, 10.0, 0.25, "suffix:m") var spill_m : float = 3.0 ## how far light reaches out of a room through an open doorway
@export_range(8, 256, 1) var rays : int = 64 ## how finely a shape is traced (corners and doorways get more rays by themselves)
@export var color : Color = Color("#dbeeff") ## the lamps' colour: a cool fluorescent white
@export_range(0.0, 3.0) var energy : float = 1.0 ## the lamps' brightness, as a Light2D's energy (the flashlight beam's is 1.7)

var _shapes : Array = [] #source -> Array[PackedVector2Array]
var _stale_since : PackedInt64Array = [] #source -> the physics frame it went stale on, or -1 when it is up to date
var _watched : Dictionary = {} #door -> the bound callable connected to its state_changed
var _furniture : Array[RID] = [] #see furniture()
var _lamps : Array[PointLight2D] = [] #source -> its light
var _textures : Dictionary = {} #rectangle size -> the texture its lamp uses (see _lamp_texture)


func _ready() -> void:
	if facility != null:
		facility.built.connect(rebuild)
	if control != null:
		control.light_changed.connect(func(_index : int, _on : bool) -> void: _update_lamps())
	rebuild()


## Forgets every shape and makes the lamps again: the map was built again (the rooms or doors may have moved).
func rebuild() -> void:
	_shapes.clear()
	_furniture.clear()
	_textures.clear()
	_stale_since = PackedInt64Array()
	for lamp : PointLight2D in _lamps:
		lamp.queue_free()
	_lamps.clear()
	for door : FacilityDoor in _watched:
		if is_instance_valid(door) and door.state_changed.is_connected(_watched[door]):
			door.state_changed.disconnect(_watched[door])
	_watched.clear()
	if facility == null:
		return
	_shapes.resize(facility.light_sources.size())
	_stale_since.resize(facility.light_sources.size())
	_stale_since.fill(Engine.get_physics_frames())
	for door : FacilityDoor in facility.doors:
		var callable : Callable = _on_door_changed.bind(door)
		door.state_changed.connect(callable)
		_watched[door] = callable
	for source in facility.light_sources.size():
		_lamps.append(_make_lamp(source))
	_update_lamps()


## Switches each lamp on or off with its light.
func _update_lamps() -> void:
	for source in _lamps.size():
		_lamps[source].enabled = is_source_on(source)
		_lamps[source].color = color
		_lamps[source].energy = energy


func _make_lamp(source : int) -> PointLight2D:
	var rect : Rect2 = facility.light_source_rect_px(source)
	var reach : Rect2 = rect.grow(spill_px())
	var size : Vector2i = Vector2i((reach.size / TEXTURE_STEP).ceil())
	var lamp : PointLight2D = PointLight2D.new()
	lamp.name = "Lamp%d" % source
	lamp.texture = _lamp_texture(rect, reach, size)
	lamp.texture_scale = TEXTURE_STEP
	lamp.shadow_enabled = true
	lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	LightLayers.make_ceiling(lamp) #lights furniture of every height; only walls and doors shadow it, since the lamp is on the ceiling
	lamp.enabled = false
	add_child(lamp)
	lamp.global_position = facility.to_global(reach.position + Vector2(size) * TEXTURE_STEP / 2.0)
	return lamp


## A lamp's texture. It only depends on the size of the rectangle (the falloff is measured from its middle), and the big map has many rectangles of the same size,
## so each size is drawn once: drawing it pixel by pixel in script is slow (seconds for the whole big map).
func _lamp_texture(rect : Rect2, reach : Rect2, size : Vector2i) -> ImageTexture:
	var key : Vector2i = Vector2i(rect.size.round())
	if _textures.has(key):
		return _textures[key]
	var data : PackedByteArray = PackedByteArray()
	data.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			data[y * size.x + x] = roundi(255.0 * falloff(rect, reach.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * TEXTURE_STEP))
	var texture : ImageTexture = ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, data))
	_textures[key] = texture
	return texture


func spill_px() -> float:
	return spill_m * 44.0


func source_count() -> int:
	return _stale_since.size()


func is_source_on(source : int) -> bool:
	return is_instance_valid(control) and is_instance_valid(facility) and control.is_light_on(facility.light_sources[source]["light"])


## The rectangle a source can light at most: its room rectangle and the spill round it, in world pixels.
func reach_rect(source : int) -> Rect2:
	return facility.light_source_rect_px(source).grow(spill_px())


## The polygons a source lights (world pixels). Worked out when first asked for and after a nearby door changed.
func polygons(source : int) -> Array:
	if source < 0 or source >= _stale_since.size() or not is_instance_valid(facility):
		return []
	if _stale_since[source] >= 0 and Engine.get_physics_frames() >= _stale_since[source] + SETTLE_PHYSICS_FRAMES:
		_shapes[source] = _compute(source)
		_stale_since[source] = -1
	return _shapes[source] if _shapes[source] != null else []


## How strongly the lights that are on fall on a point, 0 to 1: 1 inside a lit room, fading out through its doorways, 0 where no lit room's light reaches.
func light_at(point : Vector2) -> float:
	var best : float = 0.0
	if not is_instance_valid(facility) or not facility.is_inside_tree(): #the level is being torn down (the match ended, a lobby left) while a player's sight is still asking
		return best
	var local : Vector2 = facility.to_local(point)
	for source in source_count():
		if not is_source_on(source) or not reach_rect(source).has_point(local):
			continue
		for polygon : PackedVector2Array in polygons(source):
			if Geometry2D.is_point_in_polygon(point, polygon):
				best = maxf(best, falloff(facility.light_source_rect_px(source), local))
				break
	return best


## The light's strength at a point for a room rectangle, 0 to 1: even across the room, a little brighter under the middle of the ceiling, fading to nothing
## spill_m outside it (out through its doorways). The lamps' textures are made from it, and room_light.gdshader works out the same.
func falloff(rect : Rect2, point : Vector2) -> float:
	var half : Vector2 = (rect.size / 2.0).max(Vector2.ONE)
	var q : Vector2 = (point - rect.get_center()).abs()
	var outside : Vector2 = (q - half).max(Vector2.ZERO)
	var level : float = pow(1.0 - clampf(outside.length() / maxf(spill_px(), 1.0), 0.0, 1.0), 2.0)
	var edge : float = minf(maxf(q.x / half.x, q.y / half.y), 1.0) #0 in the middle of the room, 1 at its walls
	return level * (1.0 - 0.18 * smoothstep(0.35, 1.0, edge))


func _on_door_changed(_state : FacilityDoor.State, door : FacilityDoor) -> void:
	var door_rect : Rect2 = Rect2(facility.to_local(door.global_position) - Vector2(44.0, 44.0), Vector2(88.0, 88.0)) #(the gate and a little round it, in the map's space)
	var now : int = Engine.get_physics_frames()
	for source in source_count():
		if reach_rect(source).intersects(door_rect):
			_stale_since[source] = now


func _compute(source : int) -> Array:
	var rect : Rect2 = facility.light_source_rect_px(source)
	var centre : Vector2 = facility.to_global(rect.get_center())
	var half : Vector2 = rect.size / 2.0 + Vector2.ONE * spill_px()
	var reach : Callable = func(angle : float) -> float:
		var direction : Vector2 = Vector2.from_angle(angle)
		var tx : float = half.x / absf(direction.x) if absf(direction.x) > 0.0001 else INF
		var ty : float = half.y / absf(direction.y) if absf(direction.y) > 0.0001 else INF
		return minf(tx, ty)
	var shape : PackedVector2Array = SightFan.ring(get_world_2d().direct_space_state, centre, rays, reach, SightFan.WALLS, furniture())
	#the whole room is lit, corners too (the fan's straight edges between rays cut them off a little), and things standing in it cast no shadow: the lamp is on the ceiling
	var result : Array = _outer(Geometry2D.merge_polygons(shape, _rect_polygon(rect)))
	var room : String = facility.light_sources[source]["room"]
	for other in facility.light_sources.size(): #cut away the room's other rectangles: they have their own source
		if other == source or facility.light_sources[other]["room"] != room:
			continue
		var other_rect : Rect2 = facility.light_source_rect_px(other)
		if not other_rect.intersects(reach_rect(source)):
			continue
		var cut : PackedVector2Array = _rect_polygon(other_rect)
		var pieces : Array = []
		for polygon : PackedVector2Array in result:
			var inside : bool = true #the other rectangle lies wholly inside: cutting it would leave a hole, which cannot be drawn. It is lit twice there, which is fine
			for corner : Vector2 in cut:
				inside = inside and Geometry2D.is_point_in_polygon(corner, polygon)
			if inside:
				pieces.append(polygon)
			else:
				pieces.append_array(_outer(Geometry2D.clip_polygons(polygon, cut)))
		result = pieces
	return result


## Every piece of furniture (a body on FacilityTileSet.PROP_LAYER, like a generator, which is also solid like a wall): the lamp is on the ceiling, so its light
## goes over them and they cast no shadow in it (they do in a flashlight beam). PlayerSight leaves them out of the line of sight it cuts the lights to, for
## the same reason: the floor behind a generator is drawn, so a light missing there would look like a shadow. Found again after each build.
func furniture() -> Array[RID]:
	if _furniture.is_empty() and facility != null and facility.props_node != null:
		for node : Node in facility.props_node.find_children("*", "CollisionObject2D", true, false):
			var body : CollisionObject2D = node
			if body.collision_layer & FacilityTileSet.PROP_LAYER:
				_furniture.append(body.get_rid())
	return _furniture


## A rectangle of the map (map space) as a polygon in the world.
func _rect_polygon(rect : Rect2) -> PackedVector2Array:
	return PackedVector2Array([facility.to_global(rect.position), facility.to_global(Vector2(rect.end.x, rect.position.y)), facility.to_global(rect.end), facility.to_global(Vector2(rect.position.x, rect.end.y))])


## The polygons of a Geometry2D result that are not holes inside another of them (a hole cannot be drawn on its own; it is lit, which is fine).
func _outer(polygons_in : Array) -> Array:
	var result : Array = []
	for i in polygons_in.size():
		var polygon : PackedVector2Array = polygons_in[i]
		var hole : bool = false
		for j in polygons_in.size():
			if j != i and polygon.size() > 0 and Geometry2D.is_point_in_polygon(polygon[0], polygons_in[j]) and Geometry2D.is_point_in_polygon(polygon[polygon.size() / 2], polygons_in[j]):
				hole = true
				break
		if not hole:
			result.append(polygon)
	return result
