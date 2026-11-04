extends Node

##Photographs the 3D environment pieces from straight above and writes the tile and prop images, the way the character sprites were made:
##an orthographic overhead camera, the cel material from the sprite kit, and an ink outline where a surface steps up from the one beside it.
##Run it with a window (3D needs a renderer), from the repository root:
##  godot --path . res://night_shift/environment/render/env_render.tscn -- [--only=floors,walls,doors] [--out=res://night_shift/environment/art/]
##Resolution: 176 px per metre, the same as the cel character sheets, so one 0.5 m tile is 88 px. In the game everything visual is drawn at
##scale 0.25 (44 px per metre) next to the 0.25-scaled character sprites.

const PX_PER_M : float = 176.0
const INK_THRESHOLD : float = 0.02 #a surface this much higher than its neighbour gets an ink line on the lower side
const INK_COLOR : Color = Color("#07090c")
const HEIGHT_SHADER : Shader = preload("res://night_shift/environment/render/height.gdshader")

var _out_dir : String = "res://night_shift/environment/art/"
var _only : PackedStringArray = []
var _height_material : ShaderMaterial


func _ready() -> void:
	_height_material = ShaderMaterial.new()
	_height_material.shader = HEIGHT_SHADER
	for arg : String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",")
	await get_tree().process_frame
	await _run()
	get_tree().quit()


func _wanted(group : String) -> bool:
	return _only.is_empty() or group in _only


func _run() -> void:
	var cell_px : int = roundi(EnvPieces.CELL * PX_PER_M)
	if _wanted("floors"): #columns are the shapes, rows are the tones
		var tones : int = EnvPieces.FLOOR_TONES.size()
		var atlas : Image = Image.create(cell_px * EnvPieces.FLOOR_SHAPES, cell_px * tones, false, Image.FORMAT_RGBA8)
		for tone in tones:
			for shape in EnvPieces.FLOOR_SHAPES:
				var tile : Image = await _render(func(root : Node3D) -> void: root.add_child(EnvPieces.floor_tile(shape, tone)),
					Vector2(EnvPieces.CELL, EnvPieces.CELL), Rect2(-0.25, -0.25, 0.5, 0.5))
				atlas.blit_rect(tile, Rect2i(0, 0, cell_px, cell_px), Vector2i(shape * cell_px, tone * cell_px))
		_save(atlas, "floors.png")
	if _wanted("walls"):
		var atlas : Image = Image.create(cell_px * 16, cell_px * 16, false, Image.FORMAT_RGBA8)
		for mask in 256:
			var tile : Image = await _render(func(root : Node3D) -> void: root.add_child(EnvPieces.wall_tile(mask)),
				Vector2(1.5, 1.5), Rect2(-0.25, -0.25, 0.5, 0.5))
			atlas.blit_rect(tile, Rect2i(0, 0, cell_px, cell_px), Vector2i((mask % 16) * cell_px, (mask / 16) * cell_px))
		_save(atlas, "walls.png")
	if _wanted("doors"):
		for exterior in [false, true]:
			for state in ["closed", "locked", "open"]:
				for vertical in [false, true]:
					var area : Vector2 = Vector2(0.5, 1.0) if vertical else Vector2(1.0, 0.5)
					var image : Image = await _render(func(root : Node3D) -> void: root.add_child(EnvPieces.door(state, exterior, vertical)),
						area, Rect2(-area.x / 2.0, -area.y / 2.0, area.x, area.y))
					_save(image, "door_%s_%s_%s.png" % ["exterior" if exterior else "interior", state, "v" if vertical else "h"])


##Builds a piece, renders its colour and its height from above, draws the ink and returns the cropped picture.
##area is the size of the photographed region in metres, centred on the origin; crop is the part to keep, relative to the centre.
func _render(build : Callable, area : Vector2, crop : Rect2) -> Image:
	var size : Vector2i = Vector2i(roundi(area.x * PX_PER_M), roundi(area.y * PX_PER_M))
	var viewport : SubViewport = SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var root : Node3D = Node3D.new()
	viewport.add_child(root)
	var camera : Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = area.y
	camera.near = 0.05
	camera.far = 20.0
	camera.position = Vector3(0.0, 10.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0) #looking straight down, picture up is -Z, picture right is +X
	root.add_child(camera)
	camera.current = true
	build.call(root)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var color : Image = viewport.get_texture().get_image()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = _height_material
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var height : Image = viewport.get_texture().get_image()
	viewport.queue_free()
	var rect : Rect2i = Rect2i(Vector2i((Vector2(crop.position) * PX_PER_M + Vector2(size) / 2.0).round()), Vector2i((Vector2(crop.size) * PX_PER_M).round()))
	return _with_ink(color, height, rect)


##A surface that is higher than its neighbour gets a one pixel ink line on the lower side, which also outlines a prop against the floor.
func _with_ink(color : Image, height : Image, crop : Rect2i) -> Image:
	var w : int = color.get_width()
	var h : int = color.get_height()
	var heights : PackedFloat32Array = PackedFloat32Array()
	heights.resize(w * h)
	for y in h:
		for x in w:
			var p : Color = height.get_pixel(x, y)
			heights[y * w + x] = decode_height(p) if p.a > 0.5 else -1.0
	var out : Image = Image.create(crop.size.x, crop.size.y, false, Image.FORMAT_RGBA8)
	for y in range(crop.position.y, crop.end.y):
		for x in range(crop.position.x, crop.end.x):
			var own : float = heights[y * w + x]
			var ink : bool = false
			for o : Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx : int = x + o.x
				var ny : int = y + o.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h and heights[ny * w + nx] - own > INK_THRESHOLD:
					ink = true
					break
			out.set_pixel(x - crop.position.x, y - crop.position.y, INK_COLOR if ink else color.get_pixel(x, y))
	return out


##Undoes the packing in height.gdshader. The viewport hands back sRGB-encoded values, so they are converted to linear first.
static func decode_height(p : Color) -> float:
	var lin : Color = p.srgb_to_linear()
	return (lin.r * 255.0 + lin.g) / 255.0 * 2.0


func _save(image : Image, file : String) -> void:
	var path : String = _out_dir.path_join(file)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	image.save_png(path)
	print("wrote ", path, " ", image.get_size())
