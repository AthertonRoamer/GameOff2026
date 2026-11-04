class_name Game
extends Node2D

##Main game scene. Set player_scene on $Spawner once a player scene exists, then set
##game_manager_scene to rollback_game_manager.tscn and game_scene to this scene in a Configuration resource.

@export var debug_respawn_dead_players : bool = false #hides dead players and revives them (full health) after 3 seconds

@onready var spawner : RollbackPlayerSpawner = $Spawner
@onready var player_setup : PlayerSetup = $PlayerSetup
@onready var player_hud : CanvasLayer = $PlayerHud


func _ready() -> void:
	spawner.player_spawned.connect(_on_player_spawned)
	$ProjectileManager.lag_compensator = $LagCompensator
	$ProjectileManager.can_hit = func(target : Node) -> bool: return target.is_alive()
	$ProjectileManager.projectile_hit.connect(_on_projectile_hit)
	if get_parent() is GameManager:
		var lobby : Lobby = get_parent().lobby
		spawner.setup(lobby)
		spawner.spawn_all()


func start() -> void:
	set_players_active(true)


func end() -> void:
	$NetworkUnloader.initiate_unload()


func set_players_active(active : bool) -> void:
	for player in spawner.players.values():
		if is_instance_valid(player):
			player.set_active(active)


func _on_player_spawned(player : Node, member : LobbyMember, index : int) -> void:
	player_setup.setup_player(player, member, index, spawner.lobby.members.size())
	if player == spawner.local_player:
		player_hud.bind_player(player)
	if debug_respawn_dead_players:
		player.died.connect(_on_player_died.bind(player))
		player.health_changed.connect(_on_player_health_changed.bind(player))


func _on_player_died(player : Node) -> void:
	player.visible = false
	if player.is_multiplayer_authority(): #only the authority decides when health comes back; HealthSynchronizer broadcasts it
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(player):
			player.health = player.starting_health


func _on_player_health_changed(h : float, player : Node) -> void:
	if h > 0:
		player.visible = true


func _on_projectile_hit(projectile : Dictionary, target : Node) -> void:
	target.take_damage(projectile["damage"])


func _on_network_unloader_cease_rpcs_request_received() -> void:
	set_players_active(false)
	$ProjectileManager.quiesce()
	spawner.quiesce()
	($NetworkUnloader as NetworkUnloader).register_as_ceased()
