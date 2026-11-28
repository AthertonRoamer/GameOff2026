class_name SmokeCloud
extends Node2D

##A cloud of smoke from a smoke bomb (SmokeBombItem). It billows out over grow_seconds, hangs for hold_seconds and thins away over fade_seconds, then is gone.
##While it is thick it blocks sight: a line of sight that runs more than SEE_THROUGH_PX through it sees nothing beyond (blocks()). PlayerSight asks for players,
##items, shots and blood; turrets ask before they aim; a camera feed shows the cloud itself, drawn over everything in it. Someone standing in it sees only what is
##right next to them. Shots go through it: it hides, it does not shield.
##Made on every peer on the same tick (the throw is a PickupControl change), so the lobby's turrets and every player's view agree on where it is.

const GROUP : StringName = &"smoke_clouds"
const SEE_THROUGH_PX : float = 36.0 ## how much smoke a line of sight can pass through before it is blocked (someone in the cloud sees who is touching them)
const Z : int = 6 ## drawn over the players and the walls

@export var radius_px : float = 120.0
@export var grow_seconds : float = 1.2
@export var hold_seconds : float = 14.0
@export var fade_seconds : float = 3.0

var age : float = 0.0
var _puffs : Array[Dictionary] = [] #{"at": Vector2 (offset), "r": float, "spin": float}: the look of it, a few overlapping blobs


func _init() -> void:
	z_index = Z
	add_to_group(GROUP)


func _ready() -> void:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(global_position) #(the same on every peer, though only the look depends on it)
	for i in 14:
		var along : float = sqrt(rng.randf()) * radius_px * 0.62
		_puffs.append({"at": Vector2.from_angle(rng.randf() * TAU) * along, "r": radius_px * rng.randf_range(0.32, 0.5), "spin": rng.randf_range(-0.3, 0.3)})


func _process(delta : float) -> void:
	age += delta
	if age >= lifetime():
		queue_free()
		return
	queue_redraw()


func lifetime() -> float:
	return grow_seconds + hold_seconds + fade_seconds


## How thick it is now, 0 to 1.
func density() -> float:
	if age < grow_seconds:
		return smoothstep(0.0, grow_seconds, age)
	if age < grow_seconds + hold_seconds:
		return 1.0
	return 1.0 - smoothstep(0.0, fade_seconds, age - grow_seconds - hold_seconds)


## How far it reaches now (it billows out as it grows).
func reach() -> float:
	return radius_px * (0.35 + 0.65 * smoothstep(0.0, grow_seconds, age))


## How much of the line from a to b runs through this cloud, in px, weighted by how thick it is.
func smoke_between(a : Vector2, b : Vector2) -> float:
	var r : float = reach()
	var centre : Vector2 = global_position
	var along : Vector2 = b - a
	var length : float = along.length()
	if length < 0.001:
		return 0.0
	var dir : Vector2 = along / length
	var t : float = (centre - a).dot(dir)
	var closest : float = (a + dir * t).distance_to(centre)
	if closest >= r:
		return 0.0
	var half : float = sqrt(r * r - closest * closest)
	var inside : float = clampf(t + half, 0.0, length) - clampf(t - half, 0.0, length)
	return maxf(inside, 0.0) * density()


## Whether smoke hides b from someone at a (every cloud in the tree counts).
static func blocks(tree : SceneTree, a : Vector2, b : Vector2) -> bool:
	if tree == null:
		return false
	var total : float = 0.0
	for node : Node in tree.get_nodes_in_group(GROUP):
		var cloud : SmokeCloud = node as SmokeCloud
		if cloud != null and not cloud.is_queued_for_deletion():
			total += cloud.smoke_between(a, b)
			if total > SEE_THROUGH_PX:
				return true
	return false


func _draw() -> void:
	var thick : float = density()
	var grown : float = reach() / radius_px
	for puff : Dictionary in _puffs:
		var at : Vector2 = (puff["at"] as Vector2).rotated(float(puff["spin"]) * age * 0.2) * grown
		var r : float = float(puff["r"]) * grown
		for ring in 3: #soft edges: each blob is three circles, fainter outward
			draw_circle(at, r * (1.0 - ring * 0.18), Color(0.62, 0.64, 0.66, 0.2 * thick))
	draw_circle(Vector2.ZERO, reach() * 0.55, Color(0.66, 0.68, 0.7, 0.35 * thick))
