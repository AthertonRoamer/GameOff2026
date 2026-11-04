class_name EnvPieces
extends RefCounted

##The environment pieces, modelled in 3D from the building blocks in EnvMesh and photographed from straight above by env_render.gd.
##A map cell is a quarter of a metre (CELL), which is also the thickness of a wall. The floor is drawn as 0.5 m slabs (SLAB) and cut into cell
##sized quarters. Everything is built with the picture's up at -Z and right at +X, and the cel light stays up-left, so a piece never has to be
##mirrored or turned: a vertical door is modelled as a vertical door, not a rotated horizontal one.

const CELL : float = 0.25
const SLAB : float = 0.5 #floor slabs are two cells square
const INK : float = 1.0 / 176.0 #one render pixel in metres; open edges of a wall are pulled in by this so the ink outline fits in the tile
const WALL_TOP : float = 0.5 #the top of a wall block above the floor, metres
const CAP : float = 0.04 #thickness of the plate on top of the wall block
const FLOOR_VARIANTS : int = 8

const NEIGHBOUR_BITS : Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)] #N, NE, E, SE, S, SW, W, NW, the bit order of the wall masks


##The floor: 0.5 m concrete slabs on dark gaps, the same everywhere. variant 0..7 adds the wear that keeps a big room from reading as copies:
##0 plain, 1 split across, 2 corner bolts, 3 grit, 4 scuffs, 5 a drain, 6 split lengthways, 7 a stain. kind "vent" is the vent grille.
static func floor_tile(kind : String, variant : int) -> Node3D:
	var root : Node3D = Node3D.new()
	var h : float = SLAB / 2.0
	var full : Rect2 = Rect2(-h, -h, SLAB, SLAB)
	var r : RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash(kind) + variant * 7919
	if kind == "vent":
		root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor_deep")))
		for i in 5:
			root.add_child(EnvMesh.plate(Rect2(-0.2, -0.2 + i * 0.085, 0.4, 0.045), 0.0, 0.03, EnvMesh.cel("floor_stud")))
		_bolts(root, 0.0, h - 0.04, "floor_stud", 0.016)
		return root
	root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor_deep")))
	var slab : Material = EnvMesh.cel("floor_panel_dim")
	var m : float = 0.01
	var top : float = 0.025
	match variant:
		1: #two slabs, a joint across the middle
			root.add_child(EnvMesh.plate(Rect2(-h + m, -h + m, SLAB - 2 * m, (SLAB - 0.026) / 2.0), 0.0, top, slab, 0.02))
			root.add_child(EnvMesh.plate(Rect2(-h + m, 0.008, SLAB - 2 * m, (SLAB - 0.026) / 2.0), 0.0, top, slab, 0.02))
		6: #two slabs, a joint lengthways
			root.add_child(EnvMesh.plate(Rect2(-h + m, -h + m, (SLAB - 0.026) / 2.0, SLAB - 2 * m), 0.0, top, slab, 0.02))
			root.add_child(EnvMesh.plate(Rect2(0.008, -h + m, (SLAB - 0.026) / 2.0, SLAB - 2 * m), 0.0, top, slab, 0.02))
		_:
			root.add_child(EnvMesh.plate(Rect2(-h + m, -h + m, SLAB - 2 * m, SLAB - 2 * m), 0.0, top, slab, 0.02))
	match variant:
		2:
			_bolts(root, top, h - 0.05, "floor_stud", 0.016)
		3:
			for i in 7:
				root.add_child(EnvMesh.stud(Vector2(r.randf_range(-0.2, 0.2), r.randf_range(-0.2, 0.2)), top, r.randf_range(0.01, 0.022), 0.007, 0.007, EnvMesh.cel("floor_panel"), 7))
		4: #scuff marks, all running the same way like drag marks
			var long_x : bool = r.randf() < 0.5
			for i in 3:
				var length : float = r.randf_range(0.12, 0.24)
				var at : Vector2 = Vector2(r.randf_range(-0.2, 0.0), r.randf_range(-0.2, 0.0))
				root.add_child(EnvMesh.quad(Rect2(at.x, at.y, length if long_x else 0.007, 0.007 if long_x else length), top + 0.0008, EnvMesh.cel("floor_slab")))
		5: #drain
			var c : Vector2 = Vector2(r.randf_range(-0.08, 0.08), r.randf_range(-0.08, 0.08))
			root.add_child(EnvMesh.stud(c, top, 0.095, 0.085, 0.008, EnvMesh.cel("floor_stud"), 16))
			root.add_child(EnvMesh.stud(c, top, 0.078, 0.074, 0.011, EnvMesh.cel("floor_deep"), 16))
			for i in 3:
				root.add_child(EnvMesh.quad(Rect2(c.x - 0.06, c.y - 0.036 + i * 0.036, 0.12, 0.009), top + 0.0125, EnvMesh.cel("floor_stud")))
		7: #a stain
			root.add_child(EnvMesh.stud(Vector2(r.randf_range(-0.1, 0.1), r.randf_range(-0.1, 0.1)), top, 0.14, 0.14, 0.003, EnvMesh.cel("floor_stain"), 10))
	return root


##One wall cell at the centre of a 3 x 3 block. mask has a bit set for each neighbour that is wall (N, NE, E, SE, S, SW, W, NW).
##variant 1 is the cell with a panel joint across its run, so a long wall reads as bolted sections instead of one extrusion.
static func wall_tile(mask : int, variant : int = 0) -> Node3D:
	var root : Node3D = Node3D.new()
	var h : float = CELL / 2.0
	var top : float = WALL_TOP + CAP
	for i in 8: #neighbouring wall cells only matter as surfaces at the same height, so the ink does not run along a join
		if mask & (1 << i):
			var o : Vector2i = NEIGHBOUR_BITS[i]
			root.add_child(EnvMesh.quad(Rect2(o.x * CELL - h, o.y * CELL - h, CELL, CELL), top, EnvMesh.cel("cap_dark")))
	var n : bool = bool(mask & 1)
	var e : bool = bool(mask & 4)
	var s : bool = bool(mask & 16)
	var w : bool = bool(mask & 64)
	#the block: pulled in by one pixel on every open edge, which is where the ink outline goes
	var x0 : float = -h + (0.0 if w else INK)
	var x1 : float = h - (0.0 if e else INK)
	var z0 : float = -h + (0.0 if n else INK)
	var z1 : float = h - (0.0 if s else INK)
	root.add_child(EnvMesh.quad(Rect2(x0, z0, x1 - x0, z1 - z0), WALL_TOP, EnvMesh.cel("wall_dark")))
	#the cap plate: set in from the block's edge on open sides, flush on closed ones
	var ring : float = INK + 0.02
	var px0 : float = -h + (0.0 if w else ring)
	var px1 : float = h - (0.0 if e else ring)
	var pz0 : float = -h + (0.0 if n else ring)
	var pz1 : float = h - (0.0 if s else ring)
	var sides : String = ("" if n else "n") + ("" if e else "e") + ("" if s else "s") + ("" if w else "w")
	root.add_child(EnvMesh.plate(Rect2(px0, pz0, px1 - px0, pz1 - pz0), WALL_TOP, CAP, EnvMesh.cel("cap_dark"), 0.02, sides))
	#inner corners: both neighbours are wall but the diagonal is open, so the rim has to turn the corner
	var patch : float = ring + 0.02
	for corner : Array in [[2, n, e, 1.0, -1.0], [8, s, e, 1.0, 1.0], [32, s, w, -1.0, 1.0], [128, n, w, -1.0, -1.0]]:
		if corner[1] and corner[2] and not (mask & int(corner[0])):
			var rx : float = h - patch if corner[3] > 0.0 else -h
			var rz : float = h - patch if corner[4] > 0.0 else -h
			root.add_child(EnvMesh.quad(Rect2(rx, rz, patch, patch), top + 0.005, EnvMesh.cel("wall_dark")))
	#on top: a conduit that follows the wall, so it runs round every bend and junction. Each side with wall beyond it gets an arm from the middle
	#of the cell to its edge, where the next cell's arm takes over; a straight run is one pipe through the cell, and a bend, junction or end
	#gets a ball at the middle that closes the joint.
	var arms : Array[Vector2] = []
	for side : Array in [[n, 0.0, -1.0], [e, 1.0, 0.0], [s, 0.0, 1.0], [w, -1.0, 0.0]]:
		if side[0]:
			arms.append(Vector2(side[1], side[2]))
	var pipe_radius : float = 0.03
	var straight : bool = arms.size() == 2 and arms[0] == -arms[1]
	if straight:
		root.add_child(EnvMesh.pipe(Vector2.ZERO, top, CELL, pipe_radius, arms[0].x != 0.0, EnvMesh.cel("pipe")))
	elif not arms.is_empty():
		for arm : Vector2 in arms:
			root.add_child(EnvMesh.pipe(arm * CELL / 4.0, top, CELL / 2.0, pipe_radius, arm.x != 0.0, EnvMesh.cel("pipe")))
		root.add_child(EnvMesh.ball(Vector2.ZERO, top, pipe_radius, EnvMesh.cel("pipe")))
	#a panel joint with a pipe clamp and rivets on the cells that have one
	if straight and variant == 1:
		var along_x : bool = arms[0].x != 0.0
		var at : float = h - 0.03 #near the trailing edge of the cell
		var joint : Rect2 = Rect2(at - 0.003, -h + ring, 0.006, CELL - 2.0 * ring) if along_x else Rect2(-h + ring, at - 0.003, CELL - 2.0 * ring, 0.006)
		root.add_child(EnvMesh.quad(joint, top + 0.0015, EnvMesh.cel("cap_groove")))
		var clamp : Rect2 = Rect2(at - 0.014, -0.042, 0.028, 0.084) if along_x else Rect2(-0.042, at - 0.014, 0.084, 0.028)
		root.add_child(EnvMesh.plate(clamp, top, 0.048, EnvMesh.cel("wall_dark"), 0.012))
		for sgn in [-1.0, 1.0]:
			var rivet : Vector2 = Vector2(at, sgn * 0.07) if along_x else Vector2(sgn * 0.07, at)
			root.add_child(EnvMesh.stud(rivet, top, 0.009, 0.005, 0.008, EnvMesh.cel("door_inner"), 8))
	return root


##A one metre sliding gate in a wall a quarter metre thick. state: closed, locked or open. vertical gates sit in a vertical wall.
##The picture is 1 m by 0.5 m: the wall band in the middle plus a strip of floor either side that carries the hazard marking.
##Closed: two armoured leaves that meet in the middle, rib plates, a lock bar across the seam and a status light on each end post.
##Open: the leaves are in the wall pockets, so only the posts, the rails and the threshold are left.
static func door(state : String, exterior : bool, vertical : bool) -> Node3D:
	var root : Node3D = Node3D.new()
	var uv : Callable = func(u0 : float, v0 : float, u1 : float, v1 : float) -> Rect2: #u runs along the gate, v across it
		return Rect2(v0, u0, v1 - v0, u1 - u0) if vertical else Rect2(u0, v0, u1 - u0, v1 - v0)
	var pt : Callable = func(u : float, v : float) -> Vector2:
		return Vector2(v, u) if vertical else Vector2(u, v)
	var half_wall : float = CELL / 2.0 - INK #the wall band, pulled in for the ink
	var leaf_color : String = "door_leaf_ext" if exterior else "door_leaf"
	#hazard marking on the floor each side of the gate: alternating stripes
	for side in [-1.0, 1.0]:
		for k in 21:
			var u0 : float = -0.42 + k * 0.04
			var v0 : float = half_wall + 0.012 if side > 0.0 else -half_wall - 0.012 - 0.05
			root.add_child(EnvMesh.quad(uv.call(u0, v0, u0 + 0.04, v0 + 0.05), 0.004, EnvMesh.cel("hazard" if k % 2 == 0 else "hazard_dark")))
	#the rails the leaves run on, along both long edges of the wall band
	for side in [-1.0, 1.0]:
		var v0 : float = half_wall - 0.026 if side > 0.0 else -half_wall + 0.002
		root.add_child(EnvMesh.plate(uv.call(-0.44, v0, 0.44, v0 + 0.024), 0.0, 0.02, EnvMesh.cel("door_inner"), 0.01))
	#the end posts, taller than the leaves, each with a status light
	var light : String = "alarm" if state == "locked" else "item"
	for side in [-1.0, 1.0]:
		var pu : float = -0.5 if side < 0.0 else 0.44
		root.add_child(EnvMesh.plate(uv.call(pu, -half_wall, pu + 0.06, half_wall), 0.0, 0.55, EnvMesh.cel("door_leaf"), 0.03))
		var lc : Vector2 = pt.call(pu + 0.03, 0.0)
		root.add_child(EnvMesh.quad(Rect2(lc.x - 0.014, lc.y - 0.014, 0.028, 0.028), 0.555, EnvMesh.flat(light)))
	if state == "open":
		return root
	#the leaves
	var leaf_v : float = half_wall - 0.04
	for side in [-1.0, 1.0]:
		var u0 : float = -0.44 if side < 0.0 else 0.006
		var u1 : float = -0.006 if side < 0.0 else 0.44
		root.add_child(EnvMesh.plate(uv.call(u0, -leaf_v, u1, leaf_v), 0.02, 0.13, EnvMesh.cel(leaf_color), 0.025))
		for k in 3: #ribs across the leaf
			var ru : float = (0.07 + k * 0.1) * side
			root.add_child(EnvMesh.plate(uv.call(ru - 0.012, -leaf_v + 0.015, ru + 0.012, leaf_v - 0.015), 0.15, 0.012, EnvMesh.cel("door_inner"), 0.008))
		if exterior: #hazard stripe along one edge of the leaf
			for k in 4:
				var a : float = (0.012 + k * 0.016) * side
				var b : float = (0.012 + (k + 1) * 0.016) * side
				root.add_child(EnvMesh.quad(uv.call(minf(a, b), -leaf_v + 0.012, maxf(a, b), -leaf_v + 0.03), 0.1632, EnvMesh.cel("hazard" if k % 2 == 0 else "hazard_dark")))
	#the lock bar across the seam, with a light at each end
	root.add_child(EnvMesh.plate(uv.call(-0.07, -leaf_v - 0.012, 0.07, leaf_v + 0.012), 0.15, 0.024, EnvMesh.cel("door_inner"), 0.01))
	for side in [-1.0, 1.0]:
		var c : Vector2 = pt.call(0.04 * side, 0.0)
		root.add_child(EnvMesh.quad(Rect2(c.x - 0.009, c.y - 0.009, 0.018, 0.018), 0.176, EnvMesh.flat(light)))
	return root


static func _bolts(root : Node3D, y_base : float, inset : float, color : String, radius : float) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			root.add_child(EnvMesh.stud(Vector2(sx * inset, sz * inset), y_base, radius, radius * 0.55, 0.014, EnvMesh.cel(color)))
