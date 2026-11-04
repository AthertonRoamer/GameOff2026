class_name EnvPieces
extends RefCounted

##The environment pieces, modelled in 3D from the building blocks in EnvMesh and photographed from straight above by env_render.gd.
##A tile is half a metre (CELL). Everything is built with the picture's up at -Z and right at +X, and the cel light stays up-left,
##so a piece never has to be mirrored or turned: a vertical door is modelled as a vertical door, not a rotated horizontal one.

const CELL : float = 0.5
const INK : float = 1.0 / 176.0 #one render pixel in metres; open edges of a wall or door are pulled in by this so the ink outline fits in the tile
const WALL_TOP : float = 0.5 #the top of a wall block above the floor, metres
const CAP : float = 0.04 #thickness of the plate on top of the wall block

const NEIGHBOUR_BITS : Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)] #N, NE, E, SE, S, SW, W, NW, the bit order of the wall masks


const FLOOR_SHAPES : int = 6 #columns of the floor atlas: how a tile is cut up
const FLOOR_TONES : Array[String] = ["brown_dark", "brown", "brown_light"] #rows of the floor atlas


##The one floor of the facility: brown steel panels. shape is how the tile is cut up (0 one panel, 1 two side by side, 2 two stacked,
##3 four quarters, 4 a panel with a recessed plate, 5 a narrow and a wide panel), tone how light it is. FacilityMap mixes them so that a
##big room does not read as a grid of identical tiles.
static func floor_tile(shape : int, tone : int) -> Node3D:
	var root : Node3D = Node3D.new()
	var h : float = CELL / 2.0
	var color : String = FLOOR_TONES[tone]
	root.add_child(EnvMesh.quad(Rect2(-h, -h, CELL, CELL), 0.0, EnvMesh.cel("brown_deep"))) #the gaps between panels
	var m : float = 0.015
	var gap : float = 0.014
	var inner : float = CELL - m * 2.0
	var half : float = (inner - gap) / 2.0
	match shape:
		0:
			_panel(root, Rect2(-h + m, -h + m, inner, inner), color)
		1:
			_panel(root, Rect2(-h + m, -h + m, half, inner), color)
			_panel(root, Rect2(-h + m + half + gap, -h + m, half, inner), color)
		2:
			_panel(root, Rect2(-h + m, -h + m, inner, half), color)
			_panel(root, Rect2(-h + m, -h + m + half + gap, inner, half), color)
		3:
			for ix in 2:
				for iz in 2:
					_panel(root, Rect2(-h + m + ix * (half + gap), -h + m + iz * (half + gap), half, half), color)
		4:
			_panel(root, Rect2(-h + m, -h + m, inner, inner), color)
			root.add_child(EnvMesh.plate(Rect2(-0.12, -0.12, 0.24, 0.24), 0.03, 0.012, EnvMesh.cel(FLOOR_TONES[maxi(tone - 1, 0)] if tone > 0 else "brown_deep"), 0.012))
		5:
			var narrow : float = inner * 0.34 - gap / 2.0
			_panel(root, Rect2(-h + m, -h + m, narrow, inner), color)
			_panel(root, Rect2(-h + m + narrow + gap, -h + m, inner - narrow - gap, inner), color)
	return root


static func _panel(root : Node3D, rect : Rect2, color : String) -> void:
	root.add_child(EnvMesh.plate(rect, 0.0, 0.03, EnvMesh.cel(color), 0.03))


##One wall cell at the centre of a 3 x 3 block. mask has a bit set for each neighbour that is wall (N, NE, E, SE, S, SW, W, NW).
static func wall_tile(mask : int) -> Node3D:
	var root : Node3D = Node3D.new()
	var h : float = CELL / 2.0
	var top : float = WALL_TOP + CAP
	for i in 8: #neighbouring wall cells only matter as surfaces at the same height, so the ink does not run along a join
		if mask & (1 << i):
			var o : Vector2i = NEIGHBOUR_BITS[i]
			root.add_child(EnvMesh.quad(Rect2(o.x * CELL - h, o.y * CELL - h, CELL, CELL), top, EnvMesh.cel("wall_top")))
	var n : bool = bool(mask & 1)
	var e : bool = bool(mask & 4)
	var s : bool = bool(mask & 16)
	var w : bool = bool(mask & 64)
	#the block: pulled in by one pixel on every open edge, which is where the ink outline goes
	var x0 : float = -h + (0.0 if w else INK)
	var x1 : float = h - (0.0 if e else INK)
	var z0 : float = -h + (0.0 if n else INK)
	var z1 : float = h - (0.0 if s else INK)
	root.add_child(EnvMesh.quad(Rect2(x0, z0, x1 - x0, z1 - z0), WALL_TOP, EnvMesh.cel("wall")))
	#the cap plate: set in from the block's edge on open sides, flush on closed ones
	var ring : float = INK + 0.03
	var px0 : float = -h + (0.0 if w else ring)
	var px1 : float = h - (0.0 if e else ring)
	var pz0 : float = -h + (0.0 if n else ring)
	var pz1 : float = h - (0.0 if s else ring)
	var sides : String = ("" if n else "n") + ("" if e else "e") + ("" if s else "s") + ("" if w else "w")
	root.add_child(EnvMesh.plate(Rect2(px0, pz0, px1 - px0, pz1 - pz0), WALL_TOP, CAP, EnvMesh.cel("wall_top"), 0.03, sides))
	#inner corners: both neighbours are wall but the diagonal is open, so the rim has to turn the corner
	var patch : float = ring + 0.035
	for corner : Array in [[2, n, e, 1.0, -1.0], [8, s, e, 1.0, 1.0], [32, s, w, -1.0, 1.0], [128, n, w, -1.0, -1.0]]:
		if corner[1] and corner[2] and not (mask & int(corner[0])):
			var rx : float = h - patch if corner[3] > 0.0 else -h
			var rz : float = h - patch if corner[4] > 0.0 else -h
			root.add_child(EnvMesh.quad(Rect2(rx, rz, patch, patch), top + 0.005, EnvMesh.cel("wall")))
	return root


##A one metre sliding door in a wall. state: closed, locked or open. vertical doors sit in a vertical wall (2 cells tall).
static func door(state : String, exterior : bool, vertical : bool) -> Node3D:
	var root : Node3D = Node3D.new()
	var uv : Callable = func(u0 : float, v0 : float, u1 : float, v1 : float) -> Rect2: #u runs along the door, v across it
		return Rect2(v0, u0, v1 - v0, u1 - u0) if vertical else Rect2(u0, v0, u1 - u0, v1 - v0)
	var pt : Callable = func(u : float, v : float) -> Vector2:
		return Vector2(v, u) if vertical else Vector2(u, v)
	var half_v : float = CELL / 2.0 - INK #the long edges face the floor, so they are pulled in for the ink
	var sill : float = 0.30
	var leaf_h : float = 0.14
	var leaf_v : float = half_v - 0.025
	if state == "open":
		root.add_child(EnvMesh.quad(uv.call(-0.5, -half_v, 0.5, -half_v + 0.03), sill, EnvMesh.cel("wall")))
		root.add_child(EnvMesh.quad(uv.call(-0.5, half_v - 0.03, 0.5, half_v), sill, EnvMesh.cel("wall")))
		for side in [-1.0, 1.0]:
			var u0 : float = -0.5 if side < 0.0 else 0.5 - 0.13
			root.add_child(EnvMesh.plate(uv.call(u0, -leaf_v, u0 + 0.13, leaf_v), sill, leaf_h, EnvMesh.cel("uniform"), 0.03))
		return root
	root.add_child(EnvMesh.quad(uv.call(-0.5, -half_v, 0.5, half_v), sill, EnvMesh.cel("wall")))
	for side in [-1.0, 1.0]:
		var u0 : float = -0.5 if side < 0.0 else 0.012
		var u1 : float = -0.012 if side < 0.0 else 0.5
		root.add_child(EnvMesh.plate(uv.call(u0, -leaf_v, u1, leaf_v), sill, leaf_h, EnvMesh.cel("armor" if exterior else "uniform"), 0.03))
	var light : String = "alarm" if state == "locked" else "item"
	for side in [-1.0, 1.0]:
		var c : Vector2 = pt.call(0.045 * side, 0.0)
		root.add_child(EnvMesh.quad(Rect2(c.x - 0.016, c.y - 0.016, 0.032, 0.032), sill + leaf_h + 0.025, EnvMesh.flat(light)))
	return root
