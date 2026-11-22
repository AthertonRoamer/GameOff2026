class_name BloodSplat
extends Node2D

## One splat of blood on the floor, drawn in code in the game's flat style: a dark rim round a red blob, a small highlight and a few droplets. It forms (grows from
## a small blot to its full size, easing out), stays a while, then fades. Its outline is cut to the walls when it is made, so it never lies on one, and growing
## only scales it down from that size, so it never reaches one while forming either. Every peer makes the same splat from the same seed (see BloodSplats).
##   HIT     a short splash from a bullet, thrown on along the way it was going
##   BLEED   a drop of a bleeding player's blood under their feet
##   PUDDLE  the pool that forms under a body, slowly

enum Kind { HIT, BLEED, PUDDLE }

const BLOOD : Color = Color("#6b2125") #a dull, dark red: not the palette's bright alarm red
const BLOOD_DARK : Color = Color("#431a1d")
const BLOOD_LIGHT : Color = Color("#843035")
const WALL_MASK : int = FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER
const FADE_SECONDS : float = 1.5
const POINTS : int = 16 #of the outline

var kind : int = Kind.HIT
var _life : float = 10.0 #seconds until it has faded away
var _grow : float = 0.3 #seconds it takes to form
var _age : float = 0.0
var _outline : PackedVector2Array = PackedVector2Array()
var _inner : PackedVector2Array = PackedVector2Array()
var _drops : Array[Vector3] = [] #x, y, radius
var _radius : float = 8.0


## Makes the splat's shape for this kind, from the seed, at the node's position (so it must be in the tree there). direction: the way a HIT was going.
func start(splat_kind : int, direction : Vector2, splat_seed : int) -> void:
	kind = splat_kind
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = splat_seed
	var dir : Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.from_angle(rng.randf() * TAU)
	var stretch : float = 1.0
	var drop_count : int = 0
	match kind:
		Kind.HIT:
			_radius = rng.randf_range(6.0, 9.0)
			_life = rng.randf_range(9.0, 11.0)
			_grow = 0.3
			stretch = 1.7
			drop_count = rng.randi_range(3, 5)
		Kind.BLEED:
			_radius = rng.randf_range(4.0, 7.0)
			_life = rng.randf_range(9.0, 11.0)
			_grow = 0.9
			drop_count = rng.randi_range(1, 2)
		Kind.PUDDLE:
			_radius = rng.randf_range(17.0, 22.0)
			_life = 45.0
			_grow = 3.5
			drop_count = rng.randi_range(0, 2)
	for i in POINTS:
		var v : Vector2 = Vector2.from_angle(TAU * i / POINTS) * _radius * rng.randf_range(0.75, 1.2)
		v += dir * maxf(v.dot(dir), 0.0) * (stretch - 1.0) #a splash is longer on the side it was thrown to
		_outline.append(_clipped(v))
	var shrunk : Array[PackedVector2Array] = Geometry2D.offset_polygon(_outline, -1.2)
	_inner = shrunk[0] if not shrunk.is_empty() else _outline
	for i in drop_count:
		var away : float = rng.randf_range(1.3, 2.6) * _radius
		var angle : float = dir.angle() + rng.randf_range(-0.6, 0.6) if kind == Kind.HIT else rng.randf() * TAU
		var at : Vector2 = Vector2.from_angle(angle) * away
		var r : float = rng.randf_range(1.2, 2.4)
		if _is_clear(at + at.normalized() * (r + 1.0)):
			_drops.append(Vector3(at.x, at.y, r))
	scale = Vector2.ONE * 0.35
	queue_redraw()


## Lets it fade now, over this long (a puddle whose body got up).
func fade_now(seconds : float) -> void:
	_life = minf(_life, _age + seconds)


func _process(delta : float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	var t : float = clampf(_age / _grow, 0.0, 1.0)
	scale = Vector2.ONE * lerpf(0.35, 1.0, 1.0 - pow(1.0 - t, 3.0)) #forms, quickly at first
	modulate.a = clampf((_life - _age) / FADE_SECONDS, 0.0, 1.0)


func _draw() -> void:
	if _outline.size() < 3:
		return
	draw_colored_polygon(_outline, BLOOD_DARK)
	draw_colored_polygon(_inner, BLOOD)
	if kind != Kind.BLEED:
		draw_circle(Vector2(-_radius * 0.3, -_radius * 0.3), _radius * 0.16, BLOOD_LIGHT)
	for drop : Vector3 in _drops:
		draw_circle(Vector2(drop.x, drop.y), drop.z, BLOOD_DARK)
		draw_circle(Vector2(drop.x, drop.y), maxf(drop.z - 0.8, 0.5), BLOOD)


## The point v (relative to the splat), pulled back towards the middle if a wall is in the way.
func _clipped(v : Vector2) -> Vector2:
	var hit : Dictionary = _ray(v + v.normalized() * 1.5)
	if hit.is_empty():
		return v
	return (hit["position"] as Vector2 - global_position) - v.normalized() * 1.0 if (hit["position"] as Vector2).distance_to(global_position) > 1.5 else Vector2.ZERO


func _is_clear(v : Vector2) -> bool:
	return _ray(v).is_empty()


func _ray(v : Vector2) -> Dictionary:
	if not is_inside_tree():
		return {}
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, global_position + v, WALL_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query)
