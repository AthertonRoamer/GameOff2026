class_name DebugPlayerCommands
extends RefCounted

## Debug commands about players: kill, revive, life, health. They run on the lobby, which owns every player's health, and the health sync tells everyone else.
## A player killed here still counts as in play, so the match does not end over a test (see Player.debug_kill).

const ANGLES : Array[float] = [0.0, 45.0, 90.0, 135.0, 180.0, -135.0, -90.0, -45.0] #kills with no angle given come from the next direction each time

var _commands : DebugCommands
var _next_angle : int = 0


func _init(commands : DebugCommands) -> void:
	_commands = commands
	var angle := DebugCommand.argument("angle", "float", true)
	var player := DebugCommand.argument("player", "player", true)
	commands.register(DebugCommand.new("kill", "kills a player (default me), as if shot from an angle round them: 0 front, 90 right, 180 behind. No angle: the next direction each time", [angle, player], _kill))
	commands.register(DebugCommand.new("revive", "brings a dead player (default me) back with full health", [player], _revive))
	commands.register(DebugCommand.new("life", "kills a player (default me), or brings them back if they are dead", [player], _life))
	commands.register(DebugCommand.new("health", "sets a player's health (default me); 0 or less kills", [DebugCommand.argument("amount", "float"), player], _health))


func _targets(argument : Variant, sender : int) -> Array[Player]:
	if argument != null:
		var chosen : Array[Player] = []
		chosen.assign(argument)
		return chosen
	return _commands.players_named("me", sender)


func _kill(arguments : Array, sender : int) -> String:
	var angle : float = arguments[0] if arguments[0] != null else ANGLES[_next_angle % ANGLES.size()]
	var names : PackedStringArray = []
	for player : Player in _targets(arguments[1], sender):
		if player.is_alive():
			player.debug_kill(angle)
			names.append(player.player_name)
	if names.is_empty():
		return "Nobody to kill (they are all dead already)"
	if arguments[0] == null:
		_next_angle += 1
	return "Killed %s, shot from %.0f degrees" % [", ".join(names), angle]


func _revive(arguments : Array, sender : int) -> String:
	var names : PackedStringArray = []
	for player : Player in _targets(arguments[0], sender):
		if not player.is_alive():
			player.debug_revive()
			names.append(player.player_name)
	return "Revived %s" % ", ".join(names) if not names.is_empty() else "Nobody to revive (they are all alive)"


func _life(arguments : Array, sender : int) -> String:
	var targets : Array[Player] = _targets(arguments[0], sender)
	if not targets.is_empty() and targets[0].is_alive():
		return _kill([null, targets], sender)
	return _revive([targets], sender)


func _health(arguments : Array, sender : int) -> String:
	var names : PackedStringArray = []
	for player : Player in _targets(arguments[1], sender):
		if arguments[0] <= 0.0:
			if player.is_alive():
				player.debug_kill(0.0)
		else:
			player.health = arguments[0]
		names.append(player.player_name)
	return "Health of %s: %.0f" % [", ".join(names), maxf(arguments[0], 0.0)]
