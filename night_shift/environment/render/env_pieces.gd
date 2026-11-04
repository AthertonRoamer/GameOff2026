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


static func floor_tile(kind : String, variant : int) -> Node3D:
	var root : Node3D = Node3D.new()
	var h : float = CELL / 2.0
	var full : Rect2 = Rect2(-h, -h, CELL, CELL)
	var r : RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash(kind) + variant * 7919
	match kind:
		"room": #steel panels
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor")))
			_panels(root, "tile", 0.015, 0.03, false)
		"corridor": #concrete slabs
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("deep")))
			_panels(root, "floor", 0.01, 0.025, false)
		"utility": #plain plate with a few raised diamonds
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("tile")))
			_panels(root, "tile", 0.015, 0.03, false)
			var flip : float = 1.0 if variant % 2 == 0 else -1.0
			for p : Vector2 in PackedVector2Array([Vector2(-0.1 * flip, -0.1), Vector2(0.1 * flip, 0.1)]):
				root.add_child(EnvMesh.stud(p, 0.03, 0.05, 0.022, 0.016, EnvMesh.cel("wall"), 4))
		"vault": #dark steel
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("shadow")))
			_panels(root, "deep", 0.012, 0.03, false)
		"outdoor": #asphalt, a few darker and lighter patches
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("deep")))
			for i in 3:
				var rad : float = r.randf_range(0.04, 0.07)
				root.add_child(EnvMesh.stud(Vector2(r.randf_range(-0.16, 0.16), r.randf_range(-0.16, 0.16)), 0.0, rad, rad * 0.6,
					0.012, EnvMesh.cel("floor"), 8))
		"vent": #floor grille
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("shadow")))
			for i in 4:
				root.add_child(EnvMesh.plate(Rect2(-0.2, -0.19 + i * 0.1, 0.4, 0.05), 0.0, 0.03, EnvMesh.cel("wall")))
	return root


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


##A wall console, two cells wide and one deep: a desk with a screen and a keyboard.
static func console() -> Node3D:
	var root : Node3D = Node3D.new()
	root.add_child(EnvMesh.plate(Rect2(-0.47, -0.21, 0.94, 0.42), 0.0, 0.30, EnvMesh.cel("wall"), 0.03))
	root.add_child(EnvMesh.plate(Rect2(-0.44, -0.18, 0.88, 0.36), 0.30, 0.03, EnvMesh.cel("wall_top"), 0.02))
	root.add_child(EnvMesh.plate(Rect2(-0.30, -0.17, 0.60, 0.12), 0.33, 0.09, EnvMesh.cel("shadow"), 0.03))
	root.add_child(EnvMesh.quad(Rect2(-0.27, -0.148, 0.54, 0.075), 0.425, EnvMesh.flat("item")))
	root.add_child(EnvMesh.plate(Rect2(-0.22, 0.02, 0.44, 0.11), 0.33, 0.025, EnvMesh.cel("wall"), 0.012))
	return root


##One framed floor panel, or two half panels side by side when split.
static func _panels(root : Node3D, color : String, margin : float, height : float, split : bool) -> void:
	var h : float = CELL / 2.0
	var inner : float = CELL - margin * 2.0
	if split:
		var pw : float = (inner - 0.012) / 2.0
		root.add_child(EnvMesh.plate(Rect2(-h + margin, -h + margin, pw, inner), 0.0, height, EnvMesh.cel(color)))
		root.add_child(EnvMesh.plate(Rect2(0.006, -h + margin, pw, inner), 0.0, height, EnvMesh.cel(color)))
	else:
		root.add_child(EnvMesh.plate(Rect2(-h + margin, -h + margin, inner, inner), 0.0, height, EnvMesh.cel(color)))
