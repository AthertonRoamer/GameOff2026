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

const DEBUG_SETTINGS : Array[StringName] = [&"debug_respawn_dead_players", &"debug_show_role_rings", &"debug_show_team_rings", &"debug_skip_phases"] #turned off by DebugRemover

signal setup_complete #the players have been spawned with their roles and teams
signal play_started #every peer: the phases are over and the players can move (the shift clock starts now)

@export_group("Roles and teams")
@export var guard_roles : Array[Role] = [] #every guard gets a different one while they last
@export var intruder_roles : Array[Role] = []
@export var intruder_count : int = 1
@export var attacking_guard_count : int = 1 #guards who are secretly attackers. At least one guard always defends
@export var min_players_for_attacking_guards : int = 4 #with fewer players no guard secretly attacks (three players: two loyal guards and one intruder)
@export var intruders_know_attackers : bool = true #intruders are told which guards are secretly on their side
@export var attacking_guards_know_each_other : bool = false #secretly attacking guards are told about each other

@export_group("Debug")
@export var debug_respawn_dead_players : bool = false #hides dead players and revives them (full health) after 3 seconds
@export var debug_show_role_rings : bool = false #a ring in each player's role colour
@export var debug_show_team_rings : bool = false #green rings around defenders, red around attackers. Every peer is told every team for this
@export var debug_skip_phases : bool = false #play begins on the start tick, without the phases (role reveal...) before it

@onready var level : NightShiftLevel = $Level
@onready var spawner : RollbackPlayerSpawner = $Spawner
@onready var player_setup : PlayerSetup = $PlayerSetup
@onready var player_hud : CanvasLayer = $PlayerHud
@onready var lag_compensator : LagCompensator = $LagCompensator
@onready var game_clock : GameClock = $GameClock
@onready var match_director : MatchDirector = $MatchDirector
@onready var end_screen : EndScreen = $EndScreen
@onready var pickups : PickupControl = $PickupControl
@onready var artifact_placer : ArtifactPlacer = $ArtifactPlacer
@onready var ammo_placer : AmmoPlacer = $AmmoPlacer
@onready var abilities : AbilityControl = $AbilityControl #what the roles can do: revive, vents
@onready var target_chooser : TargetArtifactChooser = $TargetArtifactChooser
@onready var exit_chooser : DesignatedExitChooser = $DesignatedExitChooser
@onready var artifact_escape : ArtifactEscape = $ArtifactEscape
@onready var phases : MatchPhases = $MatchPhases
@onready var chat_relay : ChatRelay = $ChatRelay #the text chat: the lobby passes each message to the players on its channel only
@onready var spectator : Spectator = $Spectator #once this peer's player is dead, its camera follows a living one

var started : bool = false #play has begun: the phases are over. (The test harness waits for this)

var settings : MatchSettings = MatchSettings.new() #what the host chose for this match: the map, debug, the mode (see MatchSetupPanel)
var deathmatch : DeathmatchMode #only in a deathmatch: the kills, the five minutes, the result
var role_assigner : RoleAssigner = RoleAssigner.new()
var assignment : Dictionary = {} #lobby: every member's role and team. The win check will use it
var _roles : Dictionary = {} #member id -> role index, every member
var _known_teams : Dictionary = {} #member id -> Team, only the teams this peer may know
var _artifact_picks : PackedInt32Array = PackedInt32Array() #lobby: which artifact goes on each location, see ArtifactPlacer
var _target_artifact : int = -1 #lobby: the artifact the attackers are after, see TargetArtifactChooser
var _designated_exit : String = "" #lobby: the exit the attackers must leave by, see DesignatedExitChooser
var _setup_complete : bool = false
var _spawned_members : Dictionary = {} #lobby: members whose game has spawned the players


##The match setup is applied here, before the children are ready: the map is swapped and debug switched off (DebugRemover strips it when its own _ready runs) before anything reads them.
func _enter_tree() -> void:
	if get_parent() is GameManager:
		settings = MatchSettings.from_dict((get_parent() as GameManager).lobby.match_settings)
	_choose_map(settings.map_option())
	if not settings.debug:
		$DebugRemover.enabled = true


## Puts the chosen map in the level where the first one stands (the nodes that point at the map are pointed at the new one) and says where the players start.
func _choose_map(option : MapOption) -> void:
	var level_node : NightShiftLevel = $Level
	var current : FacilityMap = level_node.get_node("FacilityMap")
	if option.scene_path != "" and option.scene_path != current.scene_file_path:
		var chosen : FacilityMap = (load(option.scene_path) as PackedScene).instantiate()
		chosen.doors_start = current.doors_start
		current.name = &"ReplacedMap"
		chosen.name = &"FacilityMap"
		level_node.add_child(chosen)
		level_node.move_child(chosen, current.get_index())
		for node_name : String in ["FacilityControl", "UtilityConsoles", "Sound", "PowerGrid", "RoomLights"]:
			level_node.get_node(node_name).facility = chosen
		current.free()
	level_node.spawn_room = option.spawn_room


func _ready() -> void:
	spawner.spawn_parent = level.actors
	spawner.player_spawned.connect(_on_player_spawned)
	level.player_lookup = func(peer_id : int) -> Player: return spawner.players.get(peer_id)
	pickups.spawn_parent = level.actors
	pickups.player_lookup = level.player_lookup
	abilities.player_lookup = level.player_lookup
	abilities.build(level.facility)
	artifact_escape.facility = level.facility
	artifact_escape.players = func() -> Array: return spawner.players.values()
	level.projectiles.lag_compensator = lag_compensator
	level.projectiles.can_hit = func(target : Node) -> bool: return target.is_alive()
	level.projectiles.projectile_hit.connect(_on_projectile_hit)
	player_setup.lag_compensator = lag_compensator
	player_setup.projectile_manager = level.projectiles
	player_setup.hitscan_manager = level.hitscan
	level.hitscan.lag_compensator = lag_compensator
	level.hitscan.can_hit = func(target : Node) -> bool: return target.is_alive()
	level.hitscan.targets = func() -> Array: return spawner.players.values()
	level.hitscan.player_of = func(peer_id : int) -> Player: return spawner.players.get(peer_id)
	level.hitscan.sight = $PlayerSight.visibility #shots and bullets are only seen as well as the local player can see where they are
	level.projectiles.sight = $PlayerSight.visibility
	level.blood.sight = $PlayerSight.visibility #and so is blood on the floor
	pickups.sight = $PlayerSight.visibility #and items on the floor: ammo and relics
	$PlayerSight.ambient = level.darkness.color
	$PlayerSight.players = func() -> Array: return spawner.players.values()
	$PlayerSight.local_player = func() -> Player: return spawner.local_player
	$PlayerSight.room_lights = level.lights #rooms' ceiling lights are drawn where the local player has a line of sight to them
	level.hitscan.shot_hit.connect(_on_projectile_hit) #(the same hit as a bullet makes: damage and the way it was going)
	level.hitscan.door_shot.connect(func(door : FacilityDoor) -> void: #(lobby) a shot opens a shut door; it can be shut again. A locked one stays
		if door.state == FacilityDoor.State.CLOSED and not level.control.is_pending(door):
			level.control.force_open(door))
	player_hud.bind_hitscan(level.hitscan)
	player_hud.bind_map(level.facility)
	player_hud.bind_exit(exit_chooser) #the target exit on the full map, for intruders only
	player_hud.bind_relics(artifact_placer) #the treasure rooms the relics start in, on the full map
	player_hud.bind_power(level.power)
	chat_relay.game = self
	spectator.players = func() -> Array: return spawner.players.values()
	spectator.local_player = func() -> Player: return spawner.local_player
	spectator.name_of = func(player : Player) -> String: return chat_relay._name_of(player.member_id()) if spawner.lobby != null else String(player.name)
	spectator.allowed = func() -> bool: return started and not settings.is_deathmatch() and not end_screen.visible
	level.sound.listener = func() -> Variant: #sounds are heard from where this peer's own player is, or from the one being spectated
		if spectator.is_spectating():
			return spectator.target.global_position
		return spawner.local_player.global_position if is_instance_valid(spawner.local_player) else null
	level.sound.heard.connect(player_hud.sound_cue.ping)
	level.blood.splat_made.connect(func(kind : int, at : Vector2) -> void: level.sound.play(level.sound.blood_drip if kind == BloodSplat.Kind.BLEED else level.sound.blood_splat, at))
	level.hitscan.wall_hit.connect(func(at : Vector2, own_shot : bool) -> void:
		await get_tree().create_timer(IMPACT_SOUND_DELAY).timeout #(after the bang, so a loud shot does not hide it)
		level.sound.play(level.sound.bullet_ricochet if _player_near(at) else level.sound.bullet_wall, at, false, not own_shot)) #(a shot that strikes the wall by a player whines off it; the impact of your own shot is heard, but gives no cue)
	player_setup.spawn_point = level.spawn_position()
	if settings.is_deathmatch():
		_setup_deathmatch()
	else:
		player_hud.bind_clock(game_clock) #(a deathmatch counts down its own five minutes instead)
	player_hud.visible = false #shown when play begins, after the phases
	phases.game = self
	phases.finished.connect(_begin_play)
	_configure_role_assigner()
	if debug_show_role_rings or debug_show_team_rings:
		_add_debug_rings()
	if get_parent() is GameManager:
		var lobby : Lobby = get_parent().lobby
		spawner.setup(lobby)
		if lobby.is_master:
			_ensure_assignment()
			lobby.member_left.connect(func(_m : LobbyMember) -> void: _spawn_on_lobby_when_ready())
			lobby.member_left.connect(func(_m : LobbyMember) -> void: match_director.check_elimination())
			lobby.member_left.connect(chat_relay._on_member_left)
			artifact_escape.watch() #the attackers win when the target artifact is carried into an exit zone
			_spawn_on_lobby_when_ready() #no members: spawns now
		else:
			_request_assignment.rpc_id(1)


##Every peer, on the start tick the lobby picked. The phases (MatchPhases' children: the role reveal...) run first, and play begins when they end.
func start() -> void:
	level.control.broadcast_snapshot() #lobby only: every peer starts from the lobby's doors
	level.power.broadcast_snapshot() #and from its generators
	var start_tick : int = (get_parent() as RollbackGameManager).start_tick
	if debug_skip_phases or settings.is_deathmatch(): #(a deathmatch has no roles to reveal and nowhere to choose: everyone is dropped in)
		Main.output("Phases skipped (%s)" % ("deathmatch" if settings.is_deathmatch() else "debug_skip_phases"))
		phases.hide_cover()
		_begin_play(start_tick)
	else:
		phases.run(start_tick)


##Every peer, on the tick the last phase ended (the same tick everywhere): the players can move, the HUD shows, the shift clock starts counting
##from now, and only now can the match be won or lost.
func _begin_play(tick : int) -> void:
	started = true
	set_players_active(true)
	player_hud.visible = true
	if settings.is_deathmatch():
		deathmatch.begin(tick, spawner.lobby != null and spawner.lobby.is_master) #(no shift clock, no teams, no artifacts: kills and the five minutes)
		if spawner.lobby != null and spawner.lobby.is_master:
			ammo_placer.start_trickle() #(everyone dies and returns with what they had: the lobby brings new boxes over time)
		play_started.emit()
		return
	game_clock.start(tick)
	if spawner.lobby != null and spawner.lobby.is_master:
		match_director.begin(assignment["teams"], _build_roster(), _is_in_play)
		match_director.check_elimination() #in case every attacker left during the phases
	play_started.emit()


func end() -> void:
	game_clock.stop()
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
	role_assigner.min_players_for_attacking_guards = min_players_for_attacking_guards
	role_assigner.intruders_know_attackers = intruders_know_attackers
	role_assigner.attacking_guards_know_each_other = attacking_guards_know_each_other
	role_assigner.everyone_knows_all_teams = debug_show_team_rings
	if settings.is_deathmatch():
		role_assigner.intruder_count = 0 #everyone is a guard, and nobody is secretly on a side
		role_assigner.attacking_guard_count = 0


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
	if not settings.is_deathmatch(): #(a deathmatch has no artifacts to steal, and no exit to take them out by)
		_artifact_picks = artifact_placer.roll(rng)
		_target_artifact = target_chooser.choose(_artifact_picks, rng)
		_designated_exit = exit_chooser.choose(level.facility.exits.keys(), rng)


##Client -> lobby. Asked instead of pushed: the lobby's game always exists by the time a client's request arrives, whereas a pushed
##answer could reach a client before its own game had loaded.
@rpc("any_peer", "call_remote", "reliable")
func _request_assignment() -> void:
	var sender : int = multiplayer.get_remote_sender_id()
	if not spawner.lobby.is_master or not spawner.lobby.has_member_with_id(sender):
		return
	_ensure_assignment()
	var is_attacker : bool = assignment["teams"].get(sender) == Team.ATTACKERS #defenders are never sent the target or the exit
	var target_for_sender : int = _target_artifact if is_attacker else -1
	_receive_assignment.rpc_id(sender, assignment["roles"], role_assigner.teams_visible_to(sender, assignment), _artifact_picks, target_for_sender, _designated_exit if is_attacker else "")


@rpc("authority", "call_remote", "reliable")
func _receive_assignment(roles : Dictionary, known_teams : Dictionary, artifact_picks : PackedInt32Array, target_artifact : int, designated_exit : String) -> void:
	if not _setup_complete:
		artifact_placer.place(artifact_picks)
		ammo_placer.place()
		target_chooser.set_target(target_artifact)
		exit_chooser.set_designated(designated_exit)
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
	artifact_placer.place(_artifact_picks)
	ammo_placer.place()
	target_chooser.set_target(_target_artifact)
	exit_chooser.set_designated(_designated_exit)
	_spawn_players(assignment["roles"], assignment["teams"]) #the lobby knows every team


func _spawn_players(roles : Dictionary, known_teams : Dictionary) -> void:
	_roles = roles
	_known_teams = known_teams
	for index : int in roles.values(): #the skins of the roles in this game are loaded now, while it loads, not when the first player is drawn (each is shared by every player with that role)
		var role : Role = role_assigner.role_at(index)
		if role != null:
			SkinFrames.load_role("res://game/player/skin", role.skin)
	spawner.spawn_all()
	_refresh_chat()
	var summary : Array[String] = []
	for id : int in roles:
		var role : Role = role_assigner.role_at(roles[id])
		summary.append("%d=%s/%s" % [id, role.role_name if role else "none", Team.name_of(known_teams.get(id, Team.UNKNOWN))])
	Main.output("Roles (as this peer knows them): " + ", ".join(summary))
	_setup_complete = true
	setup_complete.emit()


##Lobby only, for the debug commands: whether roles and teams can be changed now (the players exist).
func can_change_roles() -> bool:
	return spawner.lobby.is_master and _setup_complete and not assignment.is_empty()


const ROLE_CHANGE_DELAY_TICKS : int = 8 ## how far ahead a role change's ammunition reset is scheduled: it should cover the lobby -> client delay

##Lobby only, debug: gives a member another role. Roles are public, so every peer is told. An intruder role makes the member an attacker, and leaving one
## makes them a defender. A role changes who may know whose team (an intruder's team is public), so the teams are sent out again.
func debug_set_role(member_id : int, role_index : int) -> void:
	var was_intruder : bool = is_intruder(member_id)
	assignment["roles"][member_id] = role_index
	_apply_role.rpc(member_id, role_index, NetworkTime.tick + ROLE_CHANGE_DELAY_TICKS)
	if is_intruder(member_id):
		assignment["teams"][member_id] = Team.ATTACKERS
	elif was_intruder:
		assignment["teams"][member_id] = Team.DEFENDERS
	_send_teams(member_id)


##Lobby only, debug: puts a member on a team. Teams are secret, so each peer is sent only what RoleAssigner.teams_visible_to lets it know.
func debug_set_team(member_id : int, team : int) -> void:
	assignment["teams"][member_id] = team
	_send_teams(member_id)


func is_intruder(member_id : int) -> bool:
	var role : Role = role_assigner.role_at(assignment["roles"].get(member_id, -1))
	return role != null and role.is_intruder()


func _send_teams(changed_member_id : int) -> void:
	var role : Role = role_assigner.role_at(assignment["roles"].get(changed_member_id, -1))
	match_director.update_roster(changed_member_id, role.role_name if role else "No role", assignment["teams"][changed_member_id])
	_apply_teams(assignment["teams"]) #the lobby knows every team
	for member in spawner.lobby.members:
		if member.id != multiplayer.get_unique_id():
			var is_attacker : bool = assignment["teams"].get(member.id) == Team.ATTACKERS
			_receive_teams.rpc_id(member.id, role_assigner.teams_visible_to(member.id, assignment), _target_artifact if is_attacker else -1, _designated_exit if is_attacker else "")


@rpc("authority", "call_local", "reliable")
func _apply_role(member_id : int, role_index : int, reset_tick : int) -> void:
	_roles[member_id] = role_index
	var player : Player = spawner.players.get(member_id)
	if is_instance_valid(player):
		player.change_role(role_assigner.role_at(role_index), reset_tick) #(the ammunition starts again on one tick everywhere, so a rollback keeps it)
	_refresh_chat()


@rpc("authority", "call_remote", "reliable")
func _receive_teams(known_teams : Dictionary, target_artifact : int, designated_exit : String) -> void:
	target_chooser.set_target(target_artifact)
	exit_chooser.set_designated(designated_exit)
	_apply_teams(known_teams)


func _apply_teams(known_teams : Dictionary) -> void:
	_known_teams = known_teams
	for id : int in spawner.players:
		var player : Player = spawner.players[id]
		if is_instance_valid(player):
			player.team = known_teams.get(id, Team.UNKNOWN)
	var local : Player = spawner.local_player
	if is_instance_valid(local):
		player_hud.show_target(target_chooser.target if local.team == Team.ATTACKERS else null)
	_refresh_chat()


##The local player's chat window, on the channels this peer's own role and team put it on (a peer always knows its own team). None in a deathmatch,
##and none on the lobby, which has no player of its own.
func _refresh_chat() -> void:
	var local : Player = spawner.local_player
	if not is_instance_valid(local):
		return
	var channels : Array[int] = []
	if not settings.is_deathmatch():
		channels = ChatRules.channels_for(multiplayer.get_unique_id(), {"roles": _roles, "teams": _known_teams}, role_assigner)
	player_hud.bind_chat(chat_relay, local, channels)


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
		if player.team == Team.ATTACKERS:
			player_hud.show_target(target_chooser.target)
	var is_local : bool = player == spawner.local_player
	(player as Player).get_node("Revivable").control = abilities
	player.footsteps.stepped.connect(func(def : SoundDef, at : Vector2) -> void: level.sound.play(def, at, is_local)) #every peer sees every player's feet, so every peer hears them
	player.shot_fired.connect(_on_shot_fired.bind(player, is_local))
	player.reload_started.connect(func(gun : Gun) -> void: level.sound.play(gun.reload_sound, player.global_position, is_local))
	player.damaged.connect(func(_direction : Vector2) -> void: #the health sync tells every peer, so every peer hears the hit (a killing shot has the kill sound instead)
		if player.health > 0.0:
			level.sound.play(level.sound.bullet_flesh, player.global_position))
	player.died.connect(func() -> void: level.sound.play(level.sound.kill, player.global_position))
	level.blood.players = func() -> Array: return spawner.players.values()
	player.died.connect(level.blood.on_player_died.bind(player), CONNECT_DEFERRED) #the puddle under the body, on every peer (after the skin has laid the body)
	if spawner.lobby.is_master:
		player.damaged.connect(level.blood.on_player_damaged.bind(player)) #a splash where a bullet came through, decided by the lobby
		player.died.connect(match_director.check_elimination)
	if debug_respawn_dead_players or settings.is_deathmatch():
		player.died.connect(_on_player_died.bind(player))
		player.health_changed.connect(_on_player_health_changed.bind(player))


const IMPACT_SOUND_DELAY : float = 0.14 ## seconds after the bang that a bullet's strike on the wall is heard
const RICOCHET_NEAR_METRES : float = 5.0 ## a wall impact this close to a living player is a ricochet

##Whether a living player is close to a point (as this peer sees the players).
func _player_near(point : Vector2) -> bool:
	var near_px : float = RICOCHET_NEAR_METRES * Acoustics.PX_PER_METRE
	for player : Player in spawner.players.values():
		if is_instance_valid(player) and player.is_alive() and player.global_position.distance_to(point) < near_px:
			return true
	return false


##A shot, on every peer (the shooter's own, and the lobby's word for everyone else's): the gun's bang, heard through the map from the shooter.
func _on_shot_fired(player : Player, is_local : bool) -> void:
	var gun : Gun = player.inventory.active_item as Gun
	if gun != null:
		level.sound.play(gun.shot_sound, player.global_position, is_local)


const DEATHMATCH_RESPAWN_SECONDS : float = 4.0 #how long a fallen body lies there (its fall plays and it rests) before the player comes back elsewhere


func _on_player_died(player : Node) -> void:
	var in_deathmatch : bool = settings.is_deathmatch()
	if not in_deathmatch:
		player.visible = false #(the debug respawn hides them at once; in a deathmatch the body stays and the fall is seen)
	if player.is_multiplayer_authority(): #only the authority decides when health comes back; HealthSynchronizer broadcasts it
		await get_tree().create_timer(DEATHMATCH_RESPAWN_SECONDS if in_deathmatch else 3.0).timeout
		if is_instance_valid(player) and not (in_deathmatch and deathmatch.is_over): #(nobody comes back once the deathmatch is over)
			if in_deathmatch:
				_respawn_at.rpc(int(String(player.name)), _respawn_point()) #a deathmatch brings them back somewhere else
			player.health = player.starting_health


##Somewhere on the floor that is far from every living player (the best of a few tries).
func _respawn_point() -> Vector2:
	var best : Vector2 = level.spawn_position()
	var best_gap : float = -1.0
	for attempt in 6:
		var point : Vector2 = level.facility.random_floor_point()
		var gap : float = INF
		for other : Player in spawner.players.values():
			if is_instance_valid(other) and other.is_alive():
				gap = minf(gap, other.global_position.distance_to(point))
		if gap > best_gap:
			best_gap = gap
			best = point
	return best


@rpc("authority", "call_local", "reliable")
func _respawn_at(member_id : int, point : Vector2) -> void:
	var player : Player = spawner.players.get(member_id)
	if is_instance_valid(player):
		player.visible = player.is_alive() #the body is gone from where it lay (it shows again as the player comes back, see _on_player_health_changed; if that has already come, they are simply shown)
		player.teleport(point)


func _on_player_health_changed(h : float, player : Node) -> void:
	if h > 0:
		player.visible = true


func _on_projectile_hit(projectile : Dictionary, target : Node) -> void:
	var was_alive : bool = target is Player and target.is_alive()
	target.take_damage(projectile["damage"], projectile["direction"]) #the direction decides how a player killed by it falls
	if deathmatch != null and was_alive and not target.is_alive():
		deathmatch.record_kill(int(projectile.get("owner_id", -1)), int(String(target.name))) #(the lobby counts it: only it hears of hits)


##Lobby only. Who played what, for the end screen. Built when the match starts so players who leave part way through are still listed.
func _build_roster() -> Array:
	var roster : Array = []
	for member in spawner.lobby.members:
		var role : Role = role_assigner.role_at(assignment["roles"].get(member.id, -1))
		roster.append({"id": member.id, "name": member.name, "role": role.role_name if role else "No role", "team": assignment["teams"].get(member.id, Team.UNKNOWN)})
	return roster


##A player who left is out. So is a dead one, unless debug_respawn_dead_players is going to bring them back.
func _is_in_play(member_id : int) -> bool:
	var player : Variant = spawner.players.get(member_id)
	return is_instance_valid(player) and (debug_respawn_dead_players or player.is_alive() or player.debug_killed) #(a player killed with the debug K key still counts)


## Deathmatch only. The node that counts kills and time, and what every peer does with its result.
func _setup_deathmatch() -> void:
	deathmatch = DeathmatchMode.new()
	deathmatch.name = "DeathmatchMode" #(the same on every peer: its messages find each other by this name)
	deathmatch.name_of = func(id : int) -> String: return _member_name(id)
	deathmatch.member_ids = func() -> Array: return spawner.lobby.members.map(func(m : LobbyMember) -> int: return m.id) if spawner.lobby != null else []
	add_child(deathmatch)
	deathmatch.finished.connect(_on_deathmatch_finished)
	deathmatch.return_to_lobby.connect(_on_match_director_return_to_lobby)
	player_hud.bind_deathmatch(deathmatch)


func _member_name(id : int) -> String:
	if spawner.lobby != null:
		for member : LobbyMember in spawner.lobby.members:
			if member.id == id:
				return member.name
	return str(id)


func _on_deathmatch_finished(table : Array) -> void:
	game_clock.stop()
	if is_instance_valid(spawner.local_player):
		spawner.local_player.interactor.close_screen()
	set_players_active(false)
	player_hud.visible = false
	var local_id : int = multiplayer.get_unique_id()
	var best : int = table[0]["kills"] if not table.is_empty() else 0
	var winners : Array = table.filter(func(entry : Dictionary) -> bool: return entry["kills"] == best and best > 0)
	var won : bool = winners.any(func(entry : Dictionary) -> bool: return entry["id"] == local_id)
	var title : String = "Victory" if won else "Defeat"
	var reason : String = "Nobody scored." if winners.is_empty() else ("%s wins with %d kills." % [winners[0]["name"], best] if winners.size() == 1 else "%s tie with %d kills." % [", ".join(winners.map(func(entry : Dictionary) -> String: return entry["name"])), best])
	var lines : Array = []
	for i in table.size():
		var entry : Dictionary = table[i]
		lines.append({"text": "%d. %s  -  %d kills" % [i + 1, entry["name"], entry["kills"]], "color": Palette.BACKUP if winners.any(func(w : Dictionary) -> bool: return w["id"] == entry["id"]) else Palette.PANEL_LINE})
	end_screen.show_custom(title, EndScreen.WIN_COLOR if won else EndScreen.LOSE_COLOR, reason, lines, deathmatch.results_seconds)


func _on_match_ended(reason : int, roster : Array) -> void:
	game_clock.stop()
	if is_instance_valid(spawner.local_player):
		spawner.local_player.interactor.close_screen() #first: closing a screen gives the player control back
	set_players_active(false)
	player_hud.visible = false
	end_screen.show_result(reason, roster, multiplayer.get_unique_id(), match_director.results_seconds)


func _on_match_director_return_to_lobby() -> void:
	if spawner.lobby.game_manager.in_game: #the host may have quit from the escape menu during the results
		spawner.lobby.trigger_end_game()


func _on_network_unloader_cease_rpcs_request_received() -> void:
	set_players_active(false)
	level.projectiles.quiesce()
	level.control.quiesce()
	level.power.quiesce()
	level.consoles.quiesce()
	level.blood.quiesce()
	level.hitscan.quiesce()
	pickups.quiesce()
	abilities.quiesce()
	ammo_placer.quiesce()
	artifact_escape.quiesce()
	phases.quiesce()
	spawner.quiesce()
	($NetworkUnloader as NetworkUnloader).register_as_ceased()
