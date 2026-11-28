class_name Knife
extends Item

##A knife: a blow at arm's length, held out like a gun (click to strike). It needs no ammunition and makes no noise: no shot is heard, no tracer or muzzle flash is
##seen, and nobody else is told it happened (HitscanManager.fire with melee). A blow from behind (it travels the way the target faces) does
##backstab_multiplier times the damage, enough to kill outright. The lobby decides the hit, rewound to where the attacker saw the target, like a shot.

@export var damage : float = 26.0 ## a blow from the front: two take a fresh player down
@export_range(1.0, 5.0, 0.1) var backstab_multiplier : float = 2.0 ## from behind
@export_range(10.0, 120.0, 1.0, "suffix:px") var reach_px : float = 30.0 ## past the end of the arm (Player.muzzle_distance)


func _init() -> void:
	drawable = true


func use(user : Player, tick : int) -> void:
	if user.hitscan_manager == null:
		return
	var direction : Vector2 = (user.input.aim - user.global_position).normalized()
	if direction.is_zero_approx():
		return
	var origin : Vector2 = user.global_position + direction * minf(user.muzzle_distance, 12.0) #(from the shoulder: a target pressed against the attacker is still struck)
	if user.is_inside_tree(): #a wall right there stops the blow, as it lowers a gun
		var hit : Dictionary = user.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(user.global_position, origin, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER))
		if not hit.is_empty():
			return
	user.hitscan_manager.fire(user, user.input.get_multiplayer_authority(), origin, direction, tick, damage, reach_px + user.muzzle_distance, user.input.view_lag, Color.TRANSPARENT, 1, 0.0, true, backstab_multiplier)
