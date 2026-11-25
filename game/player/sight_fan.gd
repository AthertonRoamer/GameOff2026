class_name SightFan
extends RefCounted

## A fan of rays from a point, stopped by walls and shut doors: what a light or an eye there reaches. Used by PlayerSight (the view, the flashlight beams it draws,
## the local player's line of sight) and by RoomLightShapes (where a room's ceiling light falls).

const WALLS : int = FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER
const BEAMS : int = WALLS | FacilityTileSet.PROP_LAYER #what stops a flashlight beam: walls, shut doors and furniture (which has a LightOccluder2D for the scene's own lights)
const REFINE_GAP : float = 14.0 #two neighbouring rays that land this much further apart than that get a ray between them (a corner, a doorway)
const REFINE_DEPTH : int = 8 #how many times a gap is halved at most
const MAX_FAN_POINTS : int = 420 #however many corners there are, a fan stays this small


## The points a fan of rays from `origin` reaches between two angles, each out to reach_at(angle) or the first wall: origin first, then the hits in order. Where two
## neighbouring rays land far apart (a corner, a doorway) rays are added between them by halving the gap, so the fan's edge follows the corner and does not cut across it.
static func fan(space : PhysicsDirectSpaceState2D, origin : Vector2, angle_from : float, angle_to : float, rays : int, reach_at : Callable, mask : int = WALLS, exclude : Array[RID] = []) -> PackedVector2Array:
	var full_circle : bool = angle_to - angle_from >= TAU - 0.001 #(the last ray would be the first again)
	var result : PackedVector2Array = PackedVector2Array([origin])
	var angle : float = angle_from
	var previous : Vector2 = cast(space, origin, angle, reach_at, mask, exclude)
	var first : Vector2 = previous
	result.append(previous)
	for i in range(1, rays + 1):
		var next_angle : float = angle_from + (angle_to - angle_from) * i / rays
		var last_again : bool = full_circle and i == rays
		var next : Vector2 = first if last_again else cast(space, origin, next_angle, reach_at, mask, exclude)
		_refine(space, origin, angle, previous, next_angle, next, REFINE_DEPTH, reach_at, mask, exclude, result)
		if not last_again:
			result.append(next)
		angle = next_angle
		previous = next
	return result


## A whole circle round `origin` as a closed polygon (the fan without its centre point).
static func ring(space : PhysicsDirectSpaceState2D, origin : Vector2, rays : int, reach_at : Callable, mask : int = WALLS, exclude : Array[RID] = []) -> PackedVector2Array:
	return fan(space, origin, -PI, PI, rays, reach_at, mask, exclude).slice(1)


static func cast(space : PhysicsDirectSpaceState2D, origin : Vector2, angle : float, reach_at : Callable, mask : int = WALLS, exclude : Array[RID] = []) -> Vector2:
	var far : Vector2 = origin + Vector2.from_angle(angle) * reach_at.call(angle)
	var hit : Dictionary = space.intersect_ray(PhysicsRayQueryParameters2D.create(origin, far, mask, exclude))
	return hit["position"] if not hit.is_empty() else far


static func _refine(space : PhysicsDirectSpaceState2D, origin : Vector2, angle_a : float, point_a : Vector2, angle_b : float, point_b : Vector2, depth : int, reach_at : Callable, mask : int, exclude : Array[RID], out : PackedVector2Array) -> void:
	if depth <= 0 or out.size() > MAX_FAN_POINTS or absf(origin.distance_to(point_a) - origin.distance_to(point_b)) < REFINE_GAP:
		return
	var angle_mid : float = (angle_a + angle_b) / 2.0
	var point_mid : Vector2 = cast(space, origin, angle_mid, reach_at, mask, exclude)
	_refine(space, origin, angle_a, point_a, angle_mid, point_mid, depth - 1, reach_at, mask, exclude, out)
	out.append(point_mid)
	_refine(space, origin, angle_mid, point_mid, angle_b, point_b, depth - 1, reach_at, mask, exclude, out)
