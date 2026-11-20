class_name SkinDeath
extends Node

## How a skin falls and lies when its player dies. Child of the skin; NightShiftCharacter.die() and revive() use it.
##
## A dead player falls the way the shot that killed them pushes them, and stays lying in the pose the fall ends on (the sheets do not loop, so they hold their last
## frame). There are falls from the front, the front right, the right, the back right and the back (clips from Mixamo, with the two in between blended from their
## neighbours in Blender); the left side is the right side mirrored. The sheet only picks the pose: the body is then turned so that it lands exactly away from the
## shot. The shadow lies along the body and travels with it, and the fall is kept out of walls.

const WALL_MARGIN : float = 2.0 #how far (world pixels) a body keeps from a wall
const TURN_STEP_DEG : float = 15.0 #the fall is turned by this much at a time to find a way of lying that fits
const SLIDE_STEP : float = 3.0 #the rings of places tried by sliding are this far apart, in world pixels
const RINGS : int = 20 #how many widening rings of places are tried when the player stood against a wall

var landing : Vector2 = Vector2.ZERO #where the middle of the body ends up, in the skin's space (set when it falls)
var _tween : Tween #the body (and its shadow) sliding along with the fall
var _shadow_rest : Array = [] #the shadow's position and scale while standing, put back on revive

@onready var _skin : NightShiftCharacter = get_parent()


## source_angle_deg: where the shot came from, measured from the way the player faces: 0 is from the front, positive from the right, negative from the left, 180
## from behind.
func fall(source_angle_deg : float) -> void:
	var angle := absf(source_angle_deg)
	var sheet := "death_front"
	if angle >= 157.5:
		sheet = "death_back"
	elif angle >= 112.5:
		sheet = "death_back_right"
	elif angle >= 67.5:
		sheet = "death_right"
	elif angle >= 22.5:
		sheet = "death_front_right"
	var mirrored := source_angle_deg < 0.0 and sheet != "death_front" and sheet != "death_back" #the sheets fall towards the right; the front and back are the middle
	_skin.stop_upper_body_blends()
	var full := _skin.full
	full.rotation = _skin.torso.rotation
	_skin.legs.visible = false
	_skin.torso.visible = false
	full.visible = true
	full.flip_h = mirrored
	var shadow := _skin.get_node_or_null("Shadow") as Sprite2D
	if shadow != null:
		shadow.visible = false #the blob under a standing character stays where he stood, while the body has fallen away from there
	full.play(sheet)
	full.offset = _skin.sheet_offset(sheet, mirrored)
	_follow(sheet, mirrored, source_angle_deg)


## Where the body lies, in the world.
func landing_here() -> Vector2:
	return _skin.to_global(landing)


## Stands the skin up again: the legs and torso come back, the body and its shadow go back where they were.
func rise() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var full := _skin.full
	full.visible = false
	full.flip_h = false
	full.position = Vector2.ZERO
	var shadow := _skin.get_node_or_null("Shadow") as Sprite2D
	if shadow != null:
		shadow.visible = true
		if not _shadow_rest.is_empty():
			shadow.position = _shadow_rest[0]
			shadow.scale = _shadow_rest[1]
		shadow.rotation = 0.0
	_skin.legs.visible = true
	_skin.torso.visible = true


## The body travels away from where the player stood as the sheet plays, and the shadow travels with it. The fall never ends in a wall: if the way the shot pushes
## the body would put any of it into a wall or door, the whole fall is turned (the body slumps along the wall instead of into it), the smallest turn that clears;
## only when no turn fits (a closet) is it slid, over the fall's own duration, to the nearest clear place.
func _follow(sheet : String, mirrored : bool, source_angle_deg : float) -> void:
	var full := _skin.full
	var data : Dictionary = _skin.meta[sheet]
	var flip := -1.0 if mirrored else 1.0 #a mirrored sheet has everything on the other side of its centre line
	var end : Array = data.get("end_center", [0.0, 0.0]) #where the body ends up, relative to where the player stood, in the sheet's pixels
	var sheet_fall := Vector2(end[0] * flip, end[1]).angle() #the way the sheet carries the body, which is turned onto the shot's own direction
	var rotation : float = _skin.torso.rotation - PI / 2.0 + deg_to_rad(source_angle_deg) + PI - sheet_fall
	var hull : PackedVector2Array = PackedVector2Array() #the body's outline where it ends, in the sheet's pixels, mirrored like the sheet
	for point : Array in data.get("end_hull", []):
		hull.append(Vector2(point[0] * flip, point[1]))
	var fit : Dictionary = _fit_to_walls(hull, rotation)
	full.rotation = rotation + fit["turn"]
	var pull : Vector2 = fit["pull"]
	var centre := Vector2(end[0] * flip, end[1]).rotated(full.rotation) #in the skin's space
	landing = centre + pull
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var time : float = data["frames"] / maxf(1.0, data["fps"])
	if not pull.is_zero_approx():
		_tween.tween_property(full, "position", pull, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var shadow := _skin.get_node_or_null("Shadow") as Sprite2D
	if shadow != null:
		shadow.visible = true
		if _shadow_rest.is_empty():
			_shadow_rest = [shadow.position, shadow.scale]
		var shape : Array = data.get("end_shadow", [0.0, 128.0, 128.0]) #the body's direction, length and width: the shadow lies along it
		shadow.rotation = (PI - shape[0] if mirrored else shape[0]) + full.rotation
		_tween.tween_property(shadow, "position", centre + pull, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_property(shadow, "scale", Vector2(shape[1] * 1.2, shape[2] * 1.3) / float(shadow.texture.get_width()), time)


## {turn (radians to add to the fall's rotation), pull (skin space, how far to slide it)} for a body with this outline falling at this rotation: no turn and no
## slide when it already clears the walls, else the smallest turn that does (to either side, up to half way round), else the nearest clear place by sliding.
## (The player's own collision is already off by now, so the wall layers are named here.)
func _fit_to_walls(hull : PackedVector2Array, rotation : float) -> Dictionary:
	var body := _skin.get_parent() as CollisionObject2D
	if body == null or not _skin.is_inside_tree() or hull.size() < 3:
		return {"turn": 0.0, "pull": Vector2.ZERO}
	var space := _skin.get_world_2d().direct_space_state
	for k in range(0, 13):
		for side in ([1.0] if k == 0 else [1.0, -1.0]):
			var turn : float = deg_to_rad(TURN_STEP_DEG) * k * side
			if _body_is_clear(space, body, hull, rotation + turn, Vector2.ZERO):
				return {"turn": turn, "pull": Vector2.ZERO}
	var to_skin : Transform2D = _skin.global_transform.affine_inverse()
	for ring in range(1, RINGS + 1): #no way of lying fits: slide it to the nearest clear place round the standing spot
		for k in 16:
			var offset : Vector2 = Vector2.from_angle(k * TAU / 16.0) * ring * SLIDE_STEP
			if _body_is_clear(space, body, hull, rotation, offset):
				return {"turn": 0.0, "pull": to_skin.basis_xform(offset)}
	return {"turn": 0.0, "pull": Vector2.ZERO}


## Does the body, outlined by `hull` (sheet pixels), lying at this rotation and slid by `offset` (world pixels) touch a wall or door, where it ends and on the way
## there? On the way it is smaller and nearer the standing spot (the outline scaled towards it).
func _body_is_clear(space : PhysicsDirectSpaceState2D, body : CollisionObject2D, hull : PackedVector2Array, rotation : float, offset : Vector2) -> bool:
	var basis : Transform2D = _skin.global_transform
	for t in [0.5, 0.75, 1.0]:
		var points : PackedVector2Array = PackedVector2Array()
		for point in hull:
			points.append(basis.basis_xform(point.rotated(rotation) * t))
		var grown : Array[PackedVector2Array] = Geometry2D.offset_polygon(points, WALL_MARGIN, Geometry2D.JOIN_MITER)
		if grown.is_empty():
			continue
		var shape := ConvexPolygonShape2D.new()
		shape.points = grown[0]
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, _skin.global_position + offset * t)
		query.collision_mask = FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER
		query.exclude = [body.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true