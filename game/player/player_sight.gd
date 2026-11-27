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
##                         the local player is seen without any light, if they are in front of them (in the forward cone, never behind the player's back, and not through walls). A body lit by another player's beam is brightened by it
##                         (the way the scene's lights would), and the drawn beams leave a soft hole round every player, so nobody is seen through a haze.
##   rooms' ceiling lights are drawn by this node too (room_light.gdshader), wherever the local player has a clear line of sight to them in any direction (a ring of
##                         rays round them, `sight_range` long: not the forward view), on the shapes RoomLightShapes works out (the room, and out through its open
##                         doorways). A body in a lit room counts as lit, so it is seen if it is in the forward view, like a body in a flashlight.
##   rooms on camera       (`watched`, set by the door console's CamerasLayer while it shows live feeds): everything in them is seen as a dead player sees it (bodies, their
##                         flashlights as real scene lights, shots, blood, items), because the feeds are other views of the same world and show only what is seen here.
## A dead local player sees everything. Only this peer's picture changes: nothing here is sent to anyone, and the game itself (hits, the simulation) does not look at it.

const GROUP : StringName = &"player_sight" #the node is in this group, so a console's camera feeds can find it
const WALLS : int = SightFan.WALLS
const BEAM_STRENGTH : float = 0.28 #how strongly a beam is laid over the picture at its lamp at light_scale 1: measured against the scene's own beam light (energy 1.7) on the floor
const HALO_STRENGTH : float = 0.14 #the same for the glow round the holder (the scene's halo light has energy 0.55)
const BEAM_ENERGY : float = 1.7 #the scene's beam light's energy, and the halo's: what the light on a body is worked out with
const HALO_ENERGY : float = 0.55
const MAX_BODY_GAIN : float = 2.4 #the most a light brightens a body, as a multiple of its colours in the dark (the colours stay as they are)
const BODY_GAIN_SOFTNESS : float = 4.0 #how quickly a body reaches that: bigger is gentler
const MAX_BODIES : int = 8 #how many players the shader leaves a hole round (the nearest ones)
const MAX_LYING : int = 4 #and how many fallen bodies it leaves a body-shaped hole along

@export var view_half_angle_deg : float = 55.0 #how wide the view reaches forward, to either side of the way the mouse is
@export var view_range : float = 900.0 #in world pixels: further than the screen
@export var view_near : float = 16.0 #how far the view reaches to the sides and behind the player: only what touches them (nothing outside the cone is seen). Keep above 0
@export var view_rays : int = 120 #how finely the view is traced all the way round, so it follows walls
@export_range(0.0, 1.0) var fade_start : float = 0.4 #the view is at full strength out to this share of its reach, then fades to nothing at the edge
@export var beam_range : float = 484.0 #the flashlight's length, in world pixels (11 m)
@export var beam_half_angle_deg : float = 28.0 #the flashlight cone's half angle (see Flashlight.CONE_HALF_ANGLE)
@export var beam_rays : int = 40
@export var beam_color : Color = Color("#fff3c4") #the scene's beam light colour
@export_range(0.0, 1.5) var light_scale : float = 0.75 #how strong the drawn lights are, against the scene's own beam light (1)
@export var halo_radius : float = 40.0 #the glow round a flashlight's holder: a player inside it is seen
@export var near_radius : float = 48.0 #players this close see each other without any light (not through walls)
@export var near_cone_fade_deg : float = 25.0 #a player that close is seen only inside the view's forward cone (view_half_angle_deg), fading out over this many degrees beyond it
@export var fade_seconds : float = 0.12
@export var body_radius : float = 16.0 #a player is lit when any of their body is in a beam, not just their middle
@export var ambient : Color = Color(0.176, 0.186, 0.248) #the facility's darkness (the level's CanvasModulate): a light's brightening of a body is worked out against it. Set by the game
@export_group("Room lights")
@export var sight_range : float = 1100.0 #how far the local player sees a lit room, in any direction (about the screen's half diagonal and a bit)
@export var sight_rays : int = 120 #how finely that line of sight is traced

## () -> Array of every Player. () -> the local Player, or null. Set by the game.
var players : Callable = Callable()
var local_player : Callable = Callable()
## The rooms' lamps, where their light falls, and which are on. Set by the game; unset, lit rooms are seen from anywhere.
var room_lights : RoomLightShapes
## World rectangles of the rooms a camera feed is showing right now (CamerasLayer): everything inside them is seen.
var watched : Array[Rect2] = []

const ROOM_LIGHT_SHADER : Shader = preload("res://game/lights/room_light.gdshader")

var _sight : PackedVector2Array = PackedVector2Array() #the local player's line of sight all the way round (empty: everything is seen)
var _unlights : Array[RemoteBeam] = [] #pooled: one per lit lamp on screen, taking its light back off where the local player cannot see (room_light.gdshader)
var _unlight_layer : CanvasLayer #under _layer, so the drawn beams are not darkened
var _sight_mask : SubViewport #a picture of the screen, white where the local player can see (_sight), for room_light.gdshader
var _sight_shape : Polygon2D

var _view : PackedVector2Array = PackedVector2Array() #the view polygon, in the world (empty: no limit)
var _apex : Vector2
var _facing : float = 0.0
var _alpha : Dictionary = {} #player -> how seen their body is now, 0 to 1
var _lights : Dictionary = {} #player -> {"beam": RemoteBeam, "glow": RemoteBeam}
var _bodies : PackedVector2Array = PackedVector2Array() #where the players are, for the shader's holes
var _lying_a : PackedVector2Array = PackedVector2Array() #the fallen bodies' ends and half widths, for the shader's body-shaped holes
var _lying_b : PackedVector2Array = PackedVector2Array()
var _lying_radius : PackedFloat32Array = PackedFloat32Array()
var _body_holes : PackedFloat32Array = PackedFloat32Array() #how seen each of _bodies is (0 to 1), and so how deep its hole is, so nobody unseen leaves a hole
var _lying_holes : PackedFloat32Array = PackedFloat32Array()
var _layer : CanvasLayer


func _ready() -> void:
	add_to_group(GROUP)
	#the rooms' lamps are real scene lights (RoomLightShapes), so they light the facility the way the flashlight does. Where the local player has no line of
	#sight to a lamp's light, it is taken back off by a multiply pass on this layer, which is under the drawn beams' layer and over the facility
	_unlight_layer = CanvasLayer.new()
	_unlight_layer.name = "RoomLightSight"
	_unlight_layer.follow_viewport_enabled = true
	add_child(_unlight_layer)
	_layer = CanvasLayer.new() #its own layer: the facility's darkness (a CanvasModulate) does not touch it
	_layer.follow_viewport_enabled = true
	add_child(_layer)
	#the line of sight as a picture of the screen, which the multiply pass reads. It has a canvas of its own, so nothing drawn there shows anywhere else
	_sight_mask = SubViewport.new()
	_sight_mask.name = "SightMask"
	_sight_mask.transparent_bg = true
	_sight_mask.disable_3d = true
	_sight_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sight_mask)
	_sight_shape = Polygon2D.new()
	_sight_shape.color = Color.WHITE
	_sight_mask.add_child(_sight_shape)


func _process(delta : float) -> void:
	if not players.is_valid() or not local_player.is_valid():
		return
	var me : Player = local_player.call()
	if not is_instance_valid(me):
		return
	var sees_all : bool = not me.is_alive()
	_update_view(me, sees_all)
	_update_bodies()
	_update_room_lights(me, sees_all)
	for player : Player in players.call():
		if player == me or not is_instance_valid(player):
			continue
		if not _lights.has(player):
			_lights[player] = {"beam": _add_light(), "glow": _add_light()}
			player.paint_flashlight_in_view()
		var sees_them : bool = sees_all or is_watched(player.skin.body_position()) #(on camera: seen like a dead player sees them, so the feed shows them)
		player.flashlight.set_painted(not sees_them) #(a dead local player sees by the scene's own lights: nothing is drawn over the bodies)
		var lighting : Dictionary = {"lit": true, "tint": Color.WHITE} if sees_them else _lighting_of(me, player)
		var target : float = 1.0 if sees_them else _body_seen(me, player, lighting["lit"])
		var alpha : float = move_toward(_alpha.get(player, target), target, delta / maxf(fade_seconds, 0.001))
		_alpha[player] = alpha
		player.set_body_seen(alpha, lighting["tint"])
		player.set_muzzle_seen(sees_them or visibility(player.global_position) > 0.3)
		_update_lights(player, sees_them)
	me.set_body_seen(1.0, Color.WHITE if sees_all else _lighting_of(me, me)["tint"]) #(the local player's own body is lit by the others' drawn lights too, alive or fallen)


func _add_light() -> RemoteBeam:
	var light : RemoteBeam = RemoteBeam.new()
	_layer.add_child(light)
	return light


## How well the local player sees this point, 0 (not at all) to 1: inside the view, fading towards its edge, and not behind a wall or a shut door.
## Everything is seen when there is no view (the local player is dead).
func visibility(point : Vector2) -> float:
	if _view.is_empty() or is_watched(point):
		return 1.0
	var strength : float = view_strength(point)
	if strength <= 0.0:
		return 0.0
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(_apex, point, WALLS)
	return strength if get_world_2d().direct_space_state.intersect_ray(query).is_empty() else 0.0


## Is this point in a room a camera feed is showing (`watched`)?
func is_watched(point : Vector2) -> bool:
	for rect : Rect2 in watched:
		if rect.has_point(point):
			return true
	return false


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


## A fan of rays stopped by walls and shut doors (see SightFan.fan).
func _fan(origin : Vector2, angle_from : float, angle_to : float, rays : int, reach_at : Callable, mask : int = WALLS) -> PackedVector2Array:
	return SightFan.fan(get_world_2d().direct_space_state, origin, angle_from, angle_to, rays, reach_at, mask)


## Where the players are (the nearest few, to the local player): the shader leaves a soft hole round each in the drawn lights, so the body is lit by its own brightening only.
## A fallen body is long and lies away from where its player stood: its hole is a capsule along it (see `_lying`).
func _update_bodies() -> void:
	var all : Array = players.call()
	all = all.filter(func(p) -> bool: return is_instance_valid(p))
	all.sort_custom(func(a : Player, b : Player) -> bool: return a.skin.body_position().distance_squared_to(_apex) < b.skin.body_position().distance_squared_to(_apex))
	_bodies = PackedVector2Array()
	_body_holes = PackedFloat32Array()
	_lying_a = PackedVector2Array()
	_lying_b = PackedVector2Array()
	_lying_radius = PackedFloat32Array()
	_lying_holes = PackedFloat32Array()
	var me : Player = local_player.call()
	for player : Player in all:
		#a hole only as deep as the body is seen: a hole round someone the local player cannot see (out of the view, behind a wall) would give them away
		#and none round the local player's own body
		var seen : float = 0.0 if player == me else _alpha.get(player, 0.0)
		if seen <= 0.001:
			continue
		var at : Vector2 = player.skin.body_position()
		var axis : Vector2 = player.skin.body_axis()
		if axis.is_zero_approx():
			if _bodies.size() < MAX_BODIES:
				_bodies.append(at)
				_body_holes.append(seen)
		elif _lying_a.size() < MAX_LYING:
			_lying_a.append(at - axis)
			_lying_b.append(at + axis)
			_lying_radius.append(player.skin.body_half_width())
			_lying_holes.append(seen)
	while _bodies.size() < MAX_BODIES:
		_bodies.append(Vector2(1.0e7, 1.0e7))
		_body_holes.append(0.0)
	while _lying_a.size() < MAX_LYING:
		_lying_a.append(Vector2(1.0e7, 1.0e7))
		_lying_b.append(Vector2(1.0e7, 1.0e7))
		_lying_radius.append(1.0)
		_lying_holes.append(0.0)

## Sets up the drawn beam and glow of another player's flashlight for this frame: their shapes (where the light reaches, cut to the view) and the shader's numbers.
func _update_lights(player : Player, sees_all : bool) -> void:
	var lights : Dictionary = _lights[player]
	var beam : RemoteBeam = lights["beam"]
	var glow : RemoteBeam = lights["glow"]
	if sees_all or not player.flashlight.on or not player.is_alive():
		beam.polygons = []
		glow.polygons = []
		return
	var origin : Vector2 = player.flashlight.global_position
	var direction : float = player.flashlight.global_rotation
	var half : float = deg_to_rad(beam_half_angle_deg)
	var beam_reach : Callable = func(_angle : float) -> float: return beam_range
	beam.polygons = _in_view(_fan(origin, direction - half, direction + half, beam_rays, beam_reach, SightFan.BEAMS)) #(furniture casts a shadow in a beam, like the scene's own beam light)
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


## The rooms' lamps light the facility for everyone (RoomLightShapes). The local player should see a lamp's light only where they have a line of sight to it,
## all the way round (not only forward): walls and shut doors hide a lit room behind them. So over each lit lamp on screen, a multiply pass takes its light back
## off wherever the sight mask (a picture of the screen, white where the local player can see) is dark. A dead local player sees everything: no pass.
func _update_room_lights(me : Player, sees_all : bool) -> void:
	var used : int = 0
	var view_size : Vector2 = get_viewport().get_visible_rect().size
	var to_screen : Transform2D = get_viewport().get_canvas_transform()
	if room_lights != null and room_lights.facility != null and not sees_all:
		var any_on : bool = false
		for source in room_lights.source_count():
			if room_lights.is_source_on(source):
				any_on = true
				break
		_sight = PackedVector2Array()
		if any_on:
			var reach : Callable = func(_angle : float) -> float: return sight_range
			#over furniture: the floor behind a generator is drawn, so a light missing there would look like a shadow, and a ceiling light casts none
			_sight = SightFan.ring(get_world_2d().direct_space_state, me.global_position, sight_rays, reach, WALLS, room_lights.furniture())
			if _sight_mask.size != Vector2i(view_size.ceil()):
				_sight_mask.size = Vector2i(view_size.ceil())
			_sight_mask.canvas_transform = to_screen #(the mask is the screen: world -> screen pixels)
			_sight_shape.polygon = _sight
		var screen : Rect2 = to_screen.affine_inverse() * get_viewport().get_visible_rect()
		var map : FacilityMap = room_lights.facility
		var count : int = room_lights.source_count() if any_on else 0
		for source in count:
			if not room_lights.is_source_on(source):
				continue
			var reach_rect : Rect2 = map.get_global_transform() * room_lights.reach_rect(source)
			if not reach_rect.intersects(screen):
				continue
			if used >= _unlights.size():
				var fresh : RemoteBeam = RemoteBeam.new()
				fresh.shader_material.shader = ROOM_LIGHT_SHADER
				_unlight_layer.add_child(fresh)
				fresh.shader_material.set_shader_parameter("sight_mask", _sight_mask.get_texture())
				_unlights.append(fresh)
			var unlight : RemoteBeam = _unlights[used]
			used += 1
			unlight.polygons.assign(room_lights.polygons(source)) #(where its light falls: the light is taken off only there, never darkening what it does not light)
			var rect : Rect2 = map.get_global_transform() * map.light_source_rect_px(source)
			var paint : ShaderMaterial = unlight.shader_material
			paint.set_shader_parameter("rect_pos", rect.position)
			paint.set_shader_parameter("rect_size", rect.size)
			paint.set_shader_parameter("spill", room_lights.spill_px())
			paint.set_shader_parameter("light_color", room_lights.color)
			paint.set_shader_parameter("energy", room_lights.energy)
			paint.set_shader_parameter("ambient", ambient)
	for i in range(used, _unlights.size()):
		_unlights[i].polygons = []


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
	_set_body_uniforms(shader_material)


## The players for the shader's holes (see _update_bodies).
func _set_body_uniforms(shader_material : ShaderMaterial) -> void:
	shader_material.set_shader_parameter("bodies", _bodies)
	shader_material.set_shader_parameter("body_count", MAX_BODIES)
	shader_material.set_shader_parameter("lying_a", _lying_a)
	shader_material.set_shader_parameter("lying_b", _lying_b)
	shader_material.set_shader_parameter("lying_radius", _lying_radius)
	shader_material.set_shader_parameter("body_seen", _body_holes)
	shader_material.set_shader_parameter("lying_seen", _lying_holes)


## How much the way the local player faces lets them see a point that is close: 1 inside the view's forward cone, fading to 0 just outside it, so nobody close is seen
## behind the player's back. Someone almost touching (inside body_radius) is always seen: they are in the way.
func _cone(point : Vector2, distance : float) -> float:
	if _view.is_empty() or distance <= body_radius:
		return 1.0
	var off_axis : float = absf(angle_difference(_facing, (point - _apex).angle()))
	var half : float = deg_to_rad(view_half_angle_deg)
	return 1.0 - smoothstep(half, half + deg_to_rad(near_cone_fade_deg), off_axis)


## How much of another player's body is seen: very close and unblocked, or inside the view and lit.
func _body_seen(me : Player, other : Player, lit : bool) -> float:
	var at : Vector2 = other.skin.body_position() #(a fallen body lies away from where its player stood)
	var space : PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var near : float = 0.0
	var distance : float = me.global_position.distance_to(at)
	if distance <= near_radius and space.intersect_ray(PhysicsRayQueryParameters2D.create(me.global_position, at, WALLS)).is_empty():
		near = (1.0 - smoothstep(near_radius * 0.6, near_radius, distance)) * _cone(at, distance)
	var seen_lit : float = visibility(at) if lit else 0.0
	return maxf(near, seen_lit)


## The light on another player: {"lit": whether a flashlight (any player's, the local player's too) is on them, in the glow round its holder (the holder included) or in
## its beam with nothing solid between, "tint": what the drawn lights multiply their colours by}. Only the other players' flashlights tint a body: the local player's own beam is
## a scene light, which already brightens what it falls on, the way the drawn ones are made to look like.
func _lighting_of(me : Player, other : Player) -> Dictionary:
	var at : Vector2 = other.skin.body_position()
	var lit : bool = false
	var added : Color = Color(0, 0, 0, 0) #the light that falls on them, in the scene lights' units
	for holder : Player in players.call():
		if not is_instance_valid(holder) or not holder.flashlight.on or not holder.is_alive():
			continue
		var origin : Vector2 = holder.flashlight.global_position
		var offset : Vector2 = at - origin
		var distance : float = offset.length()
		var glow : float = 1.0 - smoothstep(0.0, halo_radius, holder.global_position.distance_to(at))
		var in_glow : bool = holder.global_position.distance_to(at) <= halo_radius
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
		var blockers : int = WALLS if in_glow else SightFan.BEAMS #(furniture shadows a beam, not the glow round its holder)
		if holder != other and not get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(origin, at, blockers)).is_empty():
			continue
		lit = true
		if holder != me:
			var own_beam : bool = holder == other #(a flashlight does not light its holder from the lamp: only its glow does)
			var energy : float = (0.0 if own_beam else BEAM_ENERGY * beam) + HALO_ENERGY * glow
			added += Color(beam_color.r * energy, beam_color.g * energy, beam_color.b * energy, 0.0) * light_scale
	if room_lights != null and room_lights.light_at(at) > 0.02: #a lit room lights everyone in it (its shape already stops at walls and shut doors). Seen, not tinted:
		lit = true #the room light's shader brightens the body itself, as it does the floor
	#a brightening, not a recolouring: every colour channel is multiplied by the SAME gain, so the body keeps its colours (a different gain per channel, from a light much
	#stronger than the dark, pushed them all to white). The gain rises with the light and levels off (it never goes past MAX_BODY_GAIN), so a body in several beams does not burn out.
	var dark : float = maxf((ambient.r + ambient.g + ambient.b) / 3.0, 0.02)
	var strength : float = (added.r + added.g + added.b) / 3.0 / dark
	var gain : float = 1.0 + (MAX_BODY_GAIN - 1.0) * (1.0 - exp(-strength / BODY_GAIN_SOFTNESS))
	return {"lit": lit, "tint": Color(gain, gain, gain, 1.0)}
