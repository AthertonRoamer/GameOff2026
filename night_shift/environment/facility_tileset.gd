class_name FacilityTileSet
extends RefCounted

##Builds the facility's TileSet from the generated atlases in art/ (tools/art/make_facility_art.py).
##Scale from the sprite kit: 44 px = 1 m, so a 22 px tile is half a metre.
##  source 0, floors:  4 columns (variants) x 5 rows, one row per floor kind in FLOOR_KINDS
##  source 1, walls:   16 x 16 atlas, tile index = bitmask of which neighbours are wall (see the NEIGHBOUR_* bits)
##  source 2, shadows: same layout as the walls, contact shadows drawn on floor cells that touch walls
##Walls carry a collision shape on physics layer 2 ("world") and a light occluder, so they block movement, bullets and light.

const TILE : int = 22
const SOURCE_FLOORS : int = 0
const SOURCE_WALLS : int = 1
const SOURCE_SHADOWS : int = 2
const FLOOR_KINDS : PackedStringArray = ["room", "corridor", "utility", "vault", "outdoor"]
const ART_DIR : String = "res://night_shift/environment/art/"

const WORLD_LAYER : int = 1 << 1 #physics layer 2: walls and other solid world pieces, stops bodies and projectiles
const DOOR_LAYER : int = 1 << 3 #physics layer 4: closed doors, stops bodies only

const NEIGHBOUR_N : int = 1
const NEIGHBOUR_NE : int = 2
const NEIGHBOUR_E : int = 4
const NEIGHBOUR_SE : int = 8
const NEIGHBOUR_S : int = 16
const NEIGHBOUR_SW : int = 32
const NEIGHBOUR_W : int = 64
const NEIGHBOUR_NW : int = 128

const NEIGHBOURS : Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)] #in the order of the bits above


static func build() -> TileSet:
	var tile_set : TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, WORLD_LAYER)
	tile_set.set_physics_layer_collision_mask(0, 0)
	tile_set.add_occlusion_layer()
	_add_source(tile_set, SOURCE_FLOORS, "floors.png", 4, FLOOR_KINDS.size(), false)
	_add_source(tile_set, SOURCE_WALLS, "walls.png", 16, 16, true)
	_add_source(tile_set, SOURCE_SHADOWS, "shadows.png", 16, 16, false)
	return tile_set


static func neighbour_mask(cell : Vector2i, cells : Dictionary) -> int:
	var mask : int = 0
	for i in NEIGHBOURS.size():
		if cells.has(cell + NEIGHBOURS[i]):
			mask |= 1 << i
	return mask


static func mask_to_atlas(mask : int) -> Vector2i:
	return Vector2i(mask % 16, mask / 16)


static func _add_source(tile_set : TileSet, id : int, file : String, columns : int, rows : int, solid : bool) -> void:
	var source : TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = load(ART_DIR + file)
	source.texture_region_size = Vector2i(TILE, TILE)
	for y in rows:
		for x in columns:
			source.create_tile(Vector2i(x, y))
	tile_set.add_source(source, id) #the source must belong to the tile set before its tile data can use the tile set's layers
	if not solid:
		return
	var half : float = TILE / 2.0
	var square : PackedVector2Array = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for y in rows:
		for x in columns:
			var data : TileData = source.get_tile_data(Vector2i(x, y), 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)
			var occluder : OccluderPolygon2D = OccluderPolygon2D.new()
			occluder.polygon = square
			data.set_occluder(0, occluder)
