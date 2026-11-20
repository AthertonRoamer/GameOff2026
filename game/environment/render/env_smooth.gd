class_name EnvSmooth
extends RefCounted

##The smooth environment pieces: a plain floor, smooth rounded walls and gates, and soft shadows on the floor beside the walls.
##Every piece is a height map seen from straight above (a top-down 3D picture), shaded with the character renderer's light direction (up and to the
##left of the picture) but with a smooth ramp instead of three hard bands: flat tops get the base colour, edges that turn towards the light get lighter,
##edges that turn away get darker. Walls and gates get the characters' 1 px ink outline. Nothing here has any surface detail.
##Resolution is 176 px per metre, like the cel character sheets, so one 0.25 m cell is 44 px.

const PPM : float = 176.0
const CELL : float = 0.25
const CELL_PX : int = 44
const INK : float = 1.0 / 176.0 #one pixel in metres
const WALL_HEIGHT : float = 0.5
const WALL_FILLET : float = 0.05 #how far in from the edge the rounding reaches, metres
const LIGHT : Vector3 = Vector3(-0.42, 0.80, -0.42) #x right, y up, z towards the bottom of the picture: the sprite kit's light
const NEIGHBOURS : Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)] #N, NE, E, SE, S, SW, W, NW: the bit order of the wall masks

const FLOOR_COLOR : Color = Color("#22241f") #the olive-grey of the lit look, flat
const WALL_COLOR : Color = Color("#16203a") #dark navy
const GATE_COLOR : Color = Color("#1d2a4d")
const GATE_EXTERIOR_COLOR : Color = Color("#263766")
const INK_COLOR : Color = Color("#07090c")

const SHADOW_REACH : float = 0.3 #how far a wall's shadow reaches across the floor, metres
const SHADOW_STRENGTH : float = 0.55
const AO_REACH : float = 0.12 #the soft darkening where floor meets wall
const AO_STRENGTH : float = 0.5


static func floor_tile() -> Image:
	var image : Image = Image.create(CELL_PX, CELL_PX, false, Image.FORMAT_RGBA8)
	image.fill(FLOOR_COLOR)
	return image


##One wall cell, mask says which of its 8 neighbours are wall (N, NE, E, SE, S, SW, W, NW). Open edges get the ink outline and a rounded edge.
static func wall_tile(mask : int) -> Image:
	var image : Image = Image.create(CELL_PX, CELL_PX, false, Image.FORMAT_RGBA8)
	var e : float = 0.5 / PPM
	for py in CELL_PX:
		for px in CELL_PX:
			var p : Vector2 = Vector2((px + 0.5) / PPM - CELL / 2.0, (py + 0.5) / PPM - CELL / 2.0)
			var d : float = _distance_to_open(p, mask)
			var normal : Vector3 = _normal(_wall_height(_distance_to_open(p - Vector2(e, 0), mask)), _wall_height(_distance_to_open(p + Vector2(e, 0), mask)),
				_wall_height(_distance_to_open(p - Vector2(0, e), mask)), _wall_height(_distance_to_open(p + Vector2(0, e), mask)), e)
			var surface : Color = shade(WALL_COLOR, normal)
			var ink : float = clampf((INK - d) * PPM + 0.5, 0.0, 1.0)
			image.set_pixel(px, py, surface.lerp(INK_COLOR, ink))
	return image


##Soft shadow for one floor cell, mask says which of its 8 neighbours are wall. A transparent black picture: darker where the floor meets a wall
##(soft occlusion) and in the shadow a wall throws towards the bottom right, away from the light.
static func floor_shadow(mask : int) -> Image:
	var image : Image = Image.create(CELL_PX, CELL_PX, false, Image.FORMAT_RGBA8)
	if mask == 0:
		return image
	var walls : Array[Vector2] = []
	for i in 8:
		if mask & (1 << i):
			walls.append(Vector2(NEIGHBOURS[i]) * CELL)
	var toward_light : Vector2 = Vector2(-1.0, -1.0).normalized()
	for py in CELL_PX:
		for px in CELL_PX:
			var p : Vector2 = Vector2((px + 0.5) / PPM - CELL / 2.0, (py + 0.5) / PPM - CELL / 2.0)
			var nearest : float = 1.0
			for c : Vector2 in walls:
				nearest = minf(nearest, _box_distance(p, c, CELL / 2.0))
			var ao : float = AO_STRENGTH * (1.0 - smoothstep(0.0, AO_REACH, nearest))
			#cast shadow: five rays towards the light a little apart, so the edges of a shadow are soft instead of a hard diagonal
			var cast : float = 0.0
			for spread in [-0.3, -0.15, 0.0, 0.15, 0.3]:
				var ray : Vector2 = toward_light.rotated(spread)
				var t : float = 0.015
				while t < SHADOW_REACH:
					var q : Vector2 = p + ray * t
					var inside : bool = false
					for c : Vector2 in walls:
						if absf(q.x - c.x) <= CELL / 2.0 and absf(q.y - c.y) <= CELL / 2.0:
							inside = true
							break
					if inside:
						cast += SHADOW_STRENGTH * (1.0 - t / SHADOW_REACH) / 5.0
						break
					t += 0.015			image.set_pixel(px, py, Color(0.0, 0.0, 0.0, clampf(maxf(ao, cast), 0.0, 0.7)))
	return image


##A one metre sliding gate in a wall a quarter metre thick, picture 1 m x 0.5 m (0.5 m x 1 m when vertical). state: closed, locked or open.
##Two rounded leaves that meet in the middle (none when open), a rounded post at each end with a status light, and a soft shadow.
static func gate(state : String, exterior : bool, vertical : bool) -> Image:
	var size : Vector2i = Vector2i(88, 176) if vertical else Vector2i(176, 88)
	var image : Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var leaf_color : Color = GATE_EXTERIOR_COLOR if exterior else GATE_COLOR
	var light_color : Color = Color("#e5484d") if state == "locked" else Color("#6fd3e8")
	var half_wall : float = CELL / 2.0 - INK
	#slabs: [u0, v0, u1, v1, y base, height, fillet, colour]; u runs along the gate, v across it
	var slabs : Array = [
		[-0.5, -half_wall, -0.44, half_wall, 0.0, 0.55, 0.025, WALL_COLOR],
		[0.44, -half_wall, 0.5, half_wall, 0.0, 0.55, 0.025, WALL_COLOR]]
	if state != "open":
		slabs.append([-0.435, -0.075, -0.006, 0.075, 0.02, 0.13, 0.03, leaf_color])
		slabs.append([0.006, -0.075, 0.435, 0.075, 0.02, 0.13, 0.03, leaf_color])
	var e : float = 0.5 / PPM
	for py in size.y:
		for px in size.x:
			var p : Vector2 = Vector2((px + 0.5) / PPM - size.x / (2.0 * PPM), (py + 0.5) / PPM - size.y / (2.0 * PPM))
			var color : Color = Color(0, 0, 0, 0)
			#soft shadow under the leaves, thrown towards the bottom right
			var uv : Vector2 = _uv(p, vertical)
			var shift : Vector2 = _uv(Vector2(0.03, 0.04), vertical)
			var ds : float = _rect_inside(uv - shift, -0.5, -0.11, 0.5, 0.11)
			color = Color(0, 0, 0, 0.45 * smoothstep(-0.05, 0.03, ds))
			for slab : Array in slabs:
				var d : float = _rect_inside(uv, slab[0], slab[1], slab[2], slab[3])
				var ink : float = clampf((INK - d) * PPM + 0.5, 0.0, 1.0) if d > -INK else 0.0
				var inside : float = clampf(d * PPM + 0.5, 0.0, 1.0)
				if inside <= 0.0 and ink <= 0.0:
					continue
				var s : float = maxf(d - INK, 0.0)
				var hx0 : float = _slab_height(_rect_inside(_uv(p - Vector2(e, 0), vertical), slab[0], slab[1], slab[2], slab[3]) - INK, slab)
				var hx1 : float = _slab_height(_rect_inside(_uv(p + Vector2(e, 0), vertical), slab[0], slab[1], slab[2], slab[3]) - INK, slab)
				var hz0 : float = _slab_height(_rect_inside(_uv(p - Vector2(0, e), vertical), slab[0], slab[1], slab[2], slab[3]) - INK, slab)
				var hz1 : float = _slab_height(_rect_inside(_uv(p + Vector2(0, e), vertical), slab[0], slab[1], slab[2], slab[3]) - INK, slab)
				var surface : Color = shade(slab[7], _normal(hx0, hx1, hz0, hz1, e))
				var painted : Color = surface.lerp(INK_COLOR, clampf((INK - d) * PPM + 0.5, 0.0, 1.0))
				var weight : float = maxf(inside, ink)
				color = Color(color.r * (1.0 - weight) + painted.r * weight, color.g * (1.0 - weight) + painted.g * weight,
					color.b * (1.0 - weight) + painted.b * weight, color.a * (1.0 - weight) + weight)
			#the two status lights, on top of the posts
			for side in [-1.0, 1.0]:
				var lp : Vector2 = _uv_inverse(Vector2(0.47 * side, 0.0), vertical)
				var dl : float = 0.014 - (p - lp).length()
				var lw : float = clampf(dl * PPM + 0.5, 0.0, 1.0)
				if lw > 0.0:
					color = Color(color.r * (1.0 - lw) + light_color.r * lw, color.g * (1.0 - lw) + light_color.g * lw,
						color.b * (1.0 - lw) + light_color.b * lw, maxf(color.a, lw))
			image.set_pixel(px, py, color)
	return image


##Smooth shading: a flat top (normal straight up) comes out as the base colour, a surface tilted towards the light goes towards the highlight tone,
##one tilted away towards the shadow tone. The tones are made from the base like the character renderer does (0.62 and 1.22).
static func shade(base : Color, normal : Vector3) -> Color:
	var shadow : Color = Color(base.r * 0.62, base.g * 0.62, base.b * 0.62)
	var highlight : Color = Color(base.r + (1.0 - base.r) * 0.22, base.g + (1.0 - base.g) * 0.22, base.b + (1.0 - base.b) * 0.22)
	var t : float = clampf(normal.dot(LIGHT.normalized()), 0.0, 1.0)
	if t < 0.8:
		return shadow.lerp(base, t / 0.8)
	return base.lerp(highlight, (t - 0.8) / 0.2)


static func _normal(hx0 : float, hx1 : float, hz0 : float, hz1 : float, e : float) -> Vector3:
	return Vector3(-(hx1 - hx0) / (2.0 * e), 1.0, -(hz1 - hz0) / (2.0 * e)).normalized()


##Height of a wall's top at inside distance d from the nearest open edge: flat, rounded off over the last WALL_FILLET.
static func _wall_height(d : float) -> float:
	return WALL_HEIGHT - _fillet_drop(maxf(d - INK, 0.0), WALL_FILLET)


static func _slab_height(s : float, slab : Array) -> float:
	return slab[4] + slab[5] - _fillet_drop(maxf(s, 0.0), slab[6])


##How far below the flat top a quarter round edge is, s metres in from the edge.
static func _fillet_drop(s : float, radius : float) -> float:
	if s >= radius:
		return 0.0
	return radius - sqrt(maxf(radius * radius - (radius - s) * (radius - s), 0.0))


##Distance from p to the nearest neighbour cell that is NOT wall (so how deep inside the wall mass p is), capped at one cell.
static func _distance_to_open(p : Vector2, mask : int) -> float:
	var best : float = CELL
	for i in 8:
		if not (mask & (1 << i)):
			best = minf(best, _box_distance(p, Vector2(NEIGHBOURS[i]) * CELL, CELL / 2.0))
	return best


static func _box_distance(p : Vector2, center : Vector2, half : float) -> float:
	var q : Vector2 = (p - center).abs() - Vector2(half, half)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


static func _rect_inside(uv : Vector2, u0 : float, v0 : float, u1 : float, v1 : float) -> float:
	return minf(minf(uv.x - u0, u1 - uv.x), minf(uv.y - v0, v1 - uv.y))


static func _uv(p : Vector2, vertical : bool) -> Vector2:
	return Vector2(p.y, p.x) if vertical else p


static func _uv_inverse(uv : Vector2, vertical : bool) -> Vector2:
	return Vector2(uv.y, uv.x) if vertical else uv
