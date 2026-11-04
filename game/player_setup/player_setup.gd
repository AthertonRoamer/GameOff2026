class_name PlayerSetup
extends Node

##Handles everything about a freshly spawned player that RollbackPlayerSpawner itself doesn't:
##starting position, display name, lag compensation tracking. Put this in the game scene next
##to the Spawner and LagCompensator, and call setup_player() from player_spawned.

@export var spawn_radius : float = 100.0
@export var hit_radius : float = 25.0 * sqrt(2.0) #covers the 64x64 square collider's corners, not just its edges
@export var lag_compensator : LagCompensator
@export var projectile_manager : ProjectileManager


func setup_player(player : Node, member : LobbyMember, index : int, member_count : int) -> void:
	var angle : float = TAU * index / member_count
	player.position = Vector2.UP.rotated(angle) * spawn_radius
	player.player_name = member.name
	player.lag_compensator = lag_compensator
	player.projectile_manager = projectile_manager
	lag_compensator.track(player, &"position", hit_radius)
