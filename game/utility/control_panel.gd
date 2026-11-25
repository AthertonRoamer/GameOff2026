@tool
class_name ControlPanel
extends StaticBody2D

##A utility room's control console, seen from above: a long steel desk with three keyboards, button banks and two thin monitors along the back, a detailed picture
##rendered like the walls (a height map from above, see EnvConsole and art/console.png). The panel lights glow over it, drawn here. It is solid, glows a little in the dark, and is an interactable (see PlayerInteractor): in reach, E
##opens its `screen`. Only one player can be at a console at a time: UtilityConsoles lets the lobby decide who (see claim), and a console somebody is using
##says so in its prompt and has its last light red.
##It is a scene (control_panel.tscn) with its collision shape and screen light as real nodes, so size, light and reach are edited in the editor, and
##the drawing is a tool script, so the console shows there too. The picture has the cabinet and the dark glass; what happens on the glass (the floor plan,
##the lights that pulse) is drawn over it here. A console for a particular job is an inherited scene of it that sets `title`, `function` and `screen_scene`
##(door_control_panel.tscn). UtilityConsoles places one in each utility room and gives it its screen on a canvas layer.
##The console faces down the screen (the operator stands below it). Sizes are in world pixels, 44 per metre.

const ART : Texture2D = preload("res://game/environment/art/console.png")
const ART_SCALE : float = 44.0 / EnvConsole.PPM #the picture is drawn at 352 px per metre, the world is 44

@export var title : String = "Console"
@export var function : String = "" #the utility room function it works, like "doors" (what FacilityControl and the lobby check)
@export var screen_scene : PackedScene #what using the console opens: a full-screen Control with open(player), close() and a `closed` signal
@export var reach_m : float = 1.2 #how close the player has to be, from the middle of the console

@export_group("Screen")
@export var screen_line : Color = Palette.ITEM :
	set(value):
		screen_line = value
		queue_redraw()
@export var amber : Color = Palette.BACKUP :
	set(value):
		amber = value
		queue_redraw()
@export var red : Color = Palette.ALARM :
	set(value):
		red = value
		queue_redraw()
@export var green : Color = Palette.OK :
	set(value):
		green = value
		queue_redraw()

var screen : Control #the opened screen's instance, set by whoever places the console (UtilityConsoles)
var consoles : UtilityConsoles #the one that decides who is at the console, set by it
var occupant : int = 0 #the peer at the console, 0 when nobody is. Kept up to date on every peer by UtilityConsoles

var _time : float = 0.0

@onready var _light : PointLight2D = $Light


func _ready() -> void:
	LightLayers.make_heightless(_light) #the screen's glow lights furniture of every height (see LightLayers)
	if Engine.is_editor_hint():
		return
	add_to_group(PlayerInteractor.GROUP)


func _process(delta : float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	_light.energy = 0.5 + 0.06 * sin(_time * 2.3) #a faint flicker, like a screen
	queue_redraw()


##Close enough, and nothing solid (a wall or a closed door) in between: a console on the other side of a wall cannot be used.
func is_in_reach(world_position : Vector2, slack : float = 1.0) -> bool:
	if global_position.distance_to(world_position) > reach_m * 44.0 * slack:
		return false
	if not is_inside_tree():
		return true
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(world_position, global_position, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


##Is somebody else at the console (as this peer knows it)?
func is_in_use_by_other() -> bool:
	return occupant != 0 and occupant != multiplayer.get_unique_id()


func get_prompt() -> String:
	if is_in_use_by_other():
		return "The %s panel is in use" % title.to_lower()
	return "E   use the %s panel" % title.to_lower()


##Opens the console's screen for this player and returns it, so the interactor holds the player here until it closes. The lobby is asked to give the player the
##console; the screen opens at once, and closes again if the lobby says somebody was there first (refused).
func interact(player : Player) -> Control:
	if screen == null or is_in_use_by_other():
		return null
	if consoles != null:
		consoles.claim(self)
		screen.closed.connect(consoles.release.bind(self), CONNECT_ONE_SHOT)
	screen.open(player)
	return screen


##The lobby did not give the player the console: somebody else was at it first.
func refused() -> void:
	if screen != null and screen.visible:
		screen.close()


func _draw() -> void:
	draw_texture_rect(ART, Rect2(-ART.get_size() * ART_SCALE / 2.0, ART.get_size() * ART_SCALE), false)
	var metre : float = 44.0
	var pulse : float = 1.0 if Engine.is_editor_hint() else 0.8 + 0.2 * sin(_time * 3.0)
	for at : Vector2 in EnvConsole.LEDS: #the panel lights: dull red, with a little glow that breathes
		_glow(at * metre, red, 0.55 * pulse, 2.6)
	for i in EnvConsole.INDICATORS.size(): #the three on the back panel: red, red and a green that goes red while somebody is at the console
		var colour : Color = red if i < 2 or occupant != 0 else green
		var at : Vector2 = EnvConsole.INDICATORS[i] * metre
		draw_rect(Rect2(at - Vector2(0.62, 0.52), Vector2(1.24, 1.04)), Color(colour, 0.9 * pulse))
		_glow(at, colour, 0.5 * pulse, 2.4)
	for face : Rect2 in EnvConsole.MONITOR_FACES: #a faint cool light along the monitors' glass
		draw_rect(Rect2(face.position * metre, face.size * metre), Color(screen_line, 0.3 * pulse))
		draw_rect(Rect2(face.position * metre + Vector2(0.0, 0.5), Vector2(face.size.x * metre, 1.6)), Color(screen_line, 0.07 * pulse))


## A soft glow: a few circles, fainter the wider they are.
func _glow(at : Vector2, colour : Color, strength : float, radius : float) -> void:
	for step in 3:
		var k : float = 1.0 - step / 3.0
		draw_circle(at, radius * k, Color(colour, strength * 0.18 * (1.0 - k + 0.4)))
	draw_circle(at, radius * 0.22, Color(colour.lightened(0.25), strength))
