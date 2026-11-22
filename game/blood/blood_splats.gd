class_name BloodSplats
extends Node2D

## The blood on the floor of a level, under everything that stands on it (its z_index is set in the scene: above the floor, below the bodies). It makes BloodSplat
## nodes for three things:
##   a hit        the lobby sees a player take damage and throws a splash on the floor on the far side of them, the way the bullet was going (on_player_damaged)
##   bleeding     a player below half their health drops a splat under their feet every couple of seconds (the lobby counts the time, see Player.is_bleeding)
##   a body       when a player dies a puddle forms under where the body lies, and fades when they get up (on_player_died, on every peer: the body is the same everywhere)
## The lobby decides every hit and bleeding splat (its position and a random seed) and tells every peer, so each peer draws the same splat; a splat then lives ten
## seconds or so. Offline (the playground) the local peer is the lobby. The splats keep off walls (see BloodSplat).

const THROW_DISTANCE : float = 15.0 #how far behind the player a hit's splash is centred, in world pixels

@export var max_splats : int = 150 #the oldest goes first
@export var bleed_interval : Vector2 = Vector2(1.6, 2.6) #seconds between a bleeding player's drops, from, to

## () -> Array of the players. Set by whoever owns them (the game): it is how the lobby finds who is bleeding.
var players : Callable = Callable()

var _splats : Array[BloodSplat] = []
var _bleed_timers : Dictionary = {} #player -> seconds until their next drop
var _puddles : Dictionary = {} #player -> the puddle under their body
var _active : bool = true


func quiesce() -> void:
	_active = false


## Lobby (connect it to Player.damaged): a player was hit by something going this way.
func on_player_damaged(direction : Vector2, player : Player) -> void:
	if not _active or not _is_lobby() or direction.is_zero_approx():
		return
	var dir : Vector2 = direction.normalized()
	var start : Vector2 = player.global_position
	var at : Vector2 = start + dir * (THROW_DISTANCE + randf_range(-3.0, 4.0))
	var hit : Dictionary = _ray(start, at)
	if not hit.is_empty(): #a wall right behind them: the splash is against it, not in it
		at = start + (hit["position"] as Vector2 - start) * 0.7
	_make(BloodSplat.Kind.HIT, at, dir, randi())


## Any peer (connect it deferred to Player.died, after the skin has laid the body): a puddle forms under the body.
func on_player_died(player : Player) -> void:
	if not _active or not is_instance_valid(player):
		return
	var at : Vector2 = player.skin.body_position()
	var puddle : BloodSplat = _add(BloodSplat.Kind.PUDDLE, at, Vector2.ZERO, hash(player.get_instance_id()))
	_puddles[player] = puddle


func _process(delta : float) -> void:
	if not _active:
		return
	for player : Player in _puddles.keys(): #a body that got up leaves its puddle to fade
		if not is_instance_valid(player) or player.is_alive():
			if is_instance_valid(_puddles[player]):
				(_puddles[player] as BloodSplat).fade_now(1.2)
			_puddles.erase(player)
	if not _is_lobby() or not players.is_valid():
		return
	for player : Player in players.call():
		if not is_instance_valid(player) or not player.is_bleeding():
			_bleed_timers.erase(player)
			continue
		var left : float = _bleed_timers.get(player, randf_range(0.3, 1.0)) - delta
		if left <= 0.0:
			var spread : Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.0, 5.0)
			_make(BloodSplat.Kind.BLEED, player.global_position + spread, Vector2.ZERO, randi())
			left = randf_range(bleed_interval.x, bleed_interval.y)
		_bleed_timers[player] = left


## Lobby: makes a splat here and on every other peer.
func _make(kind : int, at : Vector2, direction : Vector2, seed : int) -> void:
	_add(kind, at, direction, seed)
	if not multiplayer.get_peers().is_empty():
		_splat_remote.rpc(kind, at, direction, seed)


func _add(kind : int, at : Vector2, direction : Vector2, seed : int) -> BloodSplat:
	var splat : BloodSplat = BloodSplat.new()
	add_child(splat)
	splat.global_position = at
	splat.start(kind, direction, seed)
	_splats.append(splat)
	_splats.assign(_splats.filter(func(s) -> bool: return is_instance_valid(s))) #(untyped: a splat that faded away is a freed object, which a typed argument refuses)
	while _splats.size() > max_splats:
		_splats.pop_front().queue_free()
	return splat


func _ray(from : Vector2, to : Vector2) -> Dictionary:
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, BloodSplat.WALL_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query)


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("authority", "call_remote", "reliable")
func _splat_remote(kind : int, at : Vector2, direction : Vector2, seed : int) -> void:
	if _active:
		_add(kind, at, direction, seed)
