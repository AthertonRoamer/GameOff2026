class_name PlayerSight
extends Node2D

## What the local player can see. The view zone is a rounded zone round the player that reaches far in the direction of the mouse (a teardrop: out to view_range towards
## the mouse, only view_near to the sides and behind, smoothly in between), cut short by walls and shut doors (the "view polygon", worked out every frame with a fan of
## rays all the way round). It fades out towards its edge instead of ending in a hard line (view_strength(), and the same fade in the shader).
##   bullets and shots     are drawn as well as visibility() says (HitscanManager and ProjectileManager call it)
##   other players' beams  and glows are drawn by this node with a shader (remote_beam.gdshader) that gives them the look of the scene's own flashlight light. Each beam is
##                         traced from its own flashlight (a fan of rays: it stops at walls) and cut to the view polygon, so you see any beam inside your view, whoever is
##                         holding it and wherever they are, and nothing outside it. Their scene lights are off (Flashlight.paint_instead).
##   other players' bodies are seen inside the view only while a flashlight is on them (yours or theirs, a beam or the glow round its holder), and a player very close to
##                         the local player is seen without any light, in any direction (not through walls). A body lit by another player's beam is brightened by it
##                         (the way the scene's lights would), and the drawn beams leave a soft hole round every player, so nobody is seen through a haze.
## A dead local player sees everything. Only this peer's picture changes: nothing here is sent to anyone, and the game itself (hits, the simulation) does not look at it.

const WALLS : int = FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER
const REFINE_GAP : float = 14.0 #two neighbouring rays that land this much further apart than that get a ray between them (a corner, a doorway)
const REFINE_DEPTH : int = 8 #how many times a gap is halved at most
const MAX_FAN_POINTS : int = 420 #however many corners there are, a fan stays this small
const BEAM_STRENGTH : float = 0.28 #how strongly a beam is laid over the picture at its lamp at light_scale 1: measured against the scene's own beam light (energy 1.7) on the floor
const HALO_STRENGTH : float = 0.14 #the same for the glow round the holder (the scene's halo light has energy 0.55)
const BEAM_ENERGY : float = 1.7 #the scene's beam light's energy, and the halo's: what the light on a body is worked out with
const HALO_ENERGY : float = 0.55
const MAX_BODY_GAIN : float = 2.4 #the most a light brightens a body, as a multiple of its colours in the dark (the colours stay as they are)
const BODY_GAIN_SOFTNESS : float = 4.0 #how quickly a body reaches that: bigger is gentler
const MAX_BODIES : int = 8 #how many players the shader leaves a hole round (the nearest ones)

@export var view_half_angle_deg : float = 55.0 #how wide the view reaches forward, to either side of the way the mouse is
@export var view_range : float = 900.0 #in world pixels: further than the screen
@export var view_near : float = 110.0 #how far the view reaches to the sides and behind the player
@export var view_rays : int = 120 #how finely the view is traced all the way round, so it follows walls
@export_range(0.0, 1.0) var fade_start : float = 0.4 #the view is at full strength out to this share of its reach, then fades to nothing at the edge
@export var beam_range : float = 484.0 #the flashlight's length, in world pixels (11 m)
@export var beam_half_angle_deg : float = 28.0 #the flashlight cone's half angle (see Flashlight.CONE_HALF_ANGLE)
@export var beam_rays : int = 40
@export var beam_color : Color = Color("#fff3c4") #the scene's beam light colour
@export_range(0.0, 1.5) var light_scale : float = 0.75 #how strong the drawn lights are, against the scene's own beam light (1)
@export var halo_radius : float = 40.0 #the glow round a flashlight's holder: a player inside it is seen
@export var near_radius : float = 48.0 #players this close see each other without any light (not through walls)
@export var fade_seconds : float = 0.12
@export var body_radius : float = 16.0 #a player is lit when any of their body is in a beam, not just their middle
@export var ambient : Color = Color(0.176, 0.186, 0.248) #the facility's darkness (the level's CanvasModulate): a light's brightening of a body is worked out against it. Set by the game

## () -> Array of every Player. () -> the local Player, or null. Set by the game.
var players : Callable = Callable()
var local_player : Callable = Callable()

var _view : PackedVector2Array = PackedVector2Array() #the view polygon, in the world (empty: no limit)
var _apex : Vector2
var _facing : float = 0.0
var _alpha : Dictionary = {} #player -> how seen their body is now, 0 to 1
var _lights : Dictionary = {} #player -> {"beam": RemoteBeam, "glow": RemoteBeam}
var _bodies : PackedVector2Array = PackedVector2Array() #where the players are, for the shader's holes
var _layer : CanvasLayer


func _ready() -> void:
	_layer = CanvasLayer.new() #its own layer: the facility's darkness (a CanvasModulate) does not touch it
	_layer.follow_viewport_enabled = true
	add_child(_layer)


func _process(delta : float) -> void:
	if not players.is_valid() or not local_player.is_valid():
		return
	var me : Player = local_player.call()
	if not is_instance_valid(me):
		return
	var sees_all : bool = not me.is_alive()
	_update_view(me, sees_all)
	_update_bodies()
	for player : Player in players.call():
		if player == me or not is_instance_valid(player):
			continue
		if not _lights.has(player):
			_lights[player] = {"beam": _add_light(), "glow": _add_light()}
			player.paint_flashlight_in_view()
		var lighting : Dictionary = _lighting_of(me, player)
		var target : float = 1.0 if sees_all else _body_seen(me, player, lighting["lit"])
		var alpha : float = move_toward(_alpha.get(player, target), target, delta / maxf(fade_seconds, 0.001))
		_alpha[player] = alpha
		player.set_body_seen(alpha, lighting["tint"])
		player.set_muzzle_seen(sees_all or visibility(player.global_position) > 0.3)
		_update_lights(player)
	if not sees_all:
		me.set_body_seen(1.0, _lighting_of(me, me)["tint"]) #(the local player's own body is lit by the others' drawn lights too)


func _add_light() -> RemoteBeam:
	var light : RemoteBeam = RemoteBeam.new()
	_layer.add_child(light)
	return light


## How well the local player sees this point, 0 (not at all) to 1: inside the view, fading towards its edge, and not behind a wall or a shut door.
## Everything is seen when there is no view (the local player is dead).
func visibility(point : Vector2) -> float:
	if _view.is_empty():
		return 1.0
	var strength : float = view_strength(point)
	if strength <= 0.0:
		return 0.0
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(_apex, point, WALLS)
	return strength if get_world_2d().direct_space_state.intersect_ray(query).is_empty() else 0.0


## The view's strength at a point alone: 1 in the middle, fading to 0 at its edge (walls are not looked at: see visibility()).
func view_strength(point : Vector2) -> float:
	if _view.is_empty():
		return 1.0
	var offset : Vector2 = point - _apex
	var distance : float = offset.length()
	if distance < 1.0:
		return 1.0
	var reach : float = _reach(offset.angle())
	return 1.0 - smoothstep(reach * fade_start, reach, distance)


## How far the view reaches in a direction: view_range towards the mouse, view_near to the sides and behind, smoothly in between.
func _reach(angle : float) -> float:
	var half : float = deg_to_rad(view_half_angle_deg)
	var forward : float = 1.0 - smoothstep(half * 0.3, half * 1.2, absf(angle_difference(angle, _facing)))
	return view_near + (view_range - view_near) * forward


## Works out the view polygon: all the way round the player, out to the view's reach in each direction or the first wall.
func _update_view(me : Player, sees_all : bool) -> void:
	if sees_all or me.input.aim == Vector2.ZERO:
		_view = PackedVector2Array()
		return
	_apex = me.global_position
	_facing = (me.input.aim - _apex).angle()
	var ring : PackedVector2Array = _fan(_apex, _facing - PI, _facing + PI, view_rays, _reach)
	_view = ring.slice(1) #(the player stands inside it)


## The points a fan of rays from `origin` reaches between two angles, each out to reach_at(angle) or the first wall: origin first, then the hits in order. Where two
## neighbouring rays land far apart (a corner, a doorway) rays are added between them by halving the gap, so the fan's edge follows the corner and does not cut across it.
func _fan(origin : Vector2, angle_from : float, angle_to : float, rays : int, reach_at : Callable) -> PackedVector2Array:
	var space : PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var full_circle : bool = angle_to - angle_from >= TAU - 0.001 #(the last ray would be the first again)
	var fan : PackedVector2Array = PackedVector2Array([origin])
	var angle : float = angle_from
	var previous : Vector2 = _cast(space, origin, angle, reach_at)
	var first : Vector2 = previous
	fan.append(previous)
	for i in range(1, rays + 1):
		var next_angle : float = angle_from + (angle_to - angle_from) * i / rays
		var last_again : bool = full_circle and i == rays
		var next : Vector2 = first if last_again else _cast(space, origin, next_angle, reach_at)
		_refine(space, origin, angle, previous, next_angle, next, REFINE_DEPTH, reach_at, fan)
		if not last_again:
			fan.append(next)
		angle = next_angle
		previous = next
	return fan


func _cast(space : PhysicsDirectSpaceState2D, origin : Vector2, angle : float, reach_at : Callable) -> Vector2:
	var far : Vector2 = origin + Vector2.from_angle(angle) * reach_at.call(angle)
	var hit : Dictionary = space.intersect_ray(PhysicsRayQueryParameters2D.create(origin, far, WALLS))
	return hit["position"] if not hit.is_empty() else far


func _refine(space : PhysicsDirectSpaceState2D, origin : Vector2, angle_a : float, point_a : Vector2, angle_b : float, point_b : Vector2, depth : int, reach_at : Callable, out : PackedVector2Array) -> void:
	if depth <= 0 or out.size() > MAX_FAN_POINTS or absf(origin.distance_to(point_a) - origin.distance_to(point_b)) < REFINE_GAP:
		return
	var angle_mid : float = (angle_a + angle_b) / 2.0
	var point_mid : Vector2 = _cast(space, origin, angle_mid, reach_at)
	_refine(space, origin, angle_a, point_a, angle_mid, point_mid, depth - 1, reach_at, out)
	out.append(point_mid)
	_refine(space, origin, angle_mid, point_mid, angle_b, point_b, depth - 1, reach_at, out)


## Where the players are (the nearest few, to the local player): the shader leaves a soft hole round each in the drawn lights.
func _update_bodies() -> void:
	var all : Array = players.call()
	all = all.filter(func(p) -> bool: return is_instance_valid(p))
	all.sort_custom(func(a : Player, b : Player) -> bool: return a.global_position.distance_squared_to(_apex) < b.global_position.distance_squared_to(_apex))
	_bodies = PackedVector2Array()
	for player : Player in all.slice(0, MAX_BODIES):
		_bodies.append(player.global_position)
	while _bodies.size() < MAX_BODIES:
		_bodies.append(Vector2(1.0e7, 1.0e7))


## Sets up the drawn beam and glow of another player's flashlight for this frame: their shapes (where the light reaches, cut to the view) and the shader's numbers.
func _update_lights(player : Player) -> void:
	var lights : Dictionary = _lights[player]
	var beam : RemoteBeam = lights["beam"]
	var glow : RemoteBeam = lights["glow"]
	if not player.flashlight.on or not player.is_alive():
		beam.polygons = []
		glow.polygons = []
		return
	var origin : Vector2 = player.flashlight.global_position
	var direction : float = player.flashlight.global_rotation
	var half : float = deg_to_rad(beam_half_angle_deg)
	var beam_reach : Callable = func(_angle : float) -> float: return beam_range
	beam.polygons = _in_view(_fan(origin, direction - half, direction + half, beam_rays, beam_reach))
	_set_view_uniforms(beam.shader_material)
	beam.shader_material.set_shader_parameter("origin", origin)
	beam.shader_material.set_shader_parameter("direction", direction)
	beam.shader_material.set_shader_parameter("beam_range", beam_range)
	beam.shader_material.set_shader_parameter("half_angle", half)
	beam.shader_material.set_shader_parameter("glow_radius", 0.0)
	beam.shader_material.set_shader_parameter("beam_color", beam_color)
	beam.shader_material.set_shader_parameter("strength", BEAM_STRENGTH * light_scale)
	var centre : Vector2 = player.global_position
	var glow_reach : Callable = func(_angle : float) -> float: return halo_radius
	glow.polygons = _in_view(_fan(centre, 0.0, TAU, 24, glow_reach))
	_set_view_uniforms(glow.shader_material)
	glow.shader_material.set_shader_parameter("origin", centre)
	glow.shader_material.set_shader_parameter("glow_radius", halo_radius)
	glow.shader_material.set_shader_parameter("beam_color", beam_color)
	glow.shader_material.set_shader_parameter("strength", HALO_STRENGTH * light_scale)


## A light's shape cut to the view polygon (the view's walls); the shader fades it with the view's edge.
func _in_view(shape : PackedVector2Array) -> Array[PackedVector2Array]:
	if _view.is_empty():
		return [shape]
	return Geometry2D.intersect_polygons(shape, _view)


func _set_view_uniforms(shader_material : ShaderMaterial) -> void:
	shader_material.set_shader_parameter("use_view", not _view.is_empty())
	shader_material.set_shader_parameter("view_apex", _apex)
	shader_material.set_shader_parameter("view_facing", _facing)
	shader_material.set_shader_parameter("view_half", deg_to_rad(view_half_angle_deg))
	shader_material.set_shader_parameter("view_range", view_range)
	shader_material.set_shader_parameter("view_near", view_near)
	shader_material.set_shader_parameter("fade_start", fade_start)
	shader_material.set_shader_parameter("bodies", _bodies)
	shader_material.set_shader_parameter("body_count", MAX_BODIES)


## How much of another player's body is seen: very close and unblocked, or inside the view and lit.
func _body_seen(me : Player, other : Player, lit : bool) -> float:
	var space : PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var near : float = 0.0
	var distance : float = me.global_position.distance_to(other.global_position)
	if distance <= near_radius and space.intersect_ray(PhysicsRayQueryParameters2D.create(me.global_position, other.global_position, WALLS)).is_empty():
		near = 1.0 - smoothstep(near_radius * 0.6, near_radius, distance)
	var seen_lit : float = visibility(other.global_position) if lit else 0.0
	return maxf(near, seen_lit)


## The light on another player: {"lit": whether a flashlight (any player's, the local player's too) is on them, in the glow round its holder (the holder included) or in
## its beam with nothing solid between, "tint": what the drawn lights multiply their colours by}. Only the other players' flashlights tint a body: the local player's own beam is
## a scene light, which already brightens what it falls on, the way the drawn ones are made to look like.
func _lighting_of(me : Player, other : Player) -> Dictionary:
	var lit : bool = false
	var added : Color = Color(0, 0, 0, 0) #the light that falls on them, in the scene lights' units
	for holder : Player in players.call():
		if not is_instance_valid(holder) or not holder.flashlight.on or not holder.is_alive():
			continue
		var origin : Vector2 = holder.flashlight.global_position
		var offset : Vector2 = other.global_position - origin
		var distance : float = offset.length()
		var glow : float = 1.0 - smoothstep(0.0, halo_radius, holder.global_position.distance_to(other.global_position))
		var in_glow : bool = holder.global_position.distance_to(other.global_position) <= halo_radius
		var beam : float = 0.0 #how strong the beam is on them, 0 to 1, as the scene's beam light would have it
		var in_beam : bool = false
		if distance <= beam_range + body_radius:
			var half : float = deg_to_rad(beam_half_angle_deg)
			var margin : float = asin(clampf(body_radius / maxf(distance, body_radius), 0.0, 1.0)) #the body is wide: part of it is in the beam before its middle is
			var off_axis : float = absf(angle_difference(holder.flashlight.global_rotation, offset.angle())) if distance > 1.0 else 0.0
			in_beam = distance <= body_radius or off_axis <= half + margin
			if in_beam:
				var along : float = pow(maxf(1.0 - distance / beam_range, 0.0), 1.4)
				var side : float = 1.0 - smoothstep(half * 0.55, half, maxf(off_axis - margin, 0.0))
				beam = 1.0 if distance <= body_radius else along * side
		if not (in_glow or in_beam):
			continue
		if holder != other and not get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(origin, other.global_position, WALLS)).is_empty():
			continue
		lit = true
		if holder != me:
			var own_beam : bool = holder == other #(a flashlight does not light its holder from the lamp: only its glow does)
			var energy : float = (0.0 if own_beam else BEAM_ENERGY * beam) + HALO_ENERGY * glow
			added += Color(beam_color.r * energy, beam_color.g * energy, beam_color.b * energy, 0.0) * light_scale
	#a brightening, not a recolouring: every colour channel is multiplied by the SAME gain, so the body keeps its colours (a different gain per channel, from a light much
	#stronger than the dark, pushed them all to white). The gain rises with the light and levels off (it never goes past MAX_BODY_GAIN), so a body in several beams does not burn out.
	var dark : float = maxf((ambient.r + ambient.g + ambient.b) / 3.0, 0.02)
	var strength : float = (added.r + added.g + added.b) / 3.0 / dark
	var gain : float = 1.0 + (MAX_BODY_GAIN - 1.0) * (1.0 - exp(-strength / BODY_GAIN_SOFTNESS))
	return {"lit": lit, "tint": Color(gain, gain, gain, 1.0)}
