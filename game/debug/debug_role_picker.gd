class_name DebugRolePicker
extends CanvasLayer

## A debug menu to choose your own role: F2 opens a button for each role in the game, and a click gives you it (the console's `role` command, so the lobby decides
## and every peer is told). It closes after a pick, or on F2 or Esc. While it is open the local player does not move or shoot.
## Removable with the rest of the debug tools: when DebugCommands is off (DebugRemover, a release) this node removes itself.

const TOGGLE_KEY : Key = KEY_F2

@onready var _commands : DebugCommands = $"../DebugCommands"
@onready var _list : VBoxContainer = $Panel/Box/Roles
@onready var _status : Label = $Panel/Box/Status

var _player_was_active : bool = true


func _ready() -> void:
	if not _commands.enabled:
		queue_free()
		return
	visible = false
	_commands.output.connect(func(text : String) -> void: _status.text = text)


func _input(event : InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key : Key = (event as InputEventKey).keycode
	if key == TOGGLE_KEY:
		_set_open(not visible)
	elif visible and key == KEY_ESCAPE:
		_set_open(false)
	else:
		return
	get_viewport().set_input_as_handled()


## One button per role the game has (a client's pick goes to the lobby, which decides).
func _fill() -> void:
	for child : Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for role : Role in _commands.game.role_assigner.all_roles():
		var button := Button.new()
		button.text = role.role_name
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_pick.bind(role))
		_list.add_child(button)


func _pick(role : Role) -> void:
	_commands.run("role " + role.role_name)
	_set_open(false)


func _set_open(open : bool) -> void:
	visible = open
	var player : Player = _commands.game.spawner.local_player
	if open:
		_fill() #(here, not in _ready: the game knows its roles only once it is ready)
		_status.text = ""
		_player_was_active = is_instance_valid(player) and player.input.active
		if is_instance_valid(player):
			player.set_active(false) #clicking a button does not shoot
	elif is_instance_valid(player) and player.is_alive():
		player.set_active(_player_was_active)
