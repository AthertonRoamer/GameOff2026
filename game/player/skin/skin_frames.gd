class_name SkinFrames
extends RefCounted

## A role's skin data: its sprites.json (per sheet: file, frame layout, fps, offset, shoulder positions...) and the SpriteFrames made from it.
## tools/rig renders the sheets and writes sprites.json; bake() turns them into <role>_frames.tres so the skin scene can use (and preview) them in the editor
## (tools/art/bake_skin_frames.gd runs it). A role with no baked file yet is cut from its sheets in code by load_role().

static var _loaded : Dictionary = {}


## The role's sprites.json and SpriteFrames, loaded once: the baked <role>_frames.tres when it exists, otherwise cut from the sheets. WarmUp calls this at startup
## so the sheets are in memory before a game starts.
static func load_role(root : String, role_name : String) -> Dictionary:
	var folder := "%s/%s" % [root, role_name]
	if not _loaded.has(folder):
		var meta : Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/sprites.json" % folder))
		var baked := "%s/%s_frames.tres" % [folder, role_name]
		_loaded[folder] = {"meta": meta, "frames": load(baked) if ResourceLoader.exists(baked) else build_frames(folder, meta)}
	return _loaded[folder]


## Cuts a role's sheets into a SpriteFrames, from its sprites.json: one animation per entry, with the fps and looping the file says.
static func build_frames(folder : String, meta : Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name : String in meta.keys():
		var m : Dictionary = meta[anim_name]
		var texture : Texture2D = load("%s/%s" % [folder, m["file"]])
		var frame_w := int(m.get("frame_w", m["frame_size"])) #a trimmed sheet (tools/rig/pack) has frames that are not the rendered size
		var frame_h := int(m.get("frame_h", m["frame_size"]))
		var columns := int(m["hframes"])
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, m["fps"])
		frames.set_animation_loop(anim_name, m["loop"])
		for i in int(m["frames"]):
			var cell := AtlasTexture.new()
			cell.atlas = texture
			cell.region = Rect2((i % columns) * frame_w, (i / columns) * frame_h, frame_w, frame_h)
			frames.add_frame(anim_name, cell)
	return frames


## Saves a role's SpriteFrames as <root>/<role>/<role>_frames.tres, so it can be assigned in the editor.
static func bake(root : String, role_name : String) -> Error:
	var folder := "%s/%s" % [root, role_name]
	var meta : Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/sprites.json" % folder))
	return ResourceSaver.save(build_frames(folder, meta), "%s/%s_frames.tres" % [folder, role_name])
