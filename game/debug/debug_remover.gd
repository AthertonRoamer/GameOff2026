class_name DebugRemover
extends Node

##Turns off every debug setting in the scene it is part of, so the game cannot ship with one left on by accident.
##
##A script declares its debug settings in a constant, and keeps them in an "Debug" export group so they are easy to spot in the inspector:
##    const DEBUG_SETTINGS : Array[StringName] = [&"can_toggle_darkness"]
##    @export_group("Debug")
##    @export var can_toggle_darkness : bool = false
##Every setting listed there must be a bool that is off when false. When this node is enabled it sets each of them to false on its parent and
##on every node below it (instanced scenes included), and keeps doing so for nodes added later, like the players spawned at runtime.
##
##Autoloads (like PixelArt) are not part of any scene but run during the game too, so with strip_autoloads it also strips every autoload
##listed in the project settings (just the autoload node itself). That change lasts after the game ends, which is what a release build wants.
##
##Keep it the FIRST child of the scene root: children are readied in order, so it then runs before the nodes beside it read their settings in
##their own _ready.

@export var enabled : bool = false #on: strip every debug setting. Turn this on for a release build
@export var always_in_release_builds : bool = true #exported builds without debug (export_release) strip them whatever `enabled` says
@export var strip_autoloads : bool = true #also strip the project's autoloads

var _root : Node


func _ready() -> void:
	if not is_active():
		return
	_root = get_parent()
	_strip(_root)
	for node : Node in _root.find_children("*", "", true, false):
		_strip(node)
	if strip_autoloads:
		for node : Node in autoloads():
			_strip(node)
	get_tree().node_added.connect(_on_node_added)


##The autoload nodes the project settings list (autoload/<Name>), as they are in the tree under /root.
func autoloads() -> Array[Node]:
	var result : Array[Node] = []
	for property : Dictionary in ProjectSettings.get_property_list():
		var setting : String = property["name"]
		if setting.begins_with("autoload/"):
			var node : Node = get_tree().root.get_node_or_null(NodePath(setting.trim_prefix("autoload/")))
			if node != null:
				result.append(node)
	return result


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func is_active() -> bool:
	return enabled or (always_in_release_builds and not OS.is_debug_build())


##The debug settings a node's script declares (its own and its base scripts').
static func debug_settings_of(node : Node) -> Array[StringName]:
	var result : Array[StringName] = []
	var script : Script = node.get_script()
	while script != null:
		var constants : Dictionary = script.get_script_constant_map()
		if constants.has("DEBUG_SETTINGS"):
			for setting : StringName in constants["DEBUG_SETTINGS"]:
				if not result.has(setting):
					result.append(setting)
		script = script.get_base_script()
	return result


func _on_node_added(node : Node) -> void:
	if _root != null and _root.is_ancestor_of(node):
		_strip(node)


func _strip(node : Node) -> void:
	for setting : StringName in debug_settings_of(node):
		if not setting in node:
			push_warning("DebugRemover: %s lists debug setting '%s' but has no such property" % [node.get_path(), setting])
		elif node.get(setting) == true:
			node.set(setting, false)
			print("DebugRemover: turned off %s on %s" % [setting, _root.get_path_to(node) if _root.is_ancestor_of(node) or node == _root else node.get_path()])
