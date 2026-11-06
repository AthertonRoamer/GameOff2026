class_name Game
extends Node2D

##Main game scene. Set player_scene on $Spawner once a player scene exists, then set
##game_manager_scene to rollback_game_manager.tscn and game_scene to this scene in a Configuration resource.
##The world itself (map, darkness, projectiles, doors, consoles) is the Level, shared with the playground. Players are spawned into its actors
##node, so they are y-sorted with the rest of the facility.
##DebugRemover (the first child) turns every debug setting in this scene off when it is enabled; see game/debug/debug_remover.gd.
##
##Roles and teams: when the game loads, the lobby randomly gives every member a role (public) and a team (secret), see RoleAssigner.
##Each client asks the lobby for its share before it spawns the players; the lobby spawns its own copies once every client has spawned.
##The game reports itself loaded only once it has spawned them
##(is_setup_complete, waited for by RollbackGameManager), so every peer has its players before the shared start tick.

const DEBUG_SETTINGS : Array[StringName] = [&"debug_respawn_dead_players", &"debug_show_role_rings", &"debug_show_team_rings"] #turned off by DebugRemover

signal setup_complete #the players have been spawned with their roles and teams

@export_group("Roles and teams")
@export var guard_roles : Array[Role] = [] #every guard gets a different one while they last
@export var intruder_roles : Array[Role] = []
@export var intruder_count : int = 1
@export var attacking_guard_count : int = 1 #guards who are secretly attackers. At least one guard always defends
@export var intruders_know_attackers : bool = true #intruders are told which guards are secretly on their side
@export var attacking_guards_know_each_other : bool = false #secretly attacking guards are told about each other

@export_group("Debug")
@export var debug_respawn_dead_players : bool = false #hides dead players and revives them (full health) after 3 seconds
@export var debug_show_role_rings : bool = false #a ring in each player's role colour
@export var debug_show_team_rings : bool = false #green rings around defenders, red around attackers. Every peer is told every team for this

@onready var level : NightShiftLevel = $Level
@onready var spawner : RollbackPlayerSpawner = $Spawner
@onready var player_setup : PlayerSetup = $PlayerSetup
@onready var player_hud : CanvasLayer = $PlayerHud
@onready var lag_compensator : LagCompensator = $LagCompensator

var role_assigner : RoleAssigner = RoleAssigner.new()
var assignment : Dictionary = {} #lobby: every member's role and team. The win check will use it
var _roles : Dictionary = {} #member id -> role index, every member
var _known_teams : Dictionary = {} #member id -> Team, only the teams this peer may know
var _setup_complete : bool = false
var _spawned_members : Dictionary = {} #lobby: members whose game has spawned the players


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
	_configure_role_assigner()
	if debug_show_role_rings or debug_show_team_rings:
		_add_debug_rings()
	if get_parent() is GameManager:
		var lobby : Lobby = get_parent().lobby
		spawner.setup(lobby)
		if lobby.is_master:
			_ensure_assignment()
			lobby.member_left.connect(func(_m : LobbyMember) -> void: _spawn_on_lobby_when_ready())
			_spawn_on_lobby_when_ready() #no members: spawns now
		else:
			_request_assignment.rpc_id(1)


func start() -> void:
	level.control.broadcast_snapshot() #lobby only: every peer starts from the lobby's doors
	set_players_active(true)


func end() -> void:
	$NetworkUnloader.initiate_unload()


func is_setup_complete() -> bool:
	return _setup_complete


func set_players_active(active : bool) -> void:
	for player in spawner.players.values():
		if is_instance_valid(player):
			player.set_active(active)


func _configure_role_assigner() -> void:
	role_assigner.guard_roles = guard_roles
	role_assigner.intruder_roles = intruder_roles
	role_assigner.intruder_count = intruder_count
	role_assigner.attacking_guard_count = attacking_guard_count
	role_assigner.intruders_know_attackers = intruders_know_attackers
	role_assigner.attacking_guards_know_each_other = attacking_guards_know_each_other
	role_assigner.everyone_knows_all_teams = debug_show_team_rings


##Lobby only: rolls the roles and teams the first time it is needed.
func _ensure_assignment() -> void:
	if not assignment.is_empty():
		return
	var member_ids : Array[int] = []
	for member in spawner.lobby.members:
		member_ids.append(member.id)
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	assignment = role_assigner.assign(member_ids, rng)


##Client -> lobby. Asked instead of pushed: the lobby's game always exists by the time a client's request arrives, whereas a pushed
##answer could reach a client before its own game had loaded.
@rpc("any_peer", "call_remote", "reliable")
func _request_assignment() -> void:
	var sender : int = multiplayer.get_remote_sender_id()
	if not spawner.lobby.is_master or not spawner.lobby.has_member_with_id(sender):
		return
	_ensure_assignment()
	_receive_assignment.rpc_id(sender, assignment["roles"], role_assigner.teams_visible_to(sender, assignment))


@rpc("authority", "call_remote", "reliable")
func _receive_assignment(roles : Dictionary, known_teams : Dictionary) -> void:
	if not _setup_complete:
		_spawn_players(roles, known_teams)
		_confirm_spawned.rpc_id(1)


##Client -> lobby: this client has spawned the players. The lobby spawns its own copies only once every member has, because the lobby's
##players start sending state right away, and a client that hasn't spawned them yet would log "Node not found" for each message.
@rpc("any_peer", "call_remote", "reliable")
func _confirm_spawned() -> void:
	if spawner.lobby.is_master:
		_spawned_members[multiplayer.get_remote_sender_id()] = true
		_spawn_on_lobby_when_ready()


func _spawn_on_lobby_when_ready() -> void:
	if _setup_complete:
		return
	for member in spawner.lobby.members:
		if not _spawned_members.has(member.id):
			return
	_spawn_players(assignment["roles"], assignment["teams"]) #the lobby knows every team


func _spawn_players(roles : Dictionary, known_teams : Dictionary) -> void:
	_roles = roles
	_known_teams = known_teams
	spawner.spawn_all()
	var summary : Array[String] = []
	for id : int in roles:
		var role : Role = role_assigner.role_at(roles[id])
		summary.append("%d=%s/%s" % [id, role.role_name if role else "none", Team.name_of(known_teams.get(id, Team.UNKNOWN))])
	Main.output("Roles (as this peer knows them): " + ", ".join(summary))
	_setup_complete = true
	setup_complete.emit()


func _add_debug_rings() -> void:
	var rings : DebugPlayerRings = DebugPlayerRings.new()
	rings.name = "DebugPlayerRings"
	rings.show_roles = debug_show_role_rings
	rings.show_teams = debug_show_team_rings
	rings.players = func() -> Array: return spawner.players.values()
	add_child(rings)


func _on_player_spawned(player : Node, member : LobbyMember, index : int) -> void:
	var role : Role = role_assigner.role_at(_roles.get(member.id, -1))
	player_setup.setup_player(player, member, index, spawner.lobby.members.size(), role, _known_teams.get(member.id, Team.UNKNOWN))
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
