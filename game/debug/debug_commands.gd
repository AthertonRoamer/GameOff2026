class_name DebugCommands
extends Node

## The debug commands of a game: typed lines like "kill 90 bob" or "health 30". Child of Game (the same node path on every peer, so the RPCs find each other).
##
## Where a line comes from does not matter: the console (DebugConsole), a hotkey in key_bindings, later the chat. run() takes it on the peer that typed it.
## A command that changes what everyone plays (health, roles, the clock) runs on the lobby, which owns that state: a client sends the line there, the lobby checks
## the sender is in the lobby and runs it, and the answer comes back as text. A command that only changes what this peer sees (rings, darkness) runs right here.
## Any player of a debug session may run commands. Commands are made in game/debug/commands/ (one set per area) and listed by "help".
##
## Removable: `enabled` is a debug setting, so DebugRemover turns it off for a release (the node then does nothing, and DebugConsole removes itself).

const DEBUG_SETTINGS : Array[StringName] = [&"enabled"] #turned off by DebugRemover

signal output(text : String) ## what a command printed (or why it did not run), on this peer

@export_group("Debug")
@export var enabled : bool = true
@export_group("")
## Keys that run a command, a hotkey for each: keycode -> line.
@export var key_bindings : Dictionary = {KEY_K: "life", KEY_R: "rings", KEY_N: "darkness", KEY_P: "pixelart"}

var show_toasts : bool = true #say the answer in a toast in the corner (the console turns this off while it is open: it prints the answer itself)

var game : Game
var _commands : Dictionary = {} #name -> DebugCommand
var _command_sets : Array[RefCounted] = []


func _ready() -> void:
	game = get_parent() as Game
	set_process_unhandled_input(enabled)
	if not enabled:
		return
	_command_sets = [DebugPlayerCommands.new(self), DebugMatchCommands.new(self), DebugViewCommands.new(self)] #(kept: the commands call into them)
	register(DebugCommand.new("help", "lists the commands, or says how to use one", [DebugCommand.argument("command", "string", true)], _help, true))


func register(command : DebugCommand) -> void:
	_commands[command.name] = command


func command_names() -> PackedStringArray:
	var names : PackedStringArray = PackedStringArray(_commands.keys())
	names.sort()
	return names


func _unhandled_input(event : InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and key_bindings.has((event as InputEventKey).keycode):
		run(key_bindings[(event as InputEventKey).keycode])


## Runs a typed line, on this peer or the lobby, and says the answer here.
func run(line : String) -> void:
	if not enabled:
		return
	var words : PackedStringArray = _split(line)
	if words.is_empty():
		return
	var command : DebugCommand = _commands.get(words[0].trim_prefix("/"))
	if command == null:
		_say("Unknown command '%s' (help lists them)" % words[0])
	elif command.runs_locally or game.spawner.lobby.is_master:
		_say(execute(line, multiplayer.get_unique_id()))
	else:
		_request.rpc_id(1, line)


## Parses and runs a line as `sender`, and returns what to say. Does nothing over the network.
func execute(line : String, sender : int) -> String:
	var words : PackedStringArray = _split(line)
	var command : DebugCommand = _commands.get(words[0].trim_prefix("/")) if not words.is_empty() else null
	if command == null:
		return "Unknown command '%s' (help lists them)" % (words[0] if not words.is_empty() else "")
	var values : Array = []
	for i in command.arguments.size():
		var spec : Dictionary = command.arguments[i]
		if i + 1 >= words.size():
			if not spec["optional"]:
				return "Missing <%s>. Usage: %s" % [spec["name"], command.usage()]
			values.append(null)
			continue
		var value : Variant = _convert(words[i + 1], spec["type"], sender)
		if value == null:
			return "'%s' is not %s <%s>. Usage: %s" % [words[i + 1], "a player for" if spec["type"] == "player" else "a valid", spec["name"], command.usage()]
		values.append(value)
	if words.size() - 1 > command.arguments.size():
		return "Too many arguments. Usage: %s" % command.usage()
	return command.handler.call(values, sender)


## The players a word means, for the commands that take a "player": me, all, a name or a peer id. Empty when there is none.
func players_named(word : String, sender : int) -> Array[Player]:
	var found : Array[Player] = []
	var players : Dictionary = game.spawner.players
	if word == "me":
		if players.has(sender):
			found.append(players[sender])
	elif word == "all":
		for player in players.values():
			if is_instance_valid(player):
				found.append(player)
	elif word.is_valid_int() and players.has(word.to_int()):
		found.append(players[word.to_int()])
	else:
		for player in players.values():
			if is_instance_valid(player) and player.player_name.to_lower() == word.to_lower():
				found.append(player)
	return found


## Client -> lobby: a command that changes what everyone plays. Only a member of the lobby may send one.
@rpc("any_peer", "call_remote", "reliable")
func _request(line : String) -> void:
	var sender : int = multiplayer.get_remote_sender_id()
	if not enabled or not game.spawner.lobby.is_master or not game.spawner.lobby.has_member_with_id(sender):
		return
	_answer.rpc_id(sender, execute(line, sender))


@rpc("authority", "call_remote", "reliable")
func _answer(text : String) -> void:
	_say(text)


func _say(text : String) -> void:
	if text == "":
		return
	output.emit(text)
	if show_toasts:
		DebugToast.say(self, text)


func _convert(word : String, type : String, sender : int) -> Variant:
	match type:
		"float":
			return word.to_float() if word.is_valid_float() else null
		"int":
			return word.to_int() if word.is_valid_int() else null
		"player":
			var players : Array[Player] = players_named(word, sender)
			return players if not players.is_empty() else null
	return word


## The words of a line, a quoted phrase being one word: kill 90 "Bob Smith".
func _split(line : String) -> PackedStringArray:
	var words : PackedStringArray = []
	var current := ""
	var quoted := false
	for character in line.strip_edges():
		if character == '"':
			quoted = not quoted
		elif character == " " and not quoted:
			if current != "":
				words.append(current)
				current = ""
		else:
			current += character
	if current != "":
		words.append(current)
	return words


func _help(arguments : Array, _sender : int) -> String:
	if arguments[0] != null:
		var command : DebugCommand = _commands.get(String(arguments[0]).trim_prefix("/"))
		return "%s: %s" % [command.usage(), command.summary] if command != null else "No command '%s'" % arguments[0]
	var lines : PackedStringArray = []
	for command_name in command_names():
		var command : DebugCommand = _commands[command_name]
		lines.append("%s: %s" % [command.usage(), command.summary])
	return "\n".join(lines)
