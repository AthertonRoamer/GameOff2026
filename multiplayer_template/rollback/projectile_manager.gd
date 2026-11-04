class_name ProjectileManager
extends Node2D

##Slow projectiles for rollback games. A projectile is not a node with state: where it is on any tick is a pure function of
##where and when it was fired (origin + direction * speed * ticks since fire), so every peer agrees without syncing positions.
##
##Flow:
##  - the weapon calls spawn() when its RewindableAction is CONFIRMING, on every peer that simulates the shot (the shooter predicts it)
##  - the lobby sends the shot to the other clients, and also resolves hits (against LagCompensator positions, one tick at a time)
##  - on a hit or a wall the lobby tells every client to remove the projectile, and emits projectile_hit so the game can apply damage
##A late input makes the lobby resimulate and the same shot can be spawned again on a nearby tick, so spawn() ignores a repeat
##from the same owner within duplicate_window_ticks (set it to about half the weapon's cooldown).
##Hits use positions on the tick the projectile reaches them (no extra rewind). Damage is the game's job: connect projectile_hit.

signal projectile_hit(projectile : Dictionary, target : Node) #lobby only. projectile: {owner_id, owner, fire_tick, damage, position}

@export var speed : float = 600.0 #pixels per second
@export var radius : float = 2.2 #the hit size and the size of the drawn bullet
@export var tracer_length : float = 20.0 #how long the fading streak behind a bullet is
@export var lifetime_ticks : int = 90
@export var duplicate_window_ticks : int = 8
@export var world_collision_mask : int = 0 #physics layers that stop a projectile (lobby only). 0 ignores the world
@export var color : Color = Color(1.0, 0.6, 0.2)

var lag_compensator : LagCompensator #the lobby needs it to find what a projectile hits
var can_hit : Callable = Callable() #optional filter (target node -> bool), for example to skip dead players

var _projectiles : Array[Dictionary] = [] #{owner_id, owner, origin, direction, fire_tick, damage, checked_tick}
var _active : bool = true
static var _halo_texture : GradientTexture2D
var _had_projectiles : bool = false #so the last projectile's removal still triggers one more redraw to clear it


func _ready() -> void:
	NetworkTime.on_tick.connect(_on_tick)


func _exit_tree() -> void:
	if NetworkTime.on_tick.is_connected(_on_tick):
		NetworkTime.on_tick.disconnect(_on_tick)


##Stops sending projectile messages. Call it when the game starts to end, before the node is freed (see RollbackPlayerSpawner.quiesce).
func quiesce() -> void:
	_active = false
	_projectiles.clear()


##Starts a projectile on this peer and, on the lobby, on every other client. Returns false if it was a repeat of an earlier shot.
##speed/color override this manager's defaults per shot, so different weapons can fire visually/physically distinct projectiles.
func spawn(owner_node : Node, owner_id : int, origin : Vector2, direction : Vector2, fire_tick : int, damage : int = 0, shot_speed : float = -1.0, shot_color : Color = Color(0, 0, 0, 0)) -> bool:
	if not _active or direction.is_zero_approx() or _find(owner_id, fire_tick) != -1:
		return false
	var resolved_speed : float = shot_speed if shot_speed >= 0.0 else speed
	var resolved_color : Color = shot_color if shot_color.a > 0.0 else color
	_add(owner_node, owner_id, origin, direction.normalized(), fire_tick, damage, resolved_speed, resolved_color)
	if _is_lobby():
		for peer in multiplayer.get_peers():
			if peer != owner_id: #the shooter already predicted it
				_client_spawn.rpc_id(peer, owner_id, origin, direction.normalized(), fire_tick, damage, resolved_speed, resolved_color)
	return true


##Where a projectile is at a (possibly fractional) tick.
func position_at(projectile : Dictionary, tick : float) -> Vector2:
	return projectile["origin"] + projectile["direction"] * projectile["speed"] * (tick - projectile["fire_tick"]) * NetworkTime.ticktime


func get_projectiles() -> Array[Dictionary]:
	return _projectiles


func _process(_delta : float) -> void:
	if is_visible_in_tree() and (not _projectiles.is_empty() or _had_projectiles):
		queue_redraw()
	_had_projectiles = not _projectiles.is_empty()


func _draw() -> void:
	var now : float = NetworkTime.tick + NetworkTime.tick_factor
	for projectile in _projectiles:
		if now >= projectile["fire_tick"]:
			_draw_bullet(position_at(projectile, now), projectile["direction"], projectile["color"])


##A small glowing bullet: a soft halo, a tapered streak that fades out behind it, a bright slug and a white-hot tip. All drawn, no texture.
func _draw_bullet(head : Vector2, direction : Vector2, base : Color) -> void:
	var side : Vector2 = direction.orthogonal()
	var tail : Vector2 = head - direction * tracer_length
	var streak_width : float = radius * 0.8
	draw_polygon(PackedVector2Array([tail, head + side * streak_width, head - side * streak_width]),
		PackedColorArray([Color(base.r, base.g, base.b, 0.0), Color(base.r, base.g, base.b, 0.6), Color(base.r, base.g, base.b, 0.6)]))
	var halo : float = radius * 3.2 #a smooth radial glow, not stacked circles, so it has no visible rings
	draw_texture_rect(_get_halo_texture(), Rect2(head - Vector2(halo, halo), Vector2(halo, halo) * 2.0), false, Color(base.r, base.g, base.b, 0.55))
	draw_line(head - direction * radius * 2.4, head, base.lightened(0.4), radius * 1.2, true)
	draw_circle(head, radius * 0.7, base.lightened(0.75))
	draw_circle(head + direction * radius * 0.2, radius * 0.4, Color.WHITE)

func _on_tick(_delta : float, tick : int) -> void:
	if not _active:
		return
	var lobby : bool = _is_lobby()
	for projectile in _projectiles.duplicate():
		if tick - projectile["fire_tick"] > lifetime_ticks:
			_projectiles.erase(projectile)
			continue
		if lobby:
			_check_hits(projectile, tick)


func _check_hits(projectile : Dictionary, tick : int) -> void:
	#a shot confirmed late has already travelled for a few ticks, so go through every tick not yet checked
	for step in range(projectile["checked_tick"] + 1, tick + 1):
		projectile["checked_tick"] = step
		var from : Vector2 = position_at(projectile, step - 1)
		var to : Vector2 = position_at(projectile, step)
		var world_hit : Vector2 = Vector2.INF
		if world_collision_mask != 0:
			var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, world_collision_mask)
			var result : Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
			if not result.is_empty():
				world_hit = result["position"]
		var hit : Dictionary = {}
		if lag_compensator != null:
			hit = lag_compensator.sweep(from, to, radius, step, projectile["owner"], can_hit)
		if hit.is_empty() and world_hit == Vector2.INF:
			continue
		if not hit.is_empty() and (world_hit == Vector2.INF or from.distance_to(hit["position"]) <= from.distance_to(world_hit)):
			projectile["position"] = hit["position"]
			projectile_hit.emit(projectile, hit["node"])
		else:
			projectile["position"] = world_hit
		_projectiles.erase(projectile)
		for peer in multiplayer.get_peers():
			_client_remove.rpc_id(peer, projectile["owner_id"], projectile["fire_tick"])
		return


func _add(owner_node : Node, owner_id : int, origin : Vector2, direction : Vector2, fire_tick : int, damage : int, shot_speed : float, shot_color : Color) -> void:
	_projectiles.append({"owner_id": owner_id, "owner": owner_node, "origin": origin, "direction": direction,
		"fire_tick": fire_tick, "damage": damage, "checked_tick": fire_tick, "position": origin,
		"speed": shot_speed, "color": shot_color})


func _find(owner_id : int, fire_tick : int) -> int:
	for i in _projectiles.size():
		if _projectiles[i]["owner_id"] == owner_id and absi(_projectiles[i]["fire_tick"] - fire_tick) <= duplicate_window_ticks:
			return i
	return -1


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("authority", "call_remote", "reliable")
func _client_spawn(owner_id : int, origin : Vector2, direction : Vector2, fire_tick : int, damage : int, shot_speed : float, shot_color : Color) -> void:
	if _active and _find(owner_id, fire_tick) == -1:
		_add(null, owner_id, origin, direction, fire_tick, damage, shot_speed, shot_color)


@rpc("authority", "call_remote", "reliable")
func _client_remove(owner_id : int, fire_tick : int) -> void:
	#the shooter's own prediction can be tick or two off the lobby's version of the same shot, so take the closest one of that owner
	var best : int = -1
	var best_gap : int = lifetime_ticks / 3
	for i in _projectiles.size():
		var gap : int = absi(_projectiles[i]["fire_tick"] - fire_tick)
		if _projectiles[i]["owner_id"] == owner_id and gap <= best_gap:
			best = i
			best_gap = gap
	if best != -1:
		_projectiles.remove_at(best)


static func _get_halo_texture() -> GradientTexture2D:
	if _halo_texture == null:
		var gradient : Gradient = Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
		_halo_texture = GradientTexture2D.new()
		_halo_texture.gradient = gradient
		_halo_texture.fill = GradientTexture2D.FILL_RADIAL
		_halo_texture.fill_from = Vector2(0.5, 0.5)
		_halo_texture.fill_to = Vector2(1.0, 0.5)
		_halo_texture.width = 64
		_halo_texture.height = 64
	return _halo_texture
