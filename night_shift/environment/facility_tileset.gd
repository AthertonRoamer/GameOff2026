class_name FacilityTileSet
extends RefCounted

##Builds the facility's TileSet from the rendered atlases in art/ (made by render/env_render.gd from 3D pieces photographed from above).
##The art is drawn at 176 px per metre like the cel character sheets, so a 0.5 m tile is 88 px. The map draws its tile layers at ART_SCALE
##(0.25), which makes a tile 22 px and keeps the world at 44 px per metre, the same scale the 0.25-scaled character sprites use.
##  source 0, floors: 4 columns (variants) x 5 rows, one row per floor kind in FLOOR_KINDS
##  source 1, walls:  16 x 16 atlas, tile index = bitmask of which neighbours are wall (see NEIGHBOURS)
##Walls carry a collision shape on physics layer 2 ("world") and a light occluder, so they block movement, bullets and light.

const TILE : int = 22 #world pixels per tile (0.5 m)
const ART_TILE : int = 88 #pixels per tile in the images
const ART_SCALE : float = 0.25
const SOURCE_FLOORS : int = 0
const SOURCE_WALLS : int = 1
const FLOOR_KINDS : PackedStringArray = ["room", "corridor", "utility", "vault", "outdoor"]
const ART_DIR : String = "res://night_shift/environment/art/"

const WORLD_LAYER : int = 1 << 1 #physics layer 2: walls and other solid world pieces, stops bodies and projectiles
const DOOR_LAYER : int = 1 << 3 #physics layer 4: closed doors, stops bodies only

const NEIGHBOURS : Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)] #N, NE, E, SE, S, SW, W, NW: bit 0 to bit 7 of a wall mask


static func build() -> TileSet:
	var tile_set : TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(ART_TILE, ART_TILE)
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, WORLD_LAYER)
	tile_set.set_physics_layer_collision_mask(0, 0)
	tile_set.add_occlusion_layer()
	_add_source(tile_set, SOURCE_FLOORS, "floors.png", 4, FLOOR_KINDS.size(), false)
	_add_source(tile_set, SOURCE_WALLS, "walls.png", 16, 16, true)
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
	source.texture_region_size = Vector2i(ART_TILE, ART_TILE)
	for y in rows:
		for x in columns:
			source.create_tile(Vector2i(x, y))
	tile_set.add_source(source, id) #the source must belong to the tile set before its tile data can use the tile set's layers
	if not solid:
		return
	var half : float = ART_TILE / 2.0
	var square : PackedVector2Array = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for y in rows:
		for x in columns:
			var data : TileData = source.get_tile_data(Vector2i(x, y), 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, square)
			var occluder : OccluderPolygon2D = OccluderPolygon2D.new()
			occluder.polygon = square
			data.set_occluder(0, occluder)
