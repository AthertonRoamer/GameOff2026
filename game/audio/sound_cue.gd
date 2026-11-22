class_name SoundCue
extends Control

##The subtle marker for a sound: a short arc round the middle of the screen, on the side the sound seems to come from, that fades away. Louder sounds are brighter.
##Sounds from the same direction share one arc. Everything to tweak is exported. Part of the HUD (game/player_hud/player_hud.tscn).

@export_range(40.0, 500.0, 1.0, "suffix:px") var radius : float = 170.0 ## from the middle of the screen
@export_range(5.0, 90.0, 1.0, "suffix:°") var arc_degrees : float = 28.0
@export_range(1.0, 20.0, 0.5, "suffix:px") var width : float = 5.0
@export_range(0.2, 3.0, 0.05, "suffix:s") var lifetime : float = 0.9
@export_range(0.0, 0.5, 0.01, "suffix:s") var fade_in : float = 0.08 ## the arc eases in rather than popping on
@export var color : Color = Color(0.949, 0.7098, 0.2667, 1.0) ## the amber of the palette
@export_range(0.0, 1.0, 0.05) var brightness : float = 1.0 ## the most opaque the arc gets
@export_range(1.0, 4.0, 0.1) var strength_boost : float = 2.3 ## quiet sounds are lifted by this much, so a distant step is still visible
@export_range(1.0, 60.0, 1.0, "suffix:°") var merge_degrees : float = 16.0

const SEGMENTS : int = 24 #the arc is drawn in this many pieces, each with its own brightness

var _pings : Array[Dictionary] = [] #{angle, strength, age}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


##A sound from this direction (world direction from the player), with this strength 0 to 1.
func ping(direction : Vector2, strength : float) -> void:
	var angle : float = direction.angle()
	for p : Dictionary in _pings:
		if absf(angle_difference(p["angle"], angle)) < deg_to_rad(merge_degrees):
			p["age"] = 0.0
			p["strength"] = maxf(p["strength"] * 0.6, strength) #a repeat refreshes the arc rather than stacking
			return
	_pings.append({"angle": angle, "strength": strength, "age": 0.0})
	set_process(true)


func _process(delta : float) -> void:
	for p : Dictionary in _pings:
		p["age"] += delta
	_pings = _pings.filter(func(p : Dictionary) -> bool: return p["age"] < lifetime)
	if _pings.is_empty():
		set_process(false)
	queue_redraw()


##Each arc is a soft stroke: brightest in the middle and tapering to nothing at both ends, a wide faint glow under a narrower core, easing in and out over its life.
func _draw() -> void:
	var middle : Vector2 = size / 2.0
	var half : float = deg_to_rad(arc_degrees) / 2.0
	for p : Dictionary in _pings:
		var t : float = p["age"] / lifetime
		var life : float = smoothstep(0.0, fade_in, p["age"]) * (1.0 - smoothstep(0.0, 1.0, t))
		var alpha : float = brightness * clampf(p["strength"] * strength_boost, 0.0, 1.0) * life
		var points : PackedVector2Array = PackedVector2Array()
		var core : PackedColorArray = PackedColorArray()
		var glow : PackedColorArray = PackedColorArray()
		for i in SEGMENTS + 1:
			var along : float = float(i) / SEGMENTS
			var taper : float = pow(sin(PI * along), 0.7)
			points.append(middle + Vector2.from_angle(p["angle"] + lerpf(-half, half, along)) * radius)
			core.append(Color(color, alpha * taper))
			glow.append(Color(color, alpha * taper * 0.3))
		draw_polyline_colors(points, glow, width * 3.5, true)
		draw_polyline_colors(points, core, width, true)
