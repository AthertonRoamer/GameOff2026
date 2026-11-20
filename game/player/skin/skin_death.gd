class_name SkinDeath
extends Node

## How a skin falls and lies when its player dies. Child of the skin; NightShiftCharacter.die() and revive() use it.
##
## A dead player falls the way the shot that killed them pushes them, and stays lying in the pose the fall ends on (the sheets do not loop, so they hold their last
## frame). There are falls from the front, the front right, the right, the back right and the back (clips from Mixamo, with the two in between blended from their
## neighbours in Blender); the left side is the right side mirrored. The sheet only picks the pose: the body is then turned so that it lands exactly away from the
## shot. The shadow lies along the body and travels with it, and the fall is kept out of walls.

@export var wall_margin := 6.0 ## how far (pixels) in front of a wall a fallen body's centre may end

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


## The body travels away from where the player stood as the sheet plays, so the shadow travels with it, and the fall is kept out of walls: when the spot the body
## ends on is behind one, the whole fall is pulled back (slid over the fall's own duration) until it ends in front of it.
func _follow(sheet : String, mirrored : bool, source_angle_deg : float) -> void:
	var full := _skin.full
	var data : Dictionary = _skin.meta[sheet]
	var flip := -1.0 if mirrored else 1.0 #a mirrored sheet has everything on the other side of its centre line
	var end : Array = data.get("end_center", [0.0, 0.0]) #where the body ends up, relative to where the player stood, in the sheet's pixels
	var sheet_fall := Vector2(end[0] * flip, end[1]).angle() #the way the sheet carries the body, which is turned onto the shot's own direction
	full.rotation = _skin.torso.rotation - PI / 2.0 + deg_to_rad(source_angle_deg) + PI - sheet_fall
	var points : Array[Vector2] = []
	for p : Array in data.get("end_points", []):
		points.append(Vector2(p[0] * flip, p[1]))
	var centre := Vector2(end[0] * flip, end[1]).rotated(full.rotation) #in the skin's space
	var pull := _pull_from_walls(points)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var time : float = data["frames"] / maxf(1.0, data["fps"])
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


## How far (skin space) the fall must be slid back so that none of the body's points ends behind a wall: a ray from where the player stands to each point
## (the points shifted by what has been pulled so far), repeated a few times because pulling one point back moves the others.
func _pull_from_walls(points : Array[Vector2]) -> Vector2:
	var body := _skin.get_parent() as CollisionObject2D
	if body == null or not _skin.is_inside_tree() or points.is_empty():
		return Vector2.ZERO
	var full := _skin.full
	var space := _skin.get_world_2d().direct_space_state
	var to_skin : Transform2D = _skin.global_transform.affine_inverse()
	var from := full.global_position
	var pull := Vector2.ZERO
	for _pass in 4:
		var worst := Vector2.ZERO
		for p in points:
			var to : Vector2 = full.to_global(p) + _skin.global_transform.basis_xform(pull)
			var query := PhysicsRayQueryParameters2D.create(from, to, body.collision_mask)
			query.exclude = [body.get_rid()]
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var over := from.distance_to(to) - maxf(from.distance_to(hit["position"]) - wall_margin, 0.0)
			var back : Vector2 = to_skin.basis_xform((from - to).normalized() * over)
			if back.length() > worst.length():
				worst = back
		if worst.length() < 0.5:
			break
		pull += worst
	return pull
