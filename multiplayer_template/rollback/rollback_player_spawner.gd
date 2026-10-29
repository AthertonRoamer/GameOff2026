class_name RollbackPlayerSpawner
extends Node

##Spawns one player per lobby member as children of this node, set up the way netfox rollback needs it.
##Every peer (including the lobby) runs the same spawn_all(), so node names and paths match without a MultiplayerSpawner.
##Authority: the player body belongs to the lobby (peer 1), the input node belongs to the member's own peer.
##Put this node in the game scene and call setup(lobby) then spawn_all(), usually from the game's _ready().
##Set position and other starting state in a player_spawned handler, it fires before the player enters the tree.

signal player_spawned(player : Node, member : LobbyMember, index : int)
signal player_removed(player : Node, member : LobbyMember)

@export var player_scene : PackedScene
@export var input_node_name : StringName = &"Input"

var lobby : Lobby
var players : Dictionary = {} #key: member id (int), value: player node
var local_player : Node


func setup(p_lobby : Lobby) -> void:
	lobby = p_lobby
	if not lobby.member_left.is_connected(_on_member_left):
		lobby.member_left.connect(_on_member_left)


func spawn_all() -> void:
	assert(lobby != null, "RollbackPlayerSpawner.setup() must be called before spawn_all()")
	var index : int = 0
	for member in lobby.members:
		spawn_player(member, index)
		index += 1


func spawn_player(member : LobbyMember, index : int = 0) -> Node:
	if player_scene == null:
		push_warning("RollbackPlayerSpawner has no player scene")
		return null
	if players.has(member.id):
		return players[member.id]
	var player : Node = player_scene.instantiate()
	player.name = str(member.id)
	player.set_multiplayer_authority(1) #recursive, so this has to come before the input node gets its own owner
	var input : Node = player.get_node_or_null(NodePath(input_node_name))
	if input != null:
		input.set_multiplayer_authority(member.id)
	else:
		push_warning("Player scene has no input node named " + str(input_node_name))
	players[member.id] = player
	if member.id == multiplayer.get_unique_id():
		local_player = player
	player_spawned.emit(player, member, index)
	add_child(player)
	return player


func quiesce() -> void:
	##Stops every player's RollbackSynchronizers from sending state and input, without freeing anything.
	##Call this when the game is about to be unloaded (NetworkUnloader's cease step), then free the game once every peer has ceased.
	##Freeing rollback nodes while other peers are still transmitting to them logs "Node not found" RPC errors.
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return #this peer already left, so nothing of ours is being sent and the synchronizers cannot be reconfigured
	for player in players.values():
		if not is_instance_valid(player):
			continue
		for synchronizer in player.find_children("*", "RollbackSynchronizer", true, false):
			synchronizer.state_properties = [] as Array[String]
			synchronizer.input_properties = [] as Array[String]
			synchronizer.process_settings()
		for synchronizer in player.find_children("*", "StateSynchronizer", true, false):
			synchronizer.properties = [] as Array[String]
			synchronizer.process_settings()


func remove_player(member_id : int) -> void:
	if not players.has(member_id):
		return
	var player : Node = players[member_id]
	players.erase(member_id)
	if player == local_player:
		local_player = null
	if is_instance_valid(player):
		player.queue_free()


func _on_member_left(member : LobbyMember) -> void:
	if players.has(member.id):
		player_removed.emit(players[member.id], member)
		remove_player(member.id)
