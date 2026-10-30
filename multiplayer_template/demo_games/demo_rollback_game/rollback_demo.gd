class_name RollbackDemo
extends Node2D

##Demo game for the rollback template: players move around an arena with client-side prediction.
##Use it by setting game_manager_scene to rollback_game_manager.tscn and game_scene to rollback_demo.tscn (rollback_demo_configuration.tres does both).

@export var first_pos : Vector2 = Vector2(100, 100)
@export var spacing : float = 100.0
@export var respawn_first_pos : Vector2 = Vector2(400, 400) #where dead players come back, spread out by spacing like first_pos

var started : bool = false #true once RollbackGameManager has called start(), on the agreed tick

@onready var spawner : RollbackPlayerSpawner = $Spawner


func _ready() -> void:
	spawner.player_spawned.connect(_on_player_spawned)
	if get_parent() is GameManager:
		var lobby : Lobby = get_parent().lobby
		spawner.setup(lobby)
		spawner.spawn_all()
		if lobby.is_master: #the lobby process is a headless referee, it only simulates
			#visible = false
			$"CanvasLayer/Quit Game".visible = false
	$ProjectileManager.lag_compensator = $LagCompensator
	$ProjectileManager.can_hit = func(target : Node) -> bool: return target.is_alive()
	$ProjectileManager.projectile_hit.connect(_on_projectile_hit) #only the lobby emits it


func start() -> void:
	started = true
	set_players_active(true)


func end() -> void:
	$NetworkUnloader.initiate_unload()


func set_players_active(active : bool) -> void:
	for player in spawner.players.values():
		if is_instance_valid(player):
			player.set_active(active)


func _on_player_spawned(player : RollbackDemoPlayer, member : LobbyMember, index : int) -> void:
	player.id = member.id
	player.player_name = member.name
	player.lag_compensator = $LagCompensator
	$LagCompensator.track(player, &"position", 32.0)
	player.position = Vector2(first_pos.x + spacing * index, first_pos.y)
	player.spawn_position = Vector2(respawn_first_pos.x + spacing * index, respawn_first_pos.y)
	player.projectile_manager = $ProjectileManager


func _on_projectile_hit(projectile : Dictionary, target : Node) -> void:
	target.take_damage(projectile["damage"])


func _on_network_unloader_cease_rpcs_request_received() -> void:
	$ProjectileManager.quiesce()
	set_players_active(false)
	spawner.quiesce()
	($NetworkUnloader as NetworkUnloader).register_as_ceased()


func _on_quit_game_pressed() -> void:
	if get_parent().lobby.has_authority:
		get_parent().lobby.trigger_request_end_game()
	else:
		Main.mode.leave_lobby()
