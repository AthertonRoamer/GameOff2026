@tool
class_name Furniture
extends StaticBody2D

##A piece of furniture or clutter on the facility's floor: a desk, a crate, a rack of boxes. Drag one from game/furniture/items/ into the map (under Props, in the group
##of its room), and set where it stands. The scene is only this node and its settings: the sprite, the collision and the light occluder are made from them when it loads
##(and again whenever a setting changes), so nothing is saved but the settings and you can change a piece's footprint right in the inspector.
##
##  texture         the picture, drawn at 176 px per metre like the characters (so it is shown at 0.25)
##  footprint       the floor it takes up, which is what stops players and shots, throws a shadow from a flashlight and blocks the view:
##                  Rectangle or Circle, `footprint_size` in world pixels (a circle is as wide as `x`), centred on the node. None: it lies on the floor (a pallet, a rug), you
##                  walk over it and it stops nothing. The items are saved with a footprint 2 px inside their picture, so what you see is what stops you.
##  height          how tall it is, in metres. It decides which shadows fall on it: only those of something taller (a chair's shadow lies on the floor but not on the table
##                  beside it; a rack's lies on the table). Pieces are sorted into LOW (under 0.6 m), MID (under 1.5 m) and TALL, see LightLayers. The top of a TALL piece
##                  takes only 0.35 of a flashlight, being out of its reach. A piece with no footprint lies flat and has no height. The footprint's occluder only throws
##                  a shadow from its far side (CULL_COUNTER_CLOCKWISE), so the top of a piece is lit like the floor and the shadow falls behind it.
##  snap            in the editor, when you move a piece its nearest edges snap to the half cell grid (5.5 px), so a side sits exactly against a wall (a circle's box
##                  counts). Turn it off to place a piece anywhere.
##
##In the editor a piece says, in the scene tree's warning, when it sticks out of its room, blocks a door or a marker, or overlaps another piece (see placement_problem).
##To make a new piece: duplicate an item scene, give it your picture (draw it facing the top of the screen, light from the top left) and set its footprint, or run
##tools/art/make_furniture.py after adding it to the list there (it also writes the scene and a trimmed sprite).
##Physics: the footprint is on the walls' layer (FacilityTileSet.WORLD_LAYER), so it stops bodies, bullets and the view the way a wall does, and on the furniture
##layer (FacilityTileSet.PROP_LAYER), so the rooms' ceiling lights reach over it and it throws no shadow in them, like a generator.

enum Footprint { NONE, RECTANGLE, CIRCLE }

const TILE : int = FacilityTileSet.TILE
const ART_SCALE : float = FacilityTileSet.ART_SCALE
const FLAT_Z : int = -12 #z_index of a piece that lies on the floor: over the floor (FacilityMap.FLOOR_Z), under a fallen body (Player.DEAD_Z)
const DOOR_CLEAR : float = 30.0 #px of floor kept clear in front of a door (a player is 24 px wide)
const MARKER_CLEAR : float = 22.0 #and round a spawn, an item location or a console
const VENT_CLEAR : float = 5.0 #and round a vent's grille
const MIN_OVERLAP : float = 0.5 #px squared
const CIRCLE_POINTS : int = 16
const WARN_COLOUR : Color = Color("#e5484d")
const OUTLINE_COLOUR : Color = Color(0.435, 0.827, 0.91, 0.55)

@export var display_name : String = ""
@export var texture : Texture2D : set = _set_texture
@export var footprint : Footprint = Footprint.RECTANGLE : set = _set_footprint
@export var footprint_size : Vector2 = Vector2(32, 32) : set = _set_size #world px (a circle uses x as its width)
@export_range(0.0, 3.0, 0.05, "suffix:m") var height : float = 0.75 : set = _set_height ## how tall it is: chair 0.45, table 0.75, rack 2.3. Shadows fall on a piece only from taller things (see LightLayers)
@export var snap : bool = true

static var _top_material : ShaderMaterial #the lighting of a TALL piece, shared
static var _shapes : Dictionary = {} #shared collision shapes and occluders, by kind and size: a map has dozens of the same piece
static var _occluders : Dictionary = {}

var _last_position : Vector2 = Vector2.ZERO
var _problem : String = ""
var _checked_for : float = 0.0
var _signature : int = 0
var _art : Sprite2D
var _occluder : LightOccluder2D
var _shown : bool = true #false while the picture and the shadow are out of the tree (set_shown)


func _ready() -> void:
	collision_mask = 0
	_last_position = position
	_rebuild()
	set_process(Engine.is_editor_hint())


func _process(delta : float) -> void: #editor only
	if snap and not position.is_equal_approx(_last_position) and is_zero_approx(fposmod(rotation_degrees, 90.0)):
		position = snapped_position() #(only when it has been moved: opening a scene leaves every piece where it was put)
	_last_position = position
	var now : int = hash([global_position, global_rotation, footprint, footprint_size, scale])
	if now == _signature:
		return
	_checked_for += delta
	if _checked_for >= 0.4:
		_checked_for = 0.0
		_signature = now
		var map : FacilityMap = owning_map()
		_problem = placement_problem(map) if map != null and not map.rooms.is_empty() else ""
		update_configuration_warnings()
		queue_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	if texture == null:
		warnings.append("This piece has no picture.")
	if _problem != "":
		warnings.append(_problem)
	return warnings


## Where `position` would be with the piece's nearest edges on the half cell grid, so an edge lands exactly on a wall (walls are on whole cells).
func snapped_position() -> Vector2:
	var half : float = TILE / 2.0
	var size : Vector2 = footprint_size if footprint != Footprint.CIRCLE else Vector2.ONE * footprint_size.x
	if is_equal_approx(fposmod(rotation_degrees, 180.0), 90.0):
		size = Vector2(size.y, size.x)
	var result : Vector2 = position
	for axis in 2: #on each axis, whichever edge is nearer a grid line goes onto it
		var near : float = position[axis] - size[axis] / 2.0
		var far : float = position[axis] + size[axis] / 2.0
		var move_near : float = roundf(near / half) * half - near
		var move_far : float = roundf(far / half) * half - far
		result[axis] += move_near if absf(move_near) <= absf(move_far) else move_far
	return result


func is_solid() -> bool:
	return footprint != Footprint.NONE


func owning_map() -> FacilityMap:
	var node : Node = get_parent()
	while node != null and not node is FacilityMap:
		node = node.get_parent()
	return node as FacilityMap


## The footprint as a polygon in the world (a rectangle's corners, or a circle as 20 points), turned and scaled with the node.
func footprint_polygon() -> PackedVector2Array:
	var local : PackedVector2Array = PackedVector2Array()
	if footprint == Footprint.CIRCLE:
		for i in CIRCLE_POINTS:
			local.append(Vector2.from_angle(i * TAU / CIRCLE_POINTS) * footprint_size.x / 2.0)
	else:
		var half : Vector2 = footprint_size / 2.0
		local = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	var result : PackedVector2Array = PackedVector2Array()
	var xf : Transform2D = global_transform
	for point : Vector2 in local:
		result.append(xf * point)
	return result


## What is wrong with where this piece stands, or "". Only pieces with a footprint can be in the way.
func placement_problem(map : FacilityMap) -> String:
	if not is_solid():
		return ""
	var polygon : PackedVector2Array = footprint_polygon()
	var bounds : Rect2 = _bounds_of(polygon)
	var space : Transform2D = map.get_global_transform().affine_inverse()
	bounds = space * bounds
	var first : Vector2i = map.world_to_cell(bounds.position + Vector2.ONE * 0.5)
	var last : Vector2i = map.world_to_cell(bounds.end - Vector2.ONE * 0.5)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if not map.is_floor(Vector2i(x, y)) or map.wall_cells.has(Vector2i(x, y)):
				return "This piece is on a wall or outside the rooms (cell %d, %d). Move it onto the floor." % [x, y]
	for door : FacilityDoor in map.doors:
		var cells : Rect2i = door.cell_rect(map)
		var zone : Rect2 = Rect2(Vector2(cells.position * TILE), Vector2(cells.size * TILE))
		zone = zone.grow_individual(6.0, DOOR_CLEAR, 6.0, DOOR_CLEAR) if door.horizontal else zone.grow_individual(DOOR_CLEAR, 6.0, DOOR_CLEAR, 6.0)
		if zone.intersects(bounds):
			return "This piece blocks the door %s. Leave room to walk through." % door.name
	for marker : Node in map.find_children("*", "Marker2D", true, false):
		if marker.get_parent() == map.vents_node: #a vent is a 2 x 2 cell grille whose top left corner is the marker
			var grille : Rect2 = Rect2((marker as Marker2D).global_position, Vector2.ONE * 2.0 * TILE).grow(VENT_CLEAR)
			var corners : PackedVector2Array = PackedVector2Array([grille.position, Vector2(grille.end.x, grille.position.y), grille.end, Vector2(grille.position.x, grille.end.y)])
			if _overlap_area(polygon, corners) > MIN_OVERLAP:
				return "This piece covers the vent %s." % marker.name
		elif _distance_to_polygon((marker as Marker2D).global_position, polygon) < MARKER_CLEAR:
			return "This piece is on top of %s." % marker.name
	for panel : Node in map.find_children("*", "ControlPanel", true, false):
		if _distance_to_polygon((panel as Node2D).global_position, polygon) < MARKER_CLEAR + 24.0:
			return "This piece is in front of the console %s." % panel.name
	for other : Node in map.find_children("*", "Furniture", true, false):
		var piece : Furniture = other as Furniture
		if piece != self and piece.is_solid() and _overlap_area(polygon, piece.footprint_polygon()) > MIN_OVERLAP:
			return "This piece overlaps %s (%s)." % [piece.name, piece.get_parent().name]
	return ""


## How much two polygons overlap, in px squared (pieces that only touch overlap by nothing, however the numbers round).
func _overlap_area(a : PackedVector2Array, b : PackedVector2Array) -> float:
	var total : float = 0.0
	for shared : PackedVector2Array in Geometry2D.intersect_polygons(a, b):
		var twice : float = 0.0
		for i in shared.size():
			twice += shared[i].x * shared[(i + 1) % shared.size()].y - shared[(i + 1) % shared.size()].x * shared[i].y
		total += absf(twice) / 2.0
	return total


func _bounds_of(polygon : PackedVector2Array) -> Rect2:
	var rect : Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point : Vector2 in polygon:
		rect = rect.expand(point)
	return rect


func _distance_to_polygon(point : Vector2, polygon : PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, polygon):
		return 0.0
	var best : float = INF
	for i in polygon.size():
		var closest : Vector2 = Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
		best = minf(best, point.distance_to(closest))
	return best


func tier() -> LightLayers.Tier:
	return LightLayers.tier_of(height, is_solid())


static func _tall_material() -> ShaderMaterial:
	if _top_material == null:
		_top_material = ShaderMaterial.new()
		_top_material.shader = load("res://game/furniture/furniture_top.gdshader")
		_top_material.set_shader_parameter("top_light", LightLayers.TALL_TOP_LIGHT)
	return _top_material


func _set_height(value : float) -> void:
	height = value
	_rebuild()


func _set_texture(value : Texture2D) -> void:
	texture = value
	_rebuild()


func _set_footprint(value : Footprint) -> void:
	footprint = value
	_rebuild()


func _set_size(value : Vector2) -> void:
	footprint_size = value
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready():
		return
	for old : Node in [get_node_or_null("Footprint"), _art, _occluder]: #(the picture and the shadow may be out of the tree: see set_shown)
		if is_instance_valid(old):
			if old.get_parent() == self:
				remove_child(old)
			old.free()
	_art = null
	_occluder = null
	_shown = true
	collision_layer = FacilityTileSet.WORLD_LAYER | FacilityTileSet.PROP_LAYER if is_solid() else 0 #(PROP_LAYER: the ceiling lights reach over it, see RoomLightShapes.furniture)
	z_index = 0 if is_solid() else FLAT_Z
	var art : Sprite2D = Sprite2D.new() #(no owner: none of this is saved into the map scene)
	art.name = "Art"
	art.texture = texture
	art.scale = Vector2.ONE * ART_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tier : LightLayers.Tier = tier()
	art.light_mask = LightLayers.receiver_layer(tier) #lit by the light for its own height (see LightLayers)
	if tier == LightLayers.Tier.TALL:
		art.material = _tall_material()
	add_child(art)
	_art = art
	if is_solid():
		var key : String = "%d %s" % [footprint, footprint_size]
		if not _shapes.has(key): #(a map has dozens of the same piece: they share one shape and one occluder)
			var shape : Shape2D
			if footprint == Footprint.CIRCLE:
				shape = CircleShape2D.new()
				(shape as CircleShape2D).radius = footprint_size.x / 2.0
			else:
				shape = RectangleShape2D.new()
				(shape as RectangleShape2D).size = footprint_size
			_shapes[key] = shape
			var shared : OccluderPolygon2D = OccluderPolygon2D.new()
			shared.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE #shades only behind the piece, so its own top is lit
			var outline : PackedVector2Array = PackedVector2Array()
			if footprint == Footprint.CIRCLE:
				for i in CIRCLE_POINTS:
					outline.append(Vector2.from_angle(i * TAU / CIRCLE_POINTS) * footprint_size.x / 2.0)
			else:
				var half : Vector2 = footprint_size / 2.0
				outline = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
			shared.polygon = outline
			_occluders[key] = shared
		var body : CollisionShape2D = CollisionShape2D.new()
		body.name = "Footprint"
		body.shape = _shapes[key]
		add_child(body)
		var occluder : LightOccluder2D = LightOccluder2D.new()
		occluder.name = "Occluder"
		occluder.occluder = _occluders[key]
		occluder.occluder_light_mask = LightLayers.caster_layer(tier) #throws a shadow only in the lights for lower things
		add_child(occluder)
		_occluder = occluder
	queue_redraw()


## Streaming (MapStreamer): the picture and the shadow are in the tree only while the piece is near the view. Every shadowed light checks every occluder in the tree
## each frame, so on the big map (about 1,900 of them) the ones far away would cost the frame for nothing. The body is always there: the game needs it everywhere.
func set_shown(value : bool) -> void:
	if value == _shown:
		return
	_shown = value
	for node : Node in [_art, _occluder]:
		if not is_instance_valid(node):
			continue
		if value and node.get_parent() == null:
			add_child(node)
		elif not value and node.get_parent() == self:
			remove_child(node)


func _notification(what : int) -> void:
	if what == NOTIFICATION_PREDELETE: #what is out of the tree is nobody's child: it is freed by hand
		for node : Node in [_art, _occluder]:
			if is_instance_valid(node) and node.get_parent() == null:
				node.free()


func _draw() -> void: #the footprint, in the editor only: what is solid, and red when something is wrong with where it is
	if not Engine.is_editor_hint() or not is_solid():
		return
	var colour : Color = WARN_COLOUR if _problem != "" else OUTLINE_COLOUR
	if footprint == Footprint.CIRCLE:
		draw_arc(Vector2.ZERO, footprint_size.x / 2.0, 0.0, TAU, 24, colour, 1.0)
	else:
		draw_rect(Rect2(-footprint_size / 2.0, footprint_size), colour, false, 1.0)
