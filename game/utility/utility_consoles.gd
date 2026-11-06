class_name UtilityConsoles
extends Node

##Puts a control console in every utility room of the facility whose `function` (from facility_layout.json) has an entry in CONSOLES, and builds
##the screen each console opens on a canvas layer of its own. A new kind of console is one more screen script and one more entry here.
##Call build() once the map is built. The consoles are interactables (see PlayerInteractor); what their screens change goes through `control`.

##function -> what its console is: the panel scene (which knows its title and the screen it opens, see control_panel.tscn) and where the panel stands,
##from the top left of the room's first rect (in world pixels: against the north wall, clear of the room's door).
const CONSOLES : Dictionary = {
	"doors": {"panel": preload("res://game/utility/door_control_panel.tscn"), "offset": Vector2(62.0, 22.0)},
}
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
	for room_id : String in facility.rooms_of_kind("utility"):
		var function : String = facility.rooms[room_id]["function"]
		if CONSOLES.has(function):
			_add_console(room_id, function, CONSOLES[function])


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


func _add_console(room_id : String, function : String, spec : Dictionary) -> void:
	var room : Rect2 = facility.room_rects_px(room_id)[0]
	var panel : ControlPanel = (spec["panel"] as PackedScene).instantiate()
	panel.name = "%sPanel" % panel.title.to_pascal_case()
	panel.position = room.position + spec["offset"]
	var screen : Control = panel.screen_scene.instantiate()
	screen.name = "%sScreen" % panel.title.to_pascal_case()
	screen.set("facility", facility)
	screen.set("control", control)
	_screen_layer.add_child(screen)
	panel.screen = screen
	facility.props_node.add_child(panel)
	panels.append(panel)