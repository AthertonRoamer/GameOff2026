class_name DebugViewCommands
extends RefCounted

## Debug commands about what this peer sees: rings, darkness, pixelart. They run on the peer that typed them and change nothing for anyone else.

var _commands : DebugCommands


func _init(commands : DebugCommands) -> void:
	_commands = commands
	commands.register(DebugCommand.new("rings", "shows or hides the role and team rings round the players", [], _rings, true))
	commands.register(DebugCommand.new("darkness", "turns the facility's darkness on or off", [], _darkness, true))
	commands.register(DebugCommand.new("pixelart", "turns the pixel art look on or off", [], _pixelart, true))


func _rings(_arguments : Array, _sender : int) -> String:
	var rings := _commands.game.get_node_or_null("DebugPlayerRings") as DebugPlayerRings
	if rings == null:
		return "There are no rings: turn on debug_show_role_rings or debug_show_team_rings on the Game"
	rings.visible = not rings.visible
	return "Player rings: " + ("on" if rings.visible else "off")


func _darkness(_arguments : Array, _sender : int) -> String:
	var darkness : CanvasModulate = _commands.game.level.darkness
	darkness.visible = not darkness.visible
	return "Darkness: " + ("on" if darkness.visible else "off")


func _pixelart(_arguments : Array, _sender : int) -> String:
	PixelArt.enabled = not PixelArt.enabled
	return "Pixel art: " + ("on" if PixelArt.enabled else "off")
