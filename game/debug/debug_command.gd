class_name DebugCommand
extends RefCounted

## One debug command: its name, what it does, the arguments it takes and the function that does it. Command sets (game/debug/commands/) make these and register
## them with DebugCommands, which parses what the player types, finds the command, runs it where it belongs and says what it printed.
##
## An argument has a type, and DebugCommands turns the typed words into it before the handler runs:
##   "float", "int", "string"
##   "player": who the command is about: me, all, a player's name or their peer id. The handler gets an Array of Players (never empty).
## An optional argument that was left out reaches the handler as null.
## The handler is (arguments : Array, sender : int) -> String, the text to show; sender is the peer id of whoever typed the command.

var name : String
var summary : String
var arguments : Array
var handler : Callable
var runs_locally : bool #on the peer that typed it (what this peer sees) instead of on the lobby (what everyone plays)


func _init(command_name : String, command_summary : String, command_arguments : Array, command_handler : Callable, local := false) -> void:
	name = command_name
	summary = command_summary
	arguments = command_arguments
	handler = command_handler
	runs_locally = local


static func argument(argument_name : String, type : String, optional := false) -> Dictionary:
	return {"name": argument_name, "type": type, "optional": optional}


## "kill [angle] [player]": required arguments in <>, optional ones in [].
func usage() -> String:
	var parts : PackedStringArray = [name]
	for spec : Dictionary in arguments:
		parts.append(("[%s]" if spec["optional"] else "<%s>") % spec["name"])
	return " ".join(parts)
