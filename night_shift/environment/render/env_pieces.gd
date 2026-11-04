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
		"room": #vinyl-topped steel panels, bolted down at the corners
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor_slab")))
			if variant == 1: #two half panels
				var pw : float = (CELL - 0.03 - 0.012) / 2.0
				root.add_child(EnvMesh.plate(Rect2(-h + 0.015, -h + 0.015, pw, CELL - 0.03), 0.0, 0.03, EnvMesh.cel("floor_panel")))
				root.add_child(EnvMesh.plate(Rect2(0.006, -h + 0.015, pw, CELL - 0.03), 0.0, 0.03, EnvMesh.cel("floor_panel")))
			else:
				root.add_child(EnvMesh.plate(Rect2(-h + 0.015, -h + 0.015, CELL - 0.03, CELL - 0.03), 0.0, 0.03, EnvMesh.cel("floor_panel")))
			if variant != 1:
				_bolts(root, 0.03, h - 0.055, "floor_stud", 0.017)
			if variant == 2:
				root.add_child(EnvMesh.stud(Vector2.ZERO, 0.03, 0.02, 0.012, 0.012, EnvMesh.cel("floor_stud")))
		"corridor": #poured concrete slabs
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor_deep")))
			match variant:
				1:
					root.add_child(EnvMesh.plate(Rect2(-h + 0.01, -h + 0.01, CELL - 0.02, (CELL - 0.026) / 2.0), 0.0, 0.025, EnvMesh.cel("floor_panel_dim"), 0.02))
					root.add_child(EnvMesh.plate(Rect2(-h + 0.01, 0.008, CELL - 0.02, (CELL - 0.026) / 2.0), 0.0, 0.025, EnvMesh.cel("floor_panel_dim"), 0.02))
				_:
					root.add_child(EnvMesh.plate(Rect2(-h + 0.01, -h + 0.01, CELL - 0.02, CELL - 0.02), 0.0, 0.025, EnvMesh.cel("floor_panel_dim"), 0.02))
			if variant == 3:
				for i in 5:
					root.add_child(EnvMesh.stud(Vector2(r.randf_range(-0.2, 0.2), r.randf_range(-0.2, 0.2)), 0.025, r.randf_range(0.015, 0.03), 0.01, 0.008, EnvMesh.cel("floor_panel"), 7))
		"utility": #diamond plate
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor_panel")))
			for j in 4:
				for i in 4:
					var p : Vector2 = Vector2(-0.15 + i * 0.1 + (0.05 if j % 2 == 1 else 0.0) - (0.025 if j % 2 == 1 else 0.0), -0.15 + j * 0.1)
					root.add_child(EnvMesh.stud(p, 0.0, 0.034, 0.014, 0.014, EnvMesh.cel("floor_stud"), 4, 45.0 if variant % 2 == 1 else 0.0))
		"vault": #dark riveted steel
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor_deep")))
			root.add_child(EnvMesh.plate(Rect2(-h + 0.012, -h + 0.012, CELL - 0.024, CELL - 0.024), 0.0, 0.03, EnvMesh.cel("floor_slab")))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					root.add_child(EnvMesh.stud(Vector2(sx * 0.17, sz * 0.17), 0.03, 0.028, 0.016, 0.018, EnvMesh.cel("floor_stud")))
			if variant == 1:
				root.add_child(EnvMesh.plate(Rect2(-0.2, -0.018, 0.4, 0.036), 0.03, 0.014, EnvMesh.cel("floor_panel_dim"), 0.01))
		"outdoor": #asphalt with grit
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor_deep")))
			for i in 16:
				var rad : float = r.randf_range(0.02, 0.045)
				root.add_child(EnvMesh.stud(Vector2(r.randf_range(-0.21, 0.21), r.randf_range(-0.21, 0.21)), 0.0, rad, rad * 0.55,
					r.randf_range(0.008, 0.018), EnvMesh.cel("floor_panel_dim" if r.randf() < 0.65 else "floor_panel"), 7, r.randf_range(0.0, 60.0)))
		"vent": #floor grille
			root.add_child(EnvMesh.quad(full, 0.0, EnvMesh.cel("floor_deep")))
			for i in 5:
				root.add_child(EnvMesh.plate(Rect2(-0.2, -0.2 + i * 0.085, 0.4, 0.045), 0.0, 0.03, EnvMesh.cel("floor_stud")))
			_bolts(root, 0.0, h - 0.04, "floor_stud", 0.016)
	return root


##One wall cell at the centre of a 3 x 3 block. mask has a bit set for each neighbour that is wall (N, NE, E, SE, S, SW, W, NW).
static func wall_tile(mask : int) -> Node3D:
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
	var ring : float = INK + 0.03
	var px0 : float = -h + (0.0 if w else ring)
	var px1 : float = h - (0.0 if e else ring)
	var pz0 : float = -h + (0.0 if n else ring)
	var pz1 : float = h - (0.0 if s else ring)
	var sides : String = ("" if n else "n") + ("" if e else "e") + ("" if s else "s") + ("" if w else "w")
	root.add_child(EnvMesh.plate(Rect2(px0, pz0, px1 - px0, pz1 - pz0), WALL_TOP, CAP, EnvMesh.cel("cap_dark"), 0.03, sides))
	#inner corners: both neighbours are wall but the diagonal is open, so the rim has to turn the corner
	var patch : float = ring + 0.035
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
	var pipe_radius : float = 0.045
	if arms.size() == 2 and arms[0] == -arms[1]:
		root.add_child(EnvMesh.pipe(Vector2.ZERO, top, CELL, pipe_radius, arms[0].x != 0.0, EnvMesh.cel("pipe")))
	elif not arms.is_empty():
		for arm : Vector2 in arms:
			root.add_child(EnvMesh.pipe(arm * CELL / 4.0, top, CELL / 2.0, pipe_radius, arm.x != 0.0, EnvMesh.cel("pipe")))
		root.add_child(EnvMesh.ball(Vector2.ZERO, top, pipe_radius, EnvMesh.cel("pipe")))
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
		root.add_child(EnvMesh.quad(uv.call(-0.5, -half_v, 0.5, -half_v + 0.03), sill, EnvMesh.cel("wall_dark")))
		root.add_child(EnvMesh.quad(uv.call(-0.5, half_v - 0.03, 0.5, half_v), sill, EnvMesh.cel("wall_dark")))
		for side in [-1.0, 1.0]:
			var u0 : float = -0.5 if side < 0.0 else 0.5 - 0.13
			root.add_child(EnvMesh.plate(uv.call(u0, -leaf_v, u0 + 0.13, leaf_v), sill, leaf_h, EnvMesh.cel("door_leaf"), 0.03))
		return root
	root.add_child(EnvMesh.quad(uv.call(-0.5, -half_v, 0.5, half_v), sill, EnvMesh.cel("wall_dark")))
	for side in [-1.0, 1.0]:
		var u0 : float = -0.5 if side < 0.0 else 0.012
		var u1 : float = -0.012 if side < 0.0 else 0.5
		root.add_child(EnvMesh.plate(uv.call(u0, -leaf_v, u1, leaf_v), sill, leaf_h, EnvMesh.cel("door_leaf"), 0.03))
		root.add_child(EnvMesh.plate(uv.call(u0 + 0.05, -leaf_v + 0.05, u1 - 0.05, leaf_v - 0.05), sill + leaf_h, 0.02, EnvMesh.cel("door_inner"), 0.012))
		if exterior: #hazard stripes across the leaf, nearest the seam
			for k in 3:
				var su : float = (0.09 + k * 0.045) * side
				root.add_child(EnvMesh.plate(uv.call(su - 0.012, -leaf_v + 0.07, su + 0.012, leaf_v - 0.07), sill + leaf_h + 0.02, 0.012, EnvMesh.cel("backup"), 0.008))
	var light : String = "alarm" if state == "locked" else "item"
	for side in [-1.0, 1.0]:
		var c : Vector2 = pt.call(0.045 * side, 0.0)
		root.add_child(EnvMesh.quad(Rect2(c.x - 0.016, c.y - 0.016, 0.032, 0.032), sill + leaf_h + 0.025, EnvMesh.flat(light)))
	return root


##A wall console, two cells wide and one deep: a desk with a screen and a keyboard.
static func console() -> Node3D:
	var root : Node3D = Node3D.new()
	root.add_child(EnvMesh.plate(Rect2(-0.47, -0.21, 0.94, 0.42), 0.0, 0.30, EnvMesh.cel("wall_dark"), 0.03))
	root.add_child(EnvMesh.plate(Rect2(-0.44, -0.18, 0.88, 0.36), 0.30, 0.03, EnvMesh.cel("door_inner"), 0.02))
	root.add_child(EnvMesh.plate(Rect2(-0.30, -0.17, 0.60, 0.12), 0.33, 0.09, EnvMesh.cel("shadow"), 0.03))
	root.add_child(EnvMesh.quad(Rect2(-0.27, -0.148, 0.54, 0.075), 0.425, EnvMesh.flat("item")))
	for i in 3:
		root.add_child(EnvMesh.quad(Rect2(-0.25, -0.138 + i * 0.022, 0.2 + i * 0.07, 0.008), 0.426, EnvMesh.flat("shadow")))
	root.add_child(EnvMesh.plate(Rect2(-0.22, 0.02, 0.44, 0.11), 0.33, 0.025, EnvMesh.cel("wall_dark"), 0.012))
	for i in 2:
		root.add_child(EnvMesh.quad(Rect2(-0.19, 0.04 + i * 0.04, 0.38, 0.022), 0.356, EnvMesh.flat("backup")))
	root.add_child(EnvMesh.stud(Vector2(-0.35, 0.05), 0.33, 0.022, 0.014, 0.015, EnvMesh.cel("alarm")))
	root.add_child(EnvMesh.stud(Vector2(0.35, 0.05), 0.33, 0.022, 0.014, 0.015, EnvMesh.cel("item")))
	return root


static func _bolts(root : Node3D, y_base : float, inset : float, color : String, radius : float) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			root.add_child(EnvMesh.stud(Vector2(sx * inset, sz * inset), y_base, radius, radius * 0.55, 0.014, EnvMesh.cel(color)))
