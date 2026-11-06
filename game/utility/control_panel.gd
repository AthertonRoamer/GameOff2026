@tool
class_name ControlPanel
extends StaticBody2D

##A utility room's control console, seen from above: a wall-height console with a lit screen, drawn in the game's cel style (flat tones, hard edges,
##ink outline). It is solid, glows a little in the dark, and is an interactable (see PlayerInteractor): in reach, E opens its `screen`.
##It is a scene (control_panel.tscn) with its collision shape and screen light as real nodes, so size, light and reach are edited in the editor, and
##the drawing is a tool script, so the console shows there too. A console for a particular job is an inherited scene of it that sets `title`, `function`
##and `screen_scene` (door_control_panel.tscn). UtilityConsoles places one in each utility room and gives it its screen on a canvas layer.
##The console faces down the screen (the operator stands below it). Sizes are in world pixels, 44 per metre.

@export var title : String = "Console"
@export var function : String = "" #the utility room function it works, like "doors" (what FacilityControl and the lobby check)
@export var screen_scene : PackedScene #what using the console opens: a full-screen Control with open(player), close() and a `closed` signal
@export var reach_m : float = 1.7 #how close the player has to be, from the middle of the console

@export_group("Look")
@export var ink : Color = Color("#06080c") : set = _set_look
@export var steel : Color = Color("#2a313d") : set = _set_look
@export var steel_lit : Color = Color("#4a5568") : set = _set_look
@export var steel_shade : Color = Color("#1a1f27") : set = _set_look
@export var screen_dark : Color = Color("#0a1118") : set = _set_look
@export var screen_line : Color = Color("#6fd3e8") : set = _set_look
@export var amber : Color = Color("#f2b544") : set = _set_look
@export var red : Color = Color("#e5484d") : set = _set_look
@export var green : Color = Color("#4be38a") : set = _set_look

var screen : Control #the opened screen's instance, set by whoever places the console (UtilityConsoles)

var _time : float = 0.0

@onready var _light : PointLight2D = $Light


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(PlayerInteractor.GROUP)


func _process(delta : float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	_light.energy = 0.5 + 0.06 * sin(_time * 2.3) #a faint flicker, like a screen
	queue_redraw()


func _set_look(_value = null) -> void:
	queue_redraw()

##Close enough, and nothing solid (a wall or a closed door) in between: a console on the other side of a wall cannot be used.
func is_in_reach(world_position : Vector2, slack : float = 1.0) -> bool:
	if global_position.distance_to(world_position) > reach_m * 44.0 * slack:
		return false
	if not is_inside_tree():
		return true
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(world_position, global_position, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func get_prompt() -> String:
	return "E   use the %s panel" % title.to_lower()


##Opens the console's screen for this player and returns it, so the interactor holds the player here until it closes.
func interact(player : Player) -> Control:
	if screen == null:
		return null
	screen.open(player)
	return screen


func _draw() -> void:
	var body : Rect2 = Rect2(-31.0, -13.0, 62.0, 26.0)
	var shape : PackedVector2Array = _rounded_rect(body, 5.0)
	draw_colored_polygon(_rounded_rect(body.grow(1.5), 6.0), ink)
	draw_colored_polygon(shape, steel)
	_draw_band(shape, Rect2(-31.0, -13.0, 62.0, 4.0), steel_lit) #the top edge catches the light
	_draw_band(shape, Rect2(-31.0, -13.0, 4.0, 26.0), steel_lit.darkened(0.25))
	_draw_band(shape, Rect2(27.0, -13.0, 4.0, 26.0), steel_shade)
	_draw_band(shape, Rect2(-31.0, 9.0, 62.0, 4.0), steel_shade)
	#the sloped front: the screen, in a dark frame
	var frame : Rect2 = Rect2(-23.0, -2.0, 46.0, 13.0)
	draw_colored_polygon(_rounded_rect(frame.grow(1.2), 3.0), ink)
	draw_colored_polygon(_rounded_rect(frame, 2.5), screen_dark)
	var pulse : float = 1.0 if Engine.is_editor_hint() else 0.75 + 0.25 * sin(_time * 3.0)
	var line : Color = Color(screen_line.r, screen_line.g, screen_line.b, 0.9)
	#a tiny floor plan on the screen
	draw_rect(Rect2(-19.0, 0.5, 14.0, 8.0), Color(line, 0.35), false, 1.0)
	draw_rect(Rect2(-3.0, 0.5, 10.0, 8.0), Color(line, 0.35), false, 1.0)
	draw_rect(Rect2(9.0, 0.5, 11.0, 8.0), Color(line, 0.35), false, 1.0)
	draw_rect(Rect2(-6.0, 3.0, 3.0, 2.0), Color(green, pulse))
	draw_rect(Rect2(7.5, 3.0, 3.0, 2.0), Color(red, pulse))
	draw_rect(Rect2(20.0, 3.0, 2.0, 2.0), Color(amber, pulse))
	#a row of buttons along the back
	for i in 6:
		var colour : Color = [green, amber, red][i % 3]
		draw_rect(Rect2(-20.0 + i * 7.5, -9.0, 4.0, 3.0), ink)
		draw_rect(Rect2(-19.5 + i * 7.5, -8.5, 3.0, 2.0), Color(colour, 0.9))


func _draw_band(outline : PackedVector2Array, band : Rect2, colour : Color) -> void:
	var band_polygon : PackedVector2Array = PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)])
	for piece : PackedVector2Array in Geometry2D.intersect_polygons(outline, band_polygon):
		draw_colored_polygon(piece, colour)


static func _rounded_rect(rect : Rect2, radius : float, steps : int = 5) -> PackedVector2Array:
	var points : PackedVector2Array = PackedVector2Array()
	var corners : Array[Vector2] = [Vector2(rect.end.x - radius, rect.position.y + radius), Vector2(rect.end.x - radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.end.y - radius), Vector2(rect.position.x + radius, rect.position.y + radius)]
	for i in 4:
		for s in steps + 1:
			points.append(corners[i] + Vector2.from_angle((i - 1) * PI / 2.0 + s * PI / 2.0 / steps) * radius)
	return points
