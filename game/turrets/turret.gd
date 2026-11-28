@tool
class_name Turret
extends StaticBody2D

##An automatic gun on a swivel, seen from above. Put turret.tscn under the map's Props node, standing in a room, and turn it (`facing_degrees`, or just rotate
##the arrow the editor draws) to point where it should watch. While it is switched on (from the door console, or by a technician, see FacilityControl and
##TurretSwitch) and its region has the power, it watches a cone in front of it and shoots intruders, never guards. It shows nothing of whether it is on: an
##idle turret sits still and silent, on or off. It only gives itself away by turning (a whir) and firing.
##
##  switched on -> WARMING (warmup_seconds) -> IDLE -> an intruder in its cone, in range, in sight -> TRACKING: turns towards them at turn_speed -> aimed ->
##  LOCKING: its laser shows for lock_on_seconds -> FIRING: bursts of shots that stray more as the burst goes on, with a pause between bursts. A target out of
##  sight is followed to where it was last seen for lose_target_seconds, then the turret turns back to its facing (RETURNING) and goes IDLE.
##
##It is solid (it stops players and shots, and furniture and walls give cover from it) and anyone can shoot it (HitscanManager.SHOOTABLE_GROUP). Shot down, it
##is switched off and can't be switched on until a guard repairs it by holding E (it comes back at full health, still off).
##Every number is in its `settings` (turret_settings.tres). The thinking is done on the lobby only (lobby_step, run by TurretSystem), which tells every peer where it points.

enum Phase { OFF, WARMING, IDLE, TRACKING, LOCKING, FIRING, RETURNING, DESTROYED }

const DEFAULT_SETTINGS : TurretSettings = preload("res://game/turrets/turret_settings.tres")
const RADIUS : float = 14.0 #the base, in world pixels (44 per metre)
const BARREL : float = 22.0 #from the middle to the muzzle
const SIGHT_MASK : int = FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER #what blocks its view: walls, closed doors, furniture
const TURN_HEARD_SECONDS : float = 0.12 #a turret counts as turning for this long after its aim last moved (the whir does not flicker between sync messages)
const FLASH_SECONDS : float = 0.06

@export var facing_degrees : float = 0.0 : set = _set_facing ## where it watches when idle: the middle of its cone. 0 is right (east), 90 down (south)
@export var settings : TurretSettings = DEFAULT_SETTINGS : set = _set_settings ## its numbers. Shared by every turret; Make Unique to tune this one alone
@export_range(0.0, 3.0, 0.05, "suffix:m") var height : float = 1.0 ## how tall it is: its shadow falls on lower things in a flashlight beam (see LightLayers)

var system : TurretSystem #set by the system when it finds the turret
var index : int = -1 #its place among the system's turrets (the same on every peer: the scene is the same)
var region : String = "" #the region of the room it stands in: what pays for it
var health : float = 0.0 : set = _set_health
var phase : Phase = Phase.OFF #on the lobby, decided here; elsewhere, as the lobby last said
var aim : float = 0.0 #where the gun points, in radians (world). On the lobby, the truth; elsewhere eased towards `aim_target`
var aim_target : float = 0.0 #elsewhere: where the lobby last said it points

#lobby only: the thinking
var target : Node2D = null
var _last_seen : Vector2 = Vector2.ZERO
var _lost_for : float = 0.0
var _warm_left : float = 0.0
var _lock_left : float = 0.0
var _locked : bool = false #the lock-on is done for this target: aimed, it fires
var _shot_left : float = 0.0
var _burst_count : int = 0

var _turning_left : float = 0.0 #every peer: > 0 while it has turned lately (the whir)
var _shown_aim : float = 0.0 #the aim at the last frame
var _flash_left : float = 0.0
var _time : float = 0.0
var _laser : Node2D


func _ready() -> void:
	collision_layer = FacilityTileSet.WORLD_LAYER | FacilityTileSet.PROP_LAYER #solid like a wall: stops players and shots; and furniture: shadows in flashlight beams
	collision_mask = 0
	var tier : LightLayers.Tier = LightLayers.tier_of(height)
	light_mask = LightLayers.receiver_layer(tier)
	var occluder : LightOccluder2D = get_node_or_null("Occluder")
	if occluder != null:
		occluder.occluder_light_mask = LightLayers.caster_layer(tier)
	aim = facing()
	aim_target = aim
	_shown_aim = aim
	if Engine.is_editor_hint():
		return
	health = max_health()
	add_to_group(PlayerInteractor.GROUP)
	add_to_group(HitscanManager.SHOOTABLE_GROUP)
	_laser = Node2D.new() #the lock-on laser glows in the dark: drawn unshaded, over the darkness
	_laser.name = "Laser"
	var material_ : CanvasItemMaterial = CanvasItemMaterial.new()
	material_.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_laser.material = material_
	_laser.top_level = true
	_laser.draw.connect(_draw_laser)
	add_child(_laser)


func _process(delta : float) -> void:
	_time += delta
	_flash_left = maxf(0.0, _flash_left - delta)
	if Engine.is_editor_hint():
		return
	if not _is_lobby_view(): #the lobby says where it points a few times a second: ease towards it, no faster than it can turn (a little faster, to catch up)
		aim = rotate_toward(aim, aim_target, the_settings().turn_speed_radians() * 1.5 * delta)
	if absf(angle_difference(_shown_aim, aim)) > 0.0005: #(on the lobby the aim moves in the physics step, between two of these)
		_turning_left = TURN_HEARD_SECONDS
	else:
		_turning_left = maxf(0.0, _turning_left - delta)
	_shown_aim = aim
	queue_redraw()
	if _laser != null:
		_laser.queue_redraw()


# ------------------------------------------------------------------ the numbers
func the_settings() -> TurretSettings:
	return settings if settings != null else DEFAULT_SETTINGS


func max_health() -> float:
	return the_settings().max_health


##Where it watches when idle (the middle of its cone), in radians, in the world.
func facing() -> float:
	return deg_to_rad(facing_degrees) + global_rotation


##Shot down (every peer: the health comes from the lobby, reliably).
func is_destroyed() -> bool:
	return health <= 0.0 and not Engine.is_editor_hint()


##Turned lately (every peer): its whir is heard.
func is_turning() -> bool:
	return _turning_left > 0.0


##Its laser shows: locking on, or firing.
func shows_laser() -> bool:
	return phase == Phase.LOCKING or phase == Phase.FIRING


##Where its shots come from.
func muzzle() -> Vector2:
	return global_position + Vector2.from_angle(aim) * BARREL


##How far an angle (world, radians) is from its facing, -PI to PI.
func offset_of(angle : float) -> float:
	return angle_difference(facing(), angle)


##Is this world point inside its cone and its range?
func covers(point : Vector2) -> bool:
	var to : Vector2 = point - global_position
	if to.length() > the_settings().range_px:
		return false
	return absf(offset_of(to.angle())) <= the_settings().fov_radians() / 2.0


##Can it see this point: in its cone and range, and nothing solid (a wall, a closed door, furniture) or thick smoke between them?
func can_see(point : Vector2) -> bool:
	if not covers(point):
		return false
	if not is_inside_tree():
		return true
	if SmokeCloud.blocks(get_tree(), global_position, point): #a smoke bomb's cloud hides them
		return false
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, point, SIGHT_MASK)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


##Who it shoots: a living intruder. Never a guard (a player with no role, in the playground, is not shot either).
static func is_quarry(player : Node) -> bool:
	if not is_instance_valid(player) or not player.has_method("is_alive") or not player.is_alive():
		return false
	var role : Role = player.get("role")
	return role != null and role.is_intruder()


# ------------------------------------------------------------------ lobby: thinking (TurretSystem calls this every physics tick)
##One step of the turret's thinking: `on` is its power switch, `players` everyone. Returns the directions of the shots it fires this step (usually none).
func lobby_step(delta : float, on : bool, players : Array) -> Array[Vector2]:
	var shots : Array[Vector2] = []
	var s : TurretSettings = the_settings()
	if health <= 0.0:
		_forget()
		phase = Phase.DESTROYED
		return shots
	if not on:
		_forget()
		phase = Phase.OFF
		return shots
	if phase == Phase.OFF or phase == Phase.DESTROYED:
		phase = Phase.WARMING
		_warm_left = s.warmup_seconds
	if phase == Phase.WARMING:
		_warm_left -= delta
		if _warm_left > 0.0:
			return shots
		phase = Phase.IDLE
	#who to aim at: the one it has, while it still sees them; else the nearest intruder it sees
	var sees_target : bool = target != null and is_quarry(target) and can_see(target.global_position)
	if not sees_target:
		var best : Node2D = null
		var best_distance : float = INF
		for player in players:
			if not is_quarry(player) or not can_see(player.global_position):
				continue
			var distance : float = global_position.distance_squared_to(player.global_position)
			if distance < best_distance:
				best = player
				best_distance = distance
		if best != null:
			if best != target:
				_new_target(best)
			sees_target = true
	var goal : float = facing()
	if sees_target:
		_last_seen = target.global_position
		_lost_for = 0.0
		goal = (_last_seen - global_position).angle()
	elif target != null:
		_lost_for += delta
		if _lost_for <= s.lose_target_seconds:
			goal = (_last_seen - global_position).angle() #keeps watching where they went
		else:
			_forget()
	_turn_towards(goal, s.turn_speed_radians() * delta)
	var aimed : bool = sees_target and absf(angle_difference(aim, goal)) <= s.aim_tolerance_radians()
	_shot_left = maxf(0.0, _shot_left - delta)
	if target == null:
		phase = Phase.RETURNING if absf(angle_difference(aim, facing())) > 0.001 else Phase.IDLE
	elif not aimed:
		phase = Phase.TRACKING
	elif not _locked:
		phase = Phase.LOCKING
		_lock_left -= delta
		if _lock_left <= 0.0:
			_locked = true
			phase = Phase.FIRING
	else:
		phase = Phase.FIRING
	if phase == Phase.FIRING and aimed and _shot_left <= 0.0:
		var stray : float = s.spread_radians(_burst_count)
		shots.append(Vector2.from_angle(aim + randf_range(-stray, stray)))
		_burst_count += 1
		if _burst_count >= s.burst_shots:
			_burst_count = 0
			_shot_left = s.burst_pause_seconds
		else:
			_shot_left = s.shot_interval()
	return shots


func _new_target(player : Node2D) -> void:
	target = player
	_locked = false
	_burst_count = 0
	var role : Role = player.get("role")
	_lock_left = the_settings().lock_on_seconds * (the_settings().silent_lock_multiplier if role != null and role.silent_walk else 1.0)


func _forget() -> void:
	target = null
	_locked = false
	_lost_for = 0.0
	_burst_count = 0


##Turns towards an angle, never leaving its cone (it goes round the way inside it, whatever the cone's width).
func _turn_towards(goal : float, step : float) -> void:
	var half : float = the_settings().fov_radians() / 2.0
	var now : float = clampf(offset_of(aim), -half, half)
	var want : float = clampf(offset_of(goal), -half, half)
	now = move_toward(now, want, step)
	aim = facing() + now


# ------------------------------------------------------------------ every peer: what the lobby said
##The lobby said where it points and what it is doing (TurretSystem's sync). Locking on is heard as it starts.
func apply_sync(new_aim : float, new_phase : Phase) -> void:
	aim_target = new_aim
	phase = new_phase


func show_shot() -> void:
	_flash_left = FLASH_SECONDS


func _is_lobby_view() -> bool:
	return system == null or system.is_lobby()


# ------------------------------------------------------------------ interactable (see PlayerInteractor): a guard repairs a shot-down turret
func get_prompt() -> String:
	return "Hold E   repair the turret"


func is_in_reach(world_position : Vector2) -> bool:
	if global_position.distance_to(world_position) > reach_px():
		return false
	if not is_inside_tree():
		return true
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(world_position, global_position, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func reach_px() -> float:
	return the_settings().reach_m * 44.0 + RADIUS


##Only a shot-down turret, and only a guard (a player with no role, in the playground, counts as one).
func can_interact(player : Node) -> bool:
	if system == null or not is_destroyed():
		return false
	var role : Role = player.get("role")
	return role == null or role.kind == Role.Kind.GUARD


func hold_seconds(_player : Node) -> float:
	return the_settings().repair_seconds


func hold_started(_player : Node) -> void:
	if system != null:
		system.request_hold(self, true)


func hold_cancelled(_player : Node) -> void:
	if system != null:
		system.request_hold(self, false)


func interact(_player : Node) -> Control:
	if system != null:
		system.request_finish(self)
	return null


##A shot ended on it. Lobby only (HitscanManager and ProjectileManager only report hits there); the system tells every peer.
func take_damage(damage : float, _direction : Vector2 = Vector2.ZERO) -> void:
	if system != null:
		system.damage_turret(self, damage)


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var s : TurretSettings = the_settings()
	var broken : bool = is_destroyed()
	if Engine.is_editor_hint(): #its cone and range, to place it
		var half : float = s.fov_radians() / 2.0
		var local_facing : float = deg_to_rad(facing_degrees)
		var cone : PackedVector2Array = PackedVector2Array([Vector2.ZERO])
		for i in 25:
			cone.append(Vector2.from_angle(local_facing - half + 2.0 * half * i / 24.0) * s.range_px)
		draw_colored_polygon(cone, Color(Palette.ALARM, 0.07))
		draw_polyline(cone + PackedVector2Array([Vector2.ZERO]), Color(Palette.ALARM, 0.4), 1.0, true)
	draw_circle(Vector2(2.0, 3.0), RADIUS + 1.5, Color(0, 0, 0, 0.35)) #its shadow
	draw_circle(Vector2.ZERO, RADIUS, Palette.WALL_TOP)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, Palette.METAL, 1.5, true)
	for i in 4: #the bolts on the base
		draw_circle(Vector2.from_angle(PI / 4.0 + i * PI / 2.0) * (RADIUS - 3.5), 1.1, Palette.WALL)
	var local_aim : float = (aim if not Engine.is_editor_hint() else facing()) - global_rotation
	if broken:
		local_aim += 0.5 #knocked askew
	draw_set_transform(Vector2.ZERO, local_aim, Vector2.ONE) #the head turns
	var body : Color = Palette.WALL if broken else Palette.METAL
	draw_rect(Rect2(-8.0, -7.0, 15.0, 14.0), body)
	draw_rect(Rect2(-8.0, -7.0, 15.0, 14.0), Palette.WALL, false, 1.0)
	draw_rect(Rect2(6.0, -2.0, BARREL - 6.0, 4.0), Palette.WALL_TOP if not broken else Palette.WALL)
	draw_rect(Rect2(BARREL - 3.0, -2.6, 3.0, 5.2), Palette.WALL)
	draw_circle(Vector2(-2.0, 0.0), 2.4, Palette.DEEP) #the sensor eye: always dark, so nobody can tell from it whether it is on
	if _flash_left > 0.0:
		draw_circle(Vector2(BARREL + 3.0, 0.0), 5.0, Color(Palette.FLASH, 0.9))
		draw_circle(Vector2(BARREL + 3.0, 0.0), 8.0, Color(Palette.BACKUP, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if broken and not Engine.is_editor_hint() and fmod(_time, 1.3) < 0.08: #a spark now and then
		draw_circle(Vector2(4.0, -5.0), 2.0, Palette.FLASH)
	if not Engine.is_editor_hint() and not broken and health < max_health(): #damage: a bar over it
		var bar : Rect2 = Rect2(Vector2(-RADIUS, -RADIUS - 8.0), Vector2(RADIUS * 2.0, 3.5))
		draw_rect(bar, Palette.VOID)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(health / max_health(), 0.0, 1.0), bar.size.y)), Palette.ALARM if health < max_health() * 0.35 else Palette.BACKUP)


func _draw_laser() -> void:
	if not shows_laser() or not is_inside_tree():
		return
	var from : Vector2 = muzzle()
	var to : Vector2 = from + Vector2.from_angle(aim) * the_settings().range_px
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, SIGHT_MASK)
	query.exclude = [get_rid()]
	var hit : Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to = hit["position"]
	var pulse : float = 0.55 + 0.25 * sin(_time * 30.0) if phase == Phase.LOCKING else 0.8
	_laser.draw_line(from, to, Color(Palette.ALARM, pulse * 0.35), 3.0, true)
	_laser.draw_line(from, to, Color(Palette.ALARM, pulse), 1.0, true)
	_laser.draw_circle(to, 2.0, Color(Palette.ALARM, pulse))


func _get_configuration_warnings() -> PackedStringArray:
	var map : FacilityMap = _map()
	if map == null:
		return PackedStringArray()
	var at : Vector2 = map.to_local(global_position)
	if map.room_at(at) == "":
		return PackedStringArray(["This turret is not on any room's floor. Drag it into a room."])
	return PackedStringArray()


func _set_facing(value : float) -> void:
	facing_degrees = value
	queue_redraw()


func _set_settings(value : TurretSettings) -> void:
	settings = value
	queue_redraw()


func _set_health(value : float) -> void:
	health = value
	queue_redraw()


func _map() -> FacilityMap:
	var node : Node = get_parent()
	while node != null and not node is FacilityMap:
		node = node.get_parent()
	return node as FacilityMap


func _notification(what : int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()
	elif what == NOTIFICATION_ENTER_TREE and Engine.is_editor_hint():
		set_notify_transform(true)
