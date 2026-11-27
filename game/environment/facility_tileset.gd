class_name FacilityTileSet
extends RefCounted

##Builds the facility's TileSet from the rendered atlases in art/ (made by render/env_render.gd from 3D pieces photographed from above).
##The art is drawn at 176 px per metre like the cel character sheets, so a quarter metre cell is 44 px. The map draws its tile layers at ART_SCALE
##(0.25), which makes a cell 11 px and keeps the world at 44 px per metre, the same scale the 0.25-scaled character sprites use.
##  source 0, floors: one plain tile
##  source 1, walls:  16 x 16, tile index = bitmask of which neighbours are wall (see NEIGHBOURS)
##  source 2, shadows: 16 x 16, soft shadow for a floor cell, tile index = bitmask of which neighbours are wall
##The tiles only draw. The walls' collision (physics layer 2, "world") and light occluders are made by the map from the wall cells joined into rectangles
##(FacilityMap._build_wall_body).

const TILE : int = 11 #world pixels per cell (0.25 m, also the thickness of a wall)
const ART_TILE : int = 44 #pixels per cell in the images
const ART_SCALE : float = 0.25
const SOURCE_FLOORS : int = 0
const SOURCE_WALLS : int = 1
const SOURCE_SHADOWS : int = 2
const ART_DIR : String = "res://game/environment/art/"
const TILESET_PATH : String = "res://game/environment/facility_tileset.tres" #the saved tile set the map's layers use (baked by bake())

const WORLD_LAYER : int = 1 << 1 #physics layer 2: walls and other solid world pieces, stops bodies and projectiles
const DOOR_LAYER : int = 1 << 3 #physics layer 4: closed doors, stops bodies only
const STRUCTURE_LAYER : int = 1 << 5 #physics layer 6: the walls only (they are on WORLD_LAYER too). What a ceiling light is stopped by, with doors: testing this layer passes over every piece of furniture without listing them
const PROP_LAYER : int = 1 << 4 #physics layer 5: furniture (generators, consoles). Casts shadows in flashlight beams, not in the rooms' ceiling lights. Stops nothing by itself

const NEIGHBOURS : Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)] #N, NE, E, SE, S, SW, W, NW: bit 0 to bit 7 of a wall mask


static var _shared : TileSet


##The tile set, loaded once: the saved facility_tileset.tres (the map scene's layers use the same file, so it can be inspected and tweaked in the editor),
##or built in code if that file is missing. WarmUp loads it at startup, so loading a game does not.
static func shared() -> TileSet:
	if _shared == null:
		_shared = load(TILESET_PATH) if ResourceLoader.exists(TILESET_PATH) else build()
	return _shared


##Saves build() as TILESET_PATH. Run it again after changing the art layout or the wall shapes: godot --headless --script res://tools/art/bake_facility_tileset.gd
static func bake() -> Error:
	return ResourceSaver.save(build(), TILESET_PATH)


static func build() -> TileSet:
	var tile_set : TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(ART_TILE, ART_TILE)
	_add_source(tile_set, SOURCE_FLOORS, "floors.png", 1, 1)
	_add_source(tile_set, SOURCE_WALLS, "walls.png", 16, 16)
	_add_source(tile_set, SOURCE_SHADOWS, "shadows.png", 16, 16)
	return tile_set


static func neighbour_mask(cell : Vector2i, cells : Dictionary) -> int:
	var mask : int = 0
	for i in NEIGHBOURS.size():
		if cells.has(cell + NEIGHBOURS[i]):
			mask |= 1 << i
	return mask


static func mask_to_atlas(mask : int) -> Vector2i:
	return Vector2i(mask % 16, mask / 16)


static func _add_source(tile_set : TileSet, id : int, file : String, columns : int, rows : int) -> void:
	var source : TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = load(ART_DIR + file)
	source.texture_region_size = Vector2i(ART_TILE, ART_TILE)
	for y in rows:
		for x in columns:
			source.create_tile(Vector2i(x, y))
	tile_set.add_source(source, id)
