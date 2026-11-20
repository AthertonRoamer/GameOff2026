class_name DebugConsole
extends CanvasLayer

## The debug console: ` (backtick) opens a line to type debug commands into, and Esc or ` closes it. It is only the front end: DebugCommands (the sibling node) parses
## and runs what is typed, wherever it has to run. Up and Down walk through earlier lines, Tab completes a command's name.
## While it is open the local player does not move or shoot, and the answers are printed here instead of in the corner.
## Removable with the rest of the debug tools: when DebugCommands is off (DebugRemover, a release) this node removes itself.

const TOGGLE_KEY : Key = KEY_QUOTELEFT
const LOG_LINES : int = 200

@onready var _log : RichTextLabel = $Panel/Box/Log
@onready var _line : LineEdit = $Panel/Box/Input
@onready var _commands : DebugCommands = $"../DebugCommands"

var _history : PackedStringArray = []
var _history_at : int = 0
var _player_was_active : bool = true


func _ready() -> void:
	if not _commands.enabled:
		queue_free()
		return
	visible = false
	_commands.output.connect(_print)
	_line.text_submitted.connect(_submit)


func _input(event : InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key : Key = (event as InputEventKey).keycode
	if key == TOGGLE_KEY:
		_set_open(not visible)
	elif visible and key == KEY_ESCAPE:
		_set_open(false)
	elif visible and key == KEY_UP:
		_walk_history(-1)
	elif visible and key == KEY_DOWN:
		_walk_history(1)
	elif visible and key == KEY_TAB:
		_complete()
	else:
		return
	get_viewport().set_input_as_handled()


func _set_open(open : bool) -> void:
	visible = open
	_commands.show_toasts = not open
	var player : Player = _commands.game.spawner.local_player
	if open:
		_line.clear()
		_line.grab_focus()
		_history_at = _history.size()
		if is_instance_valid(player):
			_player_was_active = player.input.active
			player.set_active(false) #typing does not walk the player about
	elif is_instance_valid(player) and player.is_alive():
		player.set_active(_player_was_active)


func _submit(line : String) -> void:
	_line.clear()
	if line.strip_edges() == "":
		return
	if _history.is_empty() or _history[_history.size() - 1] != line:
		_history.append(line)
	_history_at = _history.size()
	_print("> " + line)
	_commands.run(line)


func _walk_history(step : int) -> void:
	if _history.is_empty():
		return
	_history_at = clampi(_history_at + step, 0, _history.size())
	_line.text = _history[_history_at] if _history_at < _history.size() else ""
	_line.caret_column = _line.text.length()


func _complete() -> void:
	var typed : String = _line.text.strip_edges(true, false)
	if typed.contains(" "):
		return
	var matches : PackedStringArray = []
	for command_name in _commands.command_names():
		if command_name.begins_with(typed.trim_prefix("/")):
			matches.append(command_name)
	if matches.size() == 1:
		_line.text = matches[0] + " "
		_line.caret_column = _line.text.length()
	elif matches.size() > 1:
		_print(", ".join(matches))


func _print(text : String) -> void:
	_log.append_text(text.replace("[", "[lb]") + "\n")
	while _log.get_paragraph_count() > LOG_LINES:
		_log.remove_paragraph(0)
