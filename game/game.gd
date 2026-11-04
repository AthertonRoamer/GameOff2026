class_name Game
extends Node2D

##Main game scene. Set player_scene on $Spawner once a player scene exists, then set
##game_manager_scene to rollback_game_manager.tscn and game_scene to this scene in a Configuration resource.

@onready var spawner : RollbackPlayerSpawner = $Spawner
@onready var player_setup : PlayerSetup = $PlayerSetup


func _ready() -> void:
	spawner.player_spawned.connect(_on_player_spawned)
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


func _on_network_unloader_cease_rpcs_request_received() -> void:
	set_players_active(false)
	spawner.quiesce()
	($NetworkUnloader as NetworkUnloader).register_as_ceased()
