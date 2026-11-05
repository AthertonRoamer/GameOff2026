class_name PlayerSetup
extends Node

##Handles everything about a freshly spawned player that RollbackPlayerSpawner itself doesn't:
##starting position, display name, lag compensation tracking. Put this in the game scene next
##to the Spawner and LagCompensator, and call setup_player() from player_spawned.

@export var spawn_point : Vector2 = Vector2.ZERO #the middle of the starting line (the game sets it to the level's spawn room)
@export var spawn_spacing : float = 40.0 #players start side by side in a row across spawn_point, so they fit in a corridor
@export var hit_radius : float = 16.0 #a little more than the 12 px body circle
@export var lag_compensator : LagCompensator
@export var projectile_manager : ProjectileManager


func setup_player(player : Node, member : LobbyMember, index : int, member_count : int) -> void:
	player.position = spawn_point + Vector2((index - (member_count - 1) / 2.0) * spawn_spacing, 0.0)
	player.player_name = member.name
	player.lag_compensator = lag_compensator
	player.projectile_manager = projectile_manager
	lag_compensator.track(player, &"position", hit_radius)
