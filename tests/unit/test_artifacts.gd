extends Node

# Offline test that every artifact in game/items/artifacts/ is set up properly, including any added later:
#   Godot_console.exe --headless --path . res://tests/unit/test_artifacts.tscn

const FOLDER : String = "res://game/items/artifacts/"

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	var names : Dictionary = {}
	var icons : Dictionary = {}
	var count : int = 0
	for file in DirAccess.get_files_at(FOLDER):
		if not file.ends_with(".tres"):
			continue
		count += 1
		var artifact : Artifact = load(FOLDER + file) as Artifact
		check(artifact != null, "%s is an Artifact" % file)
		if artifact == null:
			continue
		check(artifact.item_name != "" and not names.has(artifact.item_name), "%s has a unique name (%s)" % [file, artifact.item_name])
		check(artifact.icon != null and not icons.has(artifact.icon.resource_path), "%s has its own image" % file)
		check(not artifact.drawable, "%s can't be drawn like a gun" % file)
		names[artifact.item_name] = true
		if artifact.icon != null:
			icons[artifact.icon.resource_path] = true
	check(count >= 2, "there are several artifacts (%d)" % count)

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
