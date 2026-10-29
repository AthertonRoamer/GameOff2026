class_name LagCompensator
extends Node

##Server-side lag compensation for instant (hitscan) weapons in 2D.
##Records where tracked nodes were on every rollback tick, so a shot can be checked against the world as the shooter saw it
##instead of the world as it is now. Netfox does not provide this itself.
##
##Usage on the lobby (server): track() every hittable node, then from the weapon's code call
##  raycast(origin, direction, max_range, tick - clamp_lag(shooter_view_lag), shooter)
##The shooter reports its view lag (how many ticks behind the server it is displaying other players) as an input property.
##The server clamps it, so a client cannot rewind further than max_rewind_ticks.

@export var max_rewind_ticks : int = 12 #60 ticks/s: 12 ticks = 200 ms. Raise it to compensate for more latency, at the cost of fairness to the target
@export var server_only : bool = true #recording is only needed where shots are resolved

var _tracked : Dictionary = {} #key: node, value: {property: StringName, radius: float, history: Dictionary (tick -> Vector2)}


func _ready() -> void:
	NetworkRollback.on_record_tick.connect(_on_record_tick)


func _exit_tree() -> void:
	if NetworkRollback.on_record_tick.is_connected(_on_record_tick):
		NetworkRollback.on_record_tick.disconnect(_on_record_tick)


func track(node : Node, property : StringName = &"position", radius : float = 32.0) -> void:
	_tracked[node] = {"property": property, "radius": radius, "history": {}}
	node.tree_exiting.connect(untrack.bind(node), CONNECT_ONE_SHOT)


func untrack(node : Node) -> void:
	_tracked.erase(node)


func clamp_lag(lag_ticks : int) -> int:
	return clampi(lag_ticks, 0, max_rewind_ticks)


##Stores the current value of every tracked node for the given tick. Called automatically after every rollback tick.
func record(tick : int) -> void:
	for node in _tracked:
		if is_instance_valid(node):
			var entry : Dictionary = _tracked[node]
			entry["history"][tick] = node.get(entry["property"])


##Forgets everything older than the given tick.
func trim(oldest_tick : int) -> void:
	for node in _tracked:
		var history : Dictionary = _tracked[node]["history"]
		for tick in history.keys():
			if tick < oldest_tick:
				history.erase(tick)


##Where the node was on the given tick. Ticks newer than anything recorded use the node's current value,
##ticks older than the history use the oldest value known.
func get_position_at(node : Node, tick : int) -> Vector2:
	var entry : Dictionary = _tracked.get(node, {})
	if entry.is_empty():
		return node.get(&"position")
	var history : Dictionary = entry["history"]
	if history.has(tick):
		return history[tick]
	if history.is_empty():
		return node.get(entry["property"])
	var newest : int = history.keys().max()
	if tick > newest:
		return node.get(entry["property"])
	return history[history.keys().min()]


##Fires a ray against the tracked nodes as they were on the given tick. Returns {} on a miss, otherwise
##{"node": Node, "position": Vector2 (where the ray enters the target), "distance": float}.
##An optional filter (node -> bool) skips nodes that cannot be hit, for example dead players.
func raycast(origin : Vector2, direction : Vector2, max_range : float, tick : int, exclude : Node = null, filter : Callable = Callable()) -> Dictionary:
	var best : Dictionary = {}
	var best_distance : float = max_range
	for node in _tracked:
		if node == exclude or not is_instance_valid(node) or (filter.is_valid() and not filter.call(node)):
			continue
		var distance : float = ray_circle_distance(origin, direction, get_position_at(node, tick), _tracked[node]["radius"])
		if distance >= 0.0 and distance <= best_distance:
			best_distance = distance
			best = {"node": node, "position": origin + direction.normalized() * distance, "distance": distance}
	return best


##Moves a circle of sweep_radius from `from` to `to` against the tracked nodes as they were on the given tick, for projectiles.
##Returns {} on a miss, otherwise {"node": Node, "position": Vector2 (where the sweep first touches), "fraction": float (0 to 1 along the move)}.
func sweep(from : Vector2, to : Vector2, sweep_radius : float, tick : int, exclude : Node = null, filter : Callable = Callable()) -> Dictionary:
	var best : Dictionary = {}
	var best_fraction : float = 2.0
	for node in _tracked:
		if node == exclude or not is_instance_valid(node) or (filter.is_valid() and not filter.call(node)):
			continue
		var fraction : float = segment_circle_fraction(from, to, sweep_radius, get_position_at(node, tick), _tracked[node]["radius"])
		if fraction >= 0.0 and fraction < best_fraction:
			best_fraction = fraction
			best = {"node": node, "position": from.lerp(to, fraction), "fraction": fraction}
	return best


##How far along the move from `from` to `to` (0 to 1) a circle of sweep_radius first touches the circle at `center`, or -1.0 if it never does.
##A move that starts already touching returns 0.
static func segment_circle_fraction(from : Vector2, to : Vector2, sweep_radius : float, center : Vector2, radius : float) -> float:
	var reach : float = sweep_radius + radius
	var start : Vector2 = from - center
	var move : Vector2 = to - from
	var c : float = start.length_squared() - reach * reach
	if c <= 0.0:
		return 0.0
	var a : float = move.length_squared()
	if a < 0.000001:
		return -1.0
	var b : float = 2.0 * start.dot(move)
	var discriminant : float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var fraction : float = (-b - sqrt(discriminant)) / (2.0 * a)
	return fraction if fraction >= 0.0 and fraction <= 1.0 else -1.0


##Distance along the ray to where it first touches the circle, or -1.0 if it does not. A ray starting inside the circle returns 0.
static func ray_circle_distance(origin : Vector2, direction : Vector2, center : Vector2, radius : float) -> float:
	if direction.is_zero_approx():
		return -1.0
	var dir : Vector2 = direction.normalized()
	var to_center : Vector2 = center - origin
	var along : float = to_center.dot(dir)
	var closest_sq : float = to_center.length_squared() - along * along
	var radius_sq : float = radius * radius
	if closest_sq > radius_sq:
		return -1.0
	var half_chord : float = sqrt(radius_sq - closest_sq)
	var entry : float = along - half_chord
	var exit : float = along + half_chord
	if exit < 0.0:
		return -1.0 #circle is behind the ray
	return maxf(entry, 0.0)


func _on_record_tick(tick : int) -> void:
	if server_only and not multiplayer.is_server():
		return
	record(tick)
	trim(NetworkRollback.history_start)
