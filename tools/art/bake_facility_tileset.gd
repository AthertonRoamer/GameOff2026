extends SceneTree

## Saves the facility's TileSet as night_shift/environment/facility_tileset.tres (see FacilityTileSet.bake()):
##   godot --headless --path . --script res://tools/art/bake_facility_tileset.gd

func _init() -> void:
	var error : Error = FacilityTileSet.bake()
	print("bake_facility_tileset: %s" % error_string(error))
	quit(0 if error == OK else 1)