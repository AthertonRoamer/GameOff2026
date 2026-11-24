class_name HitscanManager
extends Node2D

## Instant shots. A hitscan gun (Gun.hitscan) calls fire() from its use(). Two peers act on it: the shooter's, which draws the shot at once (it predicted it), and the
## lobby, which decides the hit and tells everyone else. The lobby rewinds the players to where the shooter saw them (LagCompensator, using the shooter's view lag
## from its input), takes the nearest of that and the wall, and emits shot_hit with the same kind of dictionary a projectile hit has ({damage, direction, owner_id}),
## so the game deals the damage the same way, blood and all. It sends every other peer the finished shot (_shot_remote: where it started and ended), which draws
## the tracer and plays the shooter's muzzle flash and kick, and the shooter one small message (hit_confirmed) for the hit marker. So every peer sees every shot,
## however well it could follow the shooter's input itself. A peer that is only watching ignores its own run of use() for another player's shot.
## A shot repeated by a resimulated tick is ignored (fire returns false), like ProjectileManager.spawn does.

signal shot_hit(shot : Dictionary, target : Node) #lobby only
signal hit_confirmed(damage : float) #on the shooter's own peer
signal wall_hit(at : Vector2, own_shot : bool) #a shot ended on a wall (on every peer that is told of the shot: the impact sound). own_shot: this peer's own player made it

@export var world_collision_mask : int = 10 #walls and closed doors stop a shot
@export var duplicate_window_ticks : int = 8 #a shot this close in time to the owner's last one is the same shot again
@export var target_radius : float = 16.0 #the players' hit radius, for the picture of where a shot ends

var lag_compensator : LagCompensator
var can_hit : Callable = Callable() ## (node) -> bool, who can be hit (not the dead)
var targets : Callable = Callable() ## () -> Array of the players: where this peer sees them, so a shot is drawn ending on the first one it passes through
var sight : Callable = Callable() ## (point) -> float, how well the local player sees it, 0 to 1 (PlayerSight.visibility): shots are only drawn as well as they could be seen
var player_of : Callable = Callable() ## (peer_id) -> that peer's Player or null: whose muzzle flash to play for a shot the lobby sent

var shots_seen : int = 0 #how many shots this peer has drawn (the tests compare it across peers)
var _last_shot : Dictionary = {} #owner id -> tick of the last shot seen here
var _active : bool = true


## Stops sending messages. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false


## A shot from origin along direction, at this tick, by this owner. view_lag: ticks the shooter sees others behind the lobby. Returns false for a repeat, or for a
## shot this peer only watches (the lobby sends it).
func fire(owner_node : Node, owner_id : int, origin : Vector2, direction : Vector2, tick : int, damage : float, max_range : float, view_lag : int, color : Color, pellets : int = 1, spread_degrees : float = 0.0) -> bool:
	var lobby : bool = _is_lobby()
	if not _active or direction.is_zero_approx() or not (lobby or owner_id == multiplayer.get_unique_id()):
		return false
	if absi(tick - _last_shot.get(owner_id, -1000000)) <= duplicate_window_ticks:
		return false
	_last_shot[owner_id] = tick
	var ends : PackedVector2Array = PackedVector2Array()
	var walls : PackedByteArray = PackedByteArray()
	var hit_damage : float = 0.0
	for dir : Vector2 in pellet_directions(direction.normalized(), pellets, spread_degrees, hash([owner_id, tick])):
		var result : Dictionary = _trace(owner_node, owner_id, origin, dir, tick, damage, max_range, view_lag, lobby)
		ends.append(result["end"])
		walls.append(1 if result["on_wall"] else 0)
		hit_damage += result["damage"]
	if hit_damage > 0.0:
		_confirm(owner_id, hit_damage) #one marker for a shot, however many pellets struck
	var wall_sounded : bool = false
	for i in ends.size():
		_show(origin, ends[i], color, walls[i] == 1, not wall_sounded, owner_id == multiplayer.get_unique_id())
		wall_sounded = wall_sounded or walls[i] == 1
	if lobby:
		for peer in multiplayer.get_peers():
			if peer != owner_id: #the shooter drew it already
				_shot_remote.rpc_id(peer, owner_id, origin, ends, walls, color)
	return true


## The directions of a shot's pellets: one pellet goes straight, several are spread over the cone (evenly, each moved a little at random). The random part comes from `seed_value`
## (the shooter and the tick), so the shooter's own picture of the shot and the lobby's decision are the same pellets.
static func pellet_directions(dir : Vector2, pellets : int, spread_degrees : float, seed_value : int) -> Array[Vector2]:
	var result : Array[Vector2] = []
	if pellets <= 1 or spread_degrees <= 0.0:
		result.append(dir)
		return result
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var half : float = deg_to_rad(spread_degrees)
	var slot : float = 2.0 * half / pellets
	for i in pellets:
		var angle : float = -half + slot * (i + 0.5) + rng.randf_range(-slot * 0.5, slot * 0.5)
		result.append(dir.rotated(angle))
	return result


## One ray of a shot: where it ends (a wall, the first player it passes through as this peer sees them, or the end of its reach) and, on the lobby, whether it hit someone
## (the damage then goes out as shot_hit). Returns {end, on_wall, damage dealt}.
func _trace(owner_node : Node, owner_id : int, origin : Vector2, dir : Vector2, tick : int, damage : float, max_range : float, view_lag : int, lobby : bool) -> Dictionary:
	var end : Vector2 = origin + dir * max_range
	var on_wall : bool = false
	var wall : Dictionary = get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(origin, end, world_collision_mask))
	if not wall.is_empty():
		end = wall["position"]
		on_wall = true
	var wall_distance : float = origin.distance_to(end)
	if targets.is_valid(): #where this peer sees the players: the shot is drawn ending on the first one it passes through
		for target : Node2D in targets.call():
			if target == owner_node or not is_instance_valid(target) or (can_hit.is_valid() and not can_hit.call(target)):
				continue
			var distance : float = LagCompensator.ray_circle_distance(origin, dir, target.global_position, target_radius)
			if distance >= 0.0 and distance < origin.distance_to(end):
				end = origin + dir * distance
				on_wall = false
	var dealt : float = 0.0
	if lobby and lag_compensator != null: #the lobby decides, against the players as the shooter saw them
		var hit : Dictionary = lag_compensator.raycast(origin, dir, wall_distance, tick - lag_compensator.clamp_lag(view_lag), owner_node, can_hit)
		if not hit.is_empty():
			end = hit["position"]
			on_wall = false
			dealt = damage
			shot_hit.emit({"damage": damage, "direction": dir, "owner_id": owner_id}, hit["node"])
	return {"end": end, "on_wall": on_wall, "damage": dealt}


## Draws one ray of a shot. sound_wall: whether a wall it ends on is heard (a shotgun's pellets strike the wall together: one impact sound, not eight).
func _show(origin : Vector2, end : Vector2, color : Color, on_wall : bool, sound_wall : bool = true, own_shot : bool = false) -> void:
	shots_seen += 1
	if on_wall and sound_wall:
		wall_hit.emit(end, own_shot) #every peer, whether or not it can see the shot: the sound is heard through the map
	var tracer : ShotTracer = ShotTracer.new()
	add_child(tracer)
	tracer.visibility = sight
	tracer.start(origin, end, color, on_wall)


func _confirm(owner_id : int, damage : float) -> void:
	if owner_id == multiplayer.get_unique_id():
		hit_confirmed.emit(damage)
	elif not multiplayer.get_peers().is_empty():
		_hit_confirmed_remote.rpc_id(owner_id, damage)


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


## The lobby -> every peer but the shooter: a shot happened. Draws it and plays the shooter's muzzle flash and kick.
@rpc("authority", "call_remote", "reliable")
func _shot_remote(owner_id : int, origin : Vector2, ends : PackedVector2Array, walls : PackedByteArray, color : Color) -> void:
	if not _active:
		return
	var wall_sounded : bool = false
	for i in ends.size():
		_show(origin, ends[i], color, walls[i] == 1, not wall_sounded)
		wall_sounded = wall_sounded or walls[i] == 1
	if player_of.is_valid():
		var shooter : Player = player_of.call(owner_id)
		if is_instance_valid(shooter):
			shooter.shot_fired.emit()


@rpc("authority", "call_remote", "reliable")
func _hit_confirmed_remote(damage : float) -> void:
	if _active:
		hit_confirmed.emit(damage)