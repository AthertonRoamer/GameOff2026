extends SceneTree

## Bakes the guard's SpriteFrames into game/player/skin/guard/guard_frames.tres, so the skin scene can use it in the editor. Run after the sheets or
## sprites.json change (tools/rig makes them):
##   godot --headless --path . --script res://tools/art/bake_skin_frames.gd [-- <role>]

func _init() -> void:
	var role : String = "guard"
	var args : PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	var error : Error = NightShiftCharacter.bake_frames("res://game/player/skin", role)
	print("bake_skin_frames: %s -> %s" % [role, error_string(error)])
	quit(0 if error == OK else 1)
