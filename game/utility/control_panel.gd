class_name ControlPanel
extends StaticBody2D

##A utility room's control console, seen from above: a wall-height console with a lit screen, drawn in code in the game's cel style (flat tones,
##hard edges, ink outline). It is solid, glows a little in the dark, and knows whether a player is close enough to use it. Using it is the
##game's job: the playground calls is_in_reach() and opens the screen that goes with the console (see DoorMapScreen).
##The console faces down the screen (the operator stands below it). Sizes are in world pixels, 44 per metre.

const INK : Color = Color("#06080c")
const STEEL : Color = Color("#2a313d")
const STEEL_LIT : Color = Color("#4a5568")
const STEEL_SHADE : Color = Color("#1a1f27")
const SCREEN_DARK : Color = Color("#0a1118")
const SCREEN_LINE : Color = Color("#6fd3e8")
const AMBER : Color = Color("#f2b544")
const RED : Color = Color("#e5484d")
const GREEN : Color = Color("#4be38a")

@export var title : String = "Door control"
@export var reach_m : float = 1.7 #how close the player has to be, from the middle of the console
@export var screen_light : Color = SCREEN_LINE

static var _glow_texture : GradientTexture2D

var _light : PointLight2D
var _time : float = 0.0


func _ready() -> void:
	collision_layer = 1 #solid for players, not a wall for bullets
	collision_mask = 0
	var shape : CollisionShape2D = CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	(shape.shape as RectangleShape2D).size = Vector2(62.0, 26.0)
	add_child(shape)
	_light = PointLight2D.new()
	_light.texture = _get_glow_texture()
	_light.texture_scale = 2.6 * 44.0 * 2.0 / _light.texture.get_width()
	_light.color = screen_light
	_light.energy = 0.55
	_light.position = Vector2(0, 20)
	_light.shadow_enabled = true
	add_child(_light)


func _process(delta : float) -> void:
	_time += delta
	_light.energy = 0.5 + 0.06 * sin(_time * 2.3) #a faint flicker, like a screen
	queue_redraw()


func is_in_reach(world_position : Vector2) -> bool:
	return global_position.distance_to(world_position) <= reach_m * 44.0


func _draw() -> void:
	var body : Rect2 = Rect2(-31.0, -13.0, 62.0, 26.0)
	var shape : PackedVector2Array = _rounded_rect(body, 5.0)
	draw_colored_polygon(_rounded_rect(body.grow(1.5), 6.0), INK)
	draw_colored_polygon(shape, STEEL)
	_draw_band(shape, Rect2(-31.0, -13.0, 62.0, 4.0), STEEL_LIT) #the top edge catches the light
	_draw_band(shape, Rect2(-31.0, -13.0, 4.0, 26.0), STEEL_LIT.darkened(0.25))
	_draw_band(shape, Rect2(27.0, -13.0, 4.0, 26.0), STEEL_SHADE)
	_draw_band(shape, Rect2(-31.0, 9.0, 62.0, 4.0), STEEL_SHADE)
	#the sloped front: the screen, in a dark frame
	var frame : Rect2 = Rect2(-23.0, -2.0, 46.0, 13.0)
	draw_colored_polygon(_rounded_rect(frame.grow(1.2), 3.0), INK)
	draw_colored_polygon(_rounded_rect(frame, 2.5), SCREEN_DARK)
	var pulse : float = 0.75 + 0.25 * sin(_time * 3.0)
	var line : Color = Color(SCREEN_LINE.r, SCREEN_LINE.g, SCREEN_LINE.b, 0.9)
	#a tiny floor plan on the screen
	draw_rect(Rect2(-19.0, 0.5, 14.0, 8.0), Color(line, 0.35), false, 1.0)
	draw_rect(Rect2(-3.0, 0.5, 10.0, 8.0), Color(line, 0.35), false, 1.0)
	draw_rect(Rect2(9.0, 0.5, 11.0, 8.0), Color(line, 0.35), false, 1.0)
	draw_rect(Rect2(-6.0, 3.0, 3.0, 2.0), Color(GREEN, pulse))
	draw_rect(Rect2(7.5, 3.0, 3.0, 2.0), Color(RED, pulse))
	draw_rect(Rect2(20.0, 3.0, 2.0, 2.0), Color(AMBER, pulse))
	#a row of buttons along the back
	for i in 6:
		var colour : Color = [GREEN, AMBER, RED][i % 3]
		draw_rect(Rect2(-20.0 + i * 7.5, -9.0, 4.0, 3.0), INK)
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


static func _get_glow_texture() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient : Gradient = Gradient.new()
		gradient.colors = PackedColorArray([Color.WHITE, Color.BLACK])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 128
		_glow_texture.height = 128
	return _glow_texture
