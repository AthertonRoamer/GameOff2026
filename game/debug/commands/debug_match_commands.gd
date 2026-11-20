class_name DebugMatchCommands
extends RefCounted

## Debug commands about who is who: role and team. They run on the lobby, which owns the assignment, and Game tells every peer the part it may know:
## a role is public, a team goes only to the peers RoleAssigner.teams_visible_to allows. A peer's own request never decides anything: the lobby checks it.

var _commands : DebugCommands


func _init(commands : DebugCommands) -> void:
	_commands = commands
	var player := DebugCommand.argument("player", "player", true)
	commands.register(DebugCommand.new("role", "gives a player (default me) a role by name, say 'role list' for the names. An intruder role makes them an attacker, and refills their health and items", [DebugCommand.argument("role", "string"), player], _role))
	commands.register(DebugCommand.new("team", "puts a player (default me) on a team: attackers or defenders", [DebugCommand.argument("team", "string"), player], _team))


func _role(arguments : Array, sender : int) -> String:
	var game : Game = _commands.game
	var names : PackedStringArray = []
	var roles : Array[Role] = game.role_assigner.all_roles()
	for role in roles:
		names.append(role.role_name)
	if String(arguments[0]).to_lower() == "list":
		return "Roles: " + ", ".join(names)
	var index : int = -1
	for i in roles.size():
		if roles[i].role_name.to_lower() == String(arguments[0]).to_lower():
			index = i
	if index < 0:
		return "No role '%s'. Roles: %s" % [arguments[0], ", ".join(names)]
	if not game.can_change_roles():
		return "Roles can only be changed in a running game"
	var changed : PackedStringArray = []
	for player : Player in _targets(arguments[1], sender):
		game.debug_set_role(_member_id(player), index)
		changed.append(player.player_name)
	return "%s now %s: %s" % [", ".join(changed), roles[index].role_name, "attackers" if roles[index].is_intruder() else "team unchanged"] if not changed.is_empty() else "Nobody to change"


func _team(arguments : Array, sender : int) -> String:
	var team : int = Team.UNKNOWN
	match String(arguments[0]).to_lower():
		"attackers", "attacker": team = Team.ATTACKERS
		"defenders", "defender": team = Team.DEFENDERS
	if team == Team.UNKNOWN:
		return "'%s' is not a team: attackers or defenders" % arguments[0]
	var game : Game = _commands.game
	if not game.can_change_roles():
		return "Teams can only be changed in a running game"
	var changed : PackedStringArray = []
	for player : Player in _targets(arguments[1], sender):
		if team == Team.DEFENDERS and game.is_intruder(_member_id(player)):
			continue #an intruder is always an attacker
		game.debug_set_team(_member_id(player), team)
		changed.append(player.player_name)
	return "%s now %s" % [", ".join(changed), Team.name_of(team)] if not changed.is_empty() else "Nobody to change (intruders are always attackers)"


func _targets(argument : Variant, sender : int) -> Array[Player]:
	if argument != null:
		var chosen : Array[Player] = []
		chosen.assign(argument)
		return chosen
	return _commands.players_named("me", sender)


func _member_id(player : Player) -> int:
	return _commands.game.spawner.players.find_key(player)
