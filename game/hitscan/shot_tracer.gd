class_name ShotTracer
extends Node2D

## The look of an instant shot: a bullet flying very fast, drawn in code. A short bright streak (a fading tail, a hot slug and a small glow) runs from the barrel to
## where the shot ended in a fraction of a second; its tail then catches up and it is gone, and where it struck a wall a small burst of sparks flies off. Made by
## HitscanManager on every peer; it removes itself. (The shot itself is instant: only the picture takes time to arrive.)

const SPEED : float = 3400.0 #pixels per second the bullet is drawn travelling
const TAIL : float = 44.0 #how long the streak behind it is
const TAIL_SECONDS : float = 0.07 #how long the tail takes to catch up after the bullet has arrived
const SPARK_SECONDS : float = 0.2
const SPARKS : int = 6
const WALL_INSET : float = 3.0 #how far in front of a wall an impact is looked at, for the view

var _from : Vector2
var _to : Vector2
var _dir : Vector2
var _length : float
var _travel_seconds : float
var _color : Color
var _spark : bool = false
var visibility : Callable = Callable() ## (point) -> float, how well the local player sees a point, 0 to 1 (PlayerSight.visibility). Unset: seen everywhere
var _age : float = 0.0
var _step : float = 0.0 #how far the bullet moved in the last frame: the streak is never shorter, so it reads as one smooth blur at any frame rate
var _spark_angles : PackedFloat32Array = PackedFloat32Array()


func start(from : Vector2, to : Vector2, color : Color, spark : bool) -> void:
	_from = from
	_to = to
	_color = color
	_spark = spark
	_length = from.distance_to(to)
	_dir = (to - from).normalized() if _length > 0.001 else Vector2.RIGHT
	_travel_seconds = maxf(_length / SPEED, 0.02)
	var back : float = (from - to).angle() #sparks fly back off the wall
	for i in SPARKS:
		_spark_angles.append(back + randf_range(-1.2, 1.2))
	queue_redraw()


func _process(delta : float) -> void:
	_age += delta
	_step = SPEED * delta
	if _age >= _travel_seconds + (SPARK_SECONDS if _spark else TAIL_SECONDS):
		queue_free()
		return
	queue_redraw()


## How well the local player sees a point of the shot. A shot ends ON a wall's surface, which the view's own wall test counts as blocked, so a point at the end is
## looked at from just in front of the wall: the impact (the sparks) is seen whenever the wall is.
func _seen(point : Vector2) -> float:
	if not visibility.is_valid():
		return 1.0
	if point.is_equal_approx(_to):
		point -= _dir * WALL_INSET
	return visibility.call(point)


func _draw() -> void:
	var arrived : float = clampf((_age - _travel_seconds) / TAIL_SECONDS, 0.0, 1.0) #0 while it flies, then 0 to 1 as the tail catches up
	var travelled : float = minf(SPEED * _age, _length)
	var head : Vector2 = _from + _dir * travelled
	var seen : float = _seen(head) #a bullet is only drawn as well as the local player can see where it is
	var in_sight : bool = seen > 0.02
	var tail_length : float = minf(maxf(TAIL, _step * 1.3), travelled) * (1.0 - arrived)
	if in_sight and tail_length > 0.5:
		var tail : Vector2 = head - _dir * tail_length
		var side : Vector2 = _dir.orthogonal() * 1.5
		draw_polygon(PackedVector2Array([tail, head + side, head - side]), PackedColorArray([Color(_color, 0.0), Color(_color, 0.75 * seen), Color(_color, 0.75 * seen)]))
		draw_line(head - _dir * minf(tail_length, 12.0), head, Color(_color.lightened(0.45), 0.95 * seen), 1.6, true)
	if in_sight and arrived < 1.0:
		for i in 3: #a small round glow, repeated back over the frame's travel so it smears into one blur (circles, not a wide line: that drew a visible box)
			draw_circle(head - _dir * minf(_step, travelled) * (i / 3.0), 4.5, Color(_color, 0.09 * (1.0 - arrived) * seen))
		draw_circle(head, 3.0, Color(_color, 0.3 * (1.0 - arrived) * seen))
		draw_circle(head, 1.5, Color(_color.lightened(0.8), (1.0 - arrived) * seen))
	if _spark and _age >= _travel_seconds and _seen(_to) > 0.02:
		var t : float = (_age - _travel_seconds) / SPARK_SECONDS
		for angle in _spark_angles:
			var dir : Vector2 = Vector2.from_angle(angle)
			draw_line(_to + dir * (2.0 + 6.0 * t), _to + dir * (4.0 + 10.0 * t), Color(_color.lightened(0.5), 1.0 - t), 1.0)