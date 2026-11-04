extends Node

##Writes the environment images: a plain floor, smooth walls, soft floor shadows and the gates. They are computed by EnvSmooth (height maps seen from
##above, 176 px per metre like the cel character sheets), so no window or 3D renderer is needed.
##Run from the repository root:
##  godot --headless --path . res://night_shift/environment/render/env_render.tscn -- [--only=floors,walls,shadows,doors] [--out=res://night_shift/environment/art/]
##Then import and keep mipmaps on:  godot --headless --path . --import  (mipmaps/generate=true in each art/*.png.import)

var _out_dir : String = "res://night_shift/environment/art/"
var _only : PackedStringArray = []


func _ready() -> void:
	for arg : String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
	_run()
	get_tree().quit()


func _wanted(group : String) -> bool:
	return _only.is_empty() or group in _only


func _run() -> void:
	var cell : int = EnvSmooth.CELL_PX
	if _wanted("floors"):
		_save(EnvSmooth.floor_tile(), "floors.png")
	if _wanted("walls"): #atlas column = mask % 16, row = mask / 16
		var atlas : Image = Image.create(cell * 16, cell * 16, false, Image.FORMAT_RGBA8)
		for mask in 256:
			atlas.blit_rect(EnvSmooth.wall_tile(mask), Rect2i(0, 0, cell, cell), Vector2i((mask % 16) * cell, (mask / 16) * cell))
		_save(atlas, "walls.png")
	if _wanted("shadows"):
		var atlas : Image = Image.create(cell * 16, cell * 16, false, Image.FORMAT_RGBA8)
		for mask in 256:
			atlas.blit_rect(EnvSmooth.floor_shadow(mask), Rect2i(0, 0, cell, cell), Vector2i((mask % 16) * cell, (mask / 16) * cell))
		_save(atlas, "shadows.png")
	if _wanted("doors"):
		for exterior in [false, true]:
			for state in ["closed", "locked", "open"]:
				for vertical in [false, true]:
					_save(EnvSmooth.gate(state, exterior, vertical), "door_%s_%s_%s.png" % ["exterior" if exterior else "interior", state, "v" if vertical else "h"])


func _save(image : Image, file : String) -> void:
	var path : String = _out_dir.path_join(file)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	image.save_png(path)
	print("wrote ", path, " ", image.get_size())
