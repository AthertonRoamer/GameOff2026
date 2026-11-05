class_name Game
extends Node2D

##Main game scene. Set player_scene on $Spawner once a player scene exists, then set
##game_manager_scene to rollback_game_manager.tscn and game_scene to this scene in a Configuration resource.
##The world itself (map, darkness, projectiles, doors, consoles) is the Level, shared with the playground. Players are spawned into its actors
##node, so they are y-sorted with the rest of the facility.
##DebugRemover (the first child) turns every debug setting in this scene off when it is enabled; see game/debug/debug_remover.gd.

const DEBUG_SETTINGS : Array[StringName] = [&"debug_respawn_dead_players"] #turned off by DebugRemover

@export_group("Debug")
@export var debug_respawn_dead_players : bool = false #hides dead players and revives them (full health) after 3 seconds

@onready var level : NightShiftLevel = $Level
@onready var spawner : RollbackPlayerSpawner = $Spawner
@onready var player_setup : PlayerSetup = $PlayerSetup
@onready var player_hud : CanvasLayer = $PlayerHud
@onready var lag_compensator : LagCompensator = $LagCompensator


func _ready() -> void:
	spawner.spawn_parent = level.actors
	spawner.player_spawned.connect(_on_player_spawned)
	level.player_lookup = func(peer_id : int) -> Player: return spawner.players.get(peer_id)
	level.projectiles.lag_compensator = lag_compensator
	level.projectiles.can_hit = func(target : Node) -> bool: return target.is_alive()
	level.projectiles.projectile_hit.connect(_on_projectile_hit)
	player_setup.lag_compensator = lag_compensator
	player_setup.projectile_manager = level.projectiles
	player_setup.spawn_point = level.spawn_position()
	if get_parent() is GameManager:
		var lobby : Lobby = get_parent().lobby
		spawner.setup(lobby)
		spawner.spawn_all()


func start() -> void:
	level.control.broadcast_snapshot() #lobby only: every peer starts from the lobby's doors
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
	level.projectiles.quiesce()
	level.control.quiesce()
	spawner.quiesce()
	($NetworkUnloader as NetworkUnloader).register_as_ceased()
