class_name UtilityConsoles
extends Node

##Gives every control console in the facility its screen. The consoles are ControlPanel scenes placed in the map scene, under its Props node (the Door
##Control room has one: drag more in from game/utility/ and set their `title`, `function` and `screen_scene`). build() makes each console's screen from
##its screen_scene, on a canvas layer of its own, and hands it the map and the facility's control. A new kind of console is a new screen scene and an
##inherited control_panel.tscn that points at it; nothing needs registering here.
##Call build() once the map is built. The consoles are interactables (see PlayerInteractor); what their screens change goes through `control`.

const SCREEN_LAYER : int = 20

@export var facility : FacilityMap
@export var control : FacilityControl

var panels : Array[ControlPanel] = []
var _screen_layer : CanvasLayer


func build() -> void:
	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "Screens"
	_screen_layer.layer = SCREEN_LAYER
	add_child(_screen_layer)
	for node : Node in _descendants(facility.props_node):
		if node is ControlPanel:
			_add_console(node)


##The first console that works this function, or null.
func panel_for(function : String) -> ControlPanel:
	for panel in panels:
		if panel.function == function:
			return panel
	return null


##Is this position at a console that works this function? The lobby uses it to check requests, with some slack because the lobby's view of a
##player can be a few ticks behind what the player saw when they clicked.
func is_at_console(function : String, world_position : Vector2, slack : float = 1.0) -> bool:
	for panel in panels:
		if panel.function == function and panel.is_in_reach(world_position, slack):
			return true
	return false


func _add_console(panel : ControlPanel) -> void:
	if panel.screen_scene == null:
		push_warning("%s has no screen_scene, so using it opens nothing" % panel.get_path())
		panels.append(panel)
		return
	var screen : Control = panel.screen_scene.instantiate()
	screen.name = "%sScreen" % panel.name
	screen.set("facility", facility)
	screen.set("control", control)
	_screen_layer.add_child(screen)
	panel.screen = screen
	panels.append(panel)


func _descendants(node : Node) -> Array[Node]:
	var result : Array[Node] = []
	for child : Node in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result