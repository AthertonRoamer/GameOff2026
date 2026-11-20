class_name EnvConsole
extends RefCounted

## The control console picture: a long steel desk seen from above, drawn like the walls and gates (a height map shaded by the sprite kit's light, see EnvSmooth) but
## in much more detail, at 352 px per metre: brushed and mottled steel, a sloped front edge, three keyboards of real keys, button banks, panel lights and, along
## the back, two thin dark monitors that throw a soft shadow on the desk. The desk faces down the picture (the operator stands below it).
## Everything is a "slab": a rectangle with a height, rounded edges (a fillet), a colour and, for a ramp, a slope. A pixel is shaded by the slab on top of it
## and the slabs that stick up are inked round the edge. The lights are dim here: the game lights them (ControlPanel draws their glow), so they can pulse.
## Bake it with env_render.gd (--only=console).

const PPM : float = 352.0
const SIZE_PX : Vector2i = Vector2i(568, 280) #the desk (62 x 26 world pixels, 1.41 x 0.59 m) and 0.1 m all round for its shadow
const HALF : Vector2 = Vector2(31.0, 13.0) / 44.0 #half the desk, in metres
const INK : float = 2.0 / PPM #the outline, two picture pixels

const STEEL : Color = Color("#3d4757")
const STEEL_DARK : Color = Color("#323a49")
const PANEL : Color = Color("#454f61")
const BAY : Color = Color("#13171e")
const KEY : Color = Color("#2b313c")
const KEY_LIGHT : Color = Color("#5b6574")
const GROOVE : Color = Color("#161a21")
const MONITOR : Color = Color("#101318")
const GLASS : Color = Color("#1c2a31")
const LED_OFF_RED : Color = Color("#6e2a2c")
const LED_OFF_GREEN : Color = Color("#24523a")

const TOP : float = 0.5 #the desk's top, in metres
const SHADOW_SHIFT : Vector2 = Vector2(0.03, 0.04)
const MONITOR_SHADOW_SHIFT : Vector2 = Vector2(0.05, 0.08)

## Where the lights are (metres from the middle of the desk, v down): the game draws their glow. Red panel lights, and the three indicators on the back panel.
const LEDS : Array[Vector2] = [Vector2(-0.34, 0.03), Vector2(-0.30, 0.03), Vector2(-0.26, 0.03), Vector2(0.26, 0.03), Vector2(0.30, 0.03), Vector2(0.34, 0.03)]
const INDICATORS : Array[Vector2] = [Vector2(-0.12, -0.24), Vector2(-0.075, -0.24), Vector2(-0.03, -0.24)]
## The two monitors' glass edges, as rectangles (metres): the game draws a faint glow along them.
const MONITOR_FACES : Array[Rect2] = [Rect2(-0.56, -0.247, 0.40, 0.01), Rect2(0.16, -0.247, 0.40, 0.01)]


class Slab:
	var u0 : float
	var v0 : float
	var u1 : float
	var v1 : float
	var base : float
	var height : float
	var fillet : float
	var color : Color
	var slope : float #how much the top falls per metre towards the bottom of the picture (a ramp)
	var steel : bool #brushed and mottled like the desk
	var ink : float #how thick its outline is, against the usual (the keys and buttons are small, and a full outline would swallow them)
	func _init(rect : Rect2, p_base : float, p_height : float, p_fillet : float, p_color : Color, p_slope : float = 0.0, p_steel : bool = false, p_ink : float = 1.0) -> void:
		u0 = rect.position.x
		v0 = rect.position.y
		u1 = rect.end.x
		v1 = rect.end.y
		base = p_base
		height = p_height
		fillet = p_fillet
		color = p_color
		slope = p_slope
		steel = p_steel
		ink = p_ink


static var _mottle : FastNoiseLite
static var _grain : FastNoiseLite


static func render() -> Image:
	_prepare_noise()
	var image : Image = Image.create(SIZE_PX.x, SIZE_PX.y, false, Image.FORMAT_RGBA8)
	var desk : Array[Slab] = _desk()
	var monitors : Array[Slab] = _monitors()
	var desk_grid : Dictionary = _grid(desk)
	var monitor_grid : Dictionary = _grid(monitors)
	var hx : float = HALF.x
	var hy : float = HALF.y
	for py in SIZE_PX.y:
		for px in SIZE_PX.x:
			var p : Vector2 = Vector2((px + 0.5) / PPM - SIZE_PX.x / (2.0 * PPM), (py + 0.5) / PPM - SIZE_PX.y / (2.0 * PPM))
			var ds : float = _inside(p - SHADOW_SHIFT, -hx, -hy, hx, hy)
			var color : Color = Color(0, 0, 0, 0.5 * smoothstep(-0.05, 0.03, ds)) #the desk's own shadow on the floor
			color = _paint(color, p, desk, desk_grid)
			if color.a > 0.5: #the monitors shade the desk behind and below them
				var shade : float = 0.0
				for m : Slab in monitors:
					shade = maxf(shade, smoothstep(-0.02, 0.03, _inside(p - MONITOR_SHADOW_SHIFT, m.u0, m.v0, m.u1, m.v1)))
				var k : float = 1.0 - 0.5 * shade
				color = Color(color.r * k, color.g * k, color.b * k, color.a)
			color = _paint(color, p, monitors, monitor_grid)
			image.set_pixel(px, py, color)
	return image


## The desk, back to front.
static func _desk() -> Array[Slab]:
	var hx : float = HALF.x
	var hy : float = HALF.y
	var slabs : Array[Slab] = []
	slabs.append(Slab.new(Rect2(-hx, -hy, hx * 2.0, hy * 2.0), 0.0, TOP, 0.045, STEEL, 0.0, true)) #the top
	slabs.append(Slab.new(Rect2(-hx + 0.012, 0.19, hx * 2.0 - 0.024, hy - 0.19 - 0.012), 0.0, TOP, 0.012, STEEL_DARK, -0.6, true)) #the front edge slopes away
	slabs.append(Slab.new(Rect2(-0.685, -0.283, 1.37, 0.135), TOP, 0.025, 0.02, PANEL, 0.0, true)) #the raised panel along the back
	for x : float in INDICATORS.map(func(v : Vector2) -> float: return v.x): #three lights in square bezels (red, red, green)
		slabs.append(Slab.new(Rect2(x - 0.021, -0.262, 0.042, 0.04), TOP + 0.025, 0.006, 0.006, GROOVE, 0.0, false, 0.6))
	for i in 3:
		slabs.append(Slab.new(Rect2(INDICATORS[i].x - 0.014, -0.254, 0.028, 0.024), TOP + 0.031, 0.006, 0.004, LED_OFF_GREEN if i == 2 else LED_OFF_RED, 0.0, false, 0.5))
	_button_bank(slabs, Vector2(0.13, -0.255), 2, 9, Vector2(0.026, 0.026), Vector2(0.019, 0.016)) #switches on the back panel
	_button_bank(slabs, Vector2(-0.58, -0.255), 2, 6, Vector2(0.026, 0.026), Vector2(0.019, 0.016))
	_keyboard(slabs, Rect2(-0.67, -0.115, 0.27, 0.178), 11, 6) #left
	_keyboard(slabs, Rect2(-0.20, -0.115, 0.40, 0.178), 16, 6) #middle
	_keyboard(slabs, Rect2(0.40, -0.115, 0.27, 0.178), 11, 6) #right
	for side in [-1.0, 1.0]: #between the keyboards: a bank of small buttons and three panel lights
		_button_bank(slabs, Vector2(side * 0.30 - 0.065, -0.1), 3, 5, Vector2(0.026, 0.024), Vector2(0.019, 0.015))
		for i in 3:
			var at : Vector2 = LEDS[i if side < 0.0 else 3 + i]
			slabs.append(Slab.new(Rect2(at.x - 0.016, at.y - 0.016, 0.032, 0.032), TOP, 0.008, 0.016, GROOVE, 0.0, false, 0.5)) #(a ring)
			slabs.append(Slab.new(Rect2(at.x - 0.011, at.y - 0.011, 0.022, 0.022), TOP + 0.008, 0.008, 0.011, LED_OFF_RED, 0.0, false, 0.5))
	for side in [-1.0, 1.0]: #vents on the sloped front
		for i in 7:
			slabs.append(Slab.new(Rect2(side * 0.5 - 0.09 + i * 0.028, 0.225, 0.014, 0.03), 0.0, TOP - 0.07, 0.004, GROOVE))
	return slabs


## The two thin monitors standing along the back: a slim dark case, the glass on its front, a small light on the bezel.
static func _monitors() -> Array[Slab]:
	var slabs : Array[Slab] = []
	for x0 : float in [-0.57, 0.15]:
		slabs.append(Slab.new(Rect2(x0, -0.287, 0.42, 0.052), TOP, 0.56, 0.014, MONITOR))
		slabs.append(Slab.new(Rect2(x0 + 0.014, -0.247, 0.392, 0.01), TOP, 0.56, 0.004, GLASS))
		slabs.append(Slab.new(Rect2(x0 + 0.385, -0.2815, 0.012, 0.012), TOP + 0.56, 0.004, 0.006, LED_OFF_GREEN))
	return slabs


## A keyboard in a dark bay: rows x columns of keys with a long space bar at the front.
static func _keyboard(slabs : Array[Slab], bay : Rect2, columns : int, rows : int) -> void:
	slabs.append(Slab.new(bay, TOP, -0.012, 0.01, BAY))
	var pitch : Vector2 = Vector2(bay.size.x / columns, bay.size.y / rows)
	for row in rows:
		for column in columns:
			var span : int = 1
			if row == rows - 1 and columns >= 14: #the space bar
				if column == 4:
					span = 8
				elif column > 4 and column < 12:
					continue
			var rect : Rect2 = Rect2(bay.position.x + column * pitch.x + pitch.x * 0.13, bay.position.y + row * pitch.y + pitch.y * 0.13, pitch.x * span - pitch.x * 0.26, pitch.y * 0.74)
			slabs.append(Slab.new(rect, TOP - 0.012, 0.016, 0.004, KEY_LIGHT if (row + column) % 7 == 3 else KEY, 0.0, false, 0.35))


## A bank of small square buttons.
static func _button_bank(slabs : Array[Slab], at : Vector2, rows : int, columns : int, pitch : Vector2, size : Vector2) -> void:
	for row in rows:
		for column in columns:
			slabs.append(Slab.new(Rect2(at.x + column * pitch.x, at.y + row * pitch.y, size.x, size.y), TOP + 0.02, 0.012, 0.004, KEY_LIGHT, 0.0, false, 0.45))


## A lookup of which slabs can touch each 4 cm square of the picture, so a pixel only tests the few that are near it.
static func _grid(slabs : Array[Slab]) -> Dictionary:
	var grid : Dictionary = {}
	var cell : float = 0.04
	var margin : float = INK * 2.0
	for i in slabs.size():
		var s : Slab = slabs[i]
		for cx in range(floori((s.u0 - margin) / cell), floori((s.u1 + margin) / cell) + 1):
			for cy in range(floori((s.v0 - margin) / cell), floori((s.v1 + margin) / cell) + 1):
				var key : Vector2i = Vector2i(cx, cy)
				if not grid.has(key):
					grid[key] = []
				grid[key].append(i)
	return grid


## `color` with the slabs near p painted over it, in order.
static func _paint(color : Color, p : Vector2, slabs : Array[Slab], grid : Dictionary) -> Color:
	var cell : Vector2i = Vector2i(floori(p.x / 0.04), floori(p.y / 0.04))
	if not grid.has(cell):
		return color
	var e : float = 0.5 / PPM
	var near : Array = grid[cell]
	var first : int = 0
	for n in range(near.size() - 1, -1, -1): #a slab that covers the pixel completely hides the ones under it: start there
		var t : Slab = slabs[near[n]]
		if _inside(p, t.u0, t.v0, t.u1, t.v1) >= 1.5 / PPM:
			first = n
			break
	for n in range(first, near.size()):
		var s : Slab = slabs[near[n]]
		var d : float = _inside(p, s.u0, s.v0, s.u1, s.v1)
		var width : float = INK * s.ink
		var ink : float = clampf((width - d) * PPM + 0.5, 0.0, 1.0) if d > -width else 0.0
		var inside : float = clampf(d * PPM + 0.5, 0.0, 1.0)
		if inside <= 0.0 and ink <= 0.0:
			continue
		var normal : Vector3 = Vector3.UP
		if s.slope != 0.0 or d - INK < s.fillet + e: #only a ramp and the rounded edges are not flat
			normal = Vector3(-(_height(p + Vector2(e, 0), s) - _height(p - Vector2(e, 0), s)) / (2.0 * e), 1.0,
				-(_height(p + Vector2(0, e), s) - _height(p - Vector2(0, e), s)) / (2.0 * e)).normalized()
		var base : Color = s.color
		if s.steel:
			var k : float = 1.0 + 0.07 * _mottle.get_noise_2d(p.x * 100.0, p.y * 100.0) + 0.04 * _grain.get_noise_2d(p.x * 40.0, p.y * 900.0) #mottled, with a fine brushed grain
			base = Color(minf(base.r * k, 1.0), minf(base.g * k, 1.0), minf(base.b * k, 1.0))
		var surface : Color = EnvSmooth.shade(base, normal)
		var painted : Color = surface.lerp(EnvSmooth.INK_COLOR, clampf((width - d) * PPM + 0.5, 0.0, 1.0))
		var weight : float = maxf(inside, ink)
		color = Color(color.r * (1.0 - weight) + painted.r * weight, color.g * (1.0 - weight) + painted.g * weight, color.b * (1.0 - weight) + painted.b * weight,
			color.a * (1.0 - weight) + weight)
	return color


## The height of a slab's top at q: flat, rounded off over its last `fillet` towards the edge, and tilted if it is a ramp.
static func _height(q : Vector2, s : Slab) -> float:
	var depth : float = maxf(_inside(q, s.u0, s.v0, s.u1, s.v1) - INK, 0.0)
	return s.base + s.height + s.slope * (q.y - s.v0) - EnvSmooth._fillet_drop(depth, s.fillet)


static func _inside(p : Vector2, u0 : float, v0 : float, u1 : float, v1 : float) -> float:
	return minf(minf(p.x - u0, u1 - p.x), minf(p.y - v0, v1 - p.y))


static func _prepare_noise() -> void:
	if _mottle != null:
		return
	_mottle = FastNoiseLite.new()
	_mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mottle.seed = 7
	_grain = FastNoiseLite.new()
	_grain.noise_type = FastNoiseLite.TYPE_PERLIN
	_grain.seed = 11
