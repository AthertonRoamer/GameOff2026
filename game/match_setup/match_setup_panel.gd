class_name MatchSetupPanel
extends VBoxContainer

##The host's match options, in the lobby menu: which map, whether debug is on, and the game mode. `changed` says every time one of them is set; settings() is what is
##chosen now. The lobby menu sends it to the lobby (see HostMenu).

signal changed(settings : MatchSettings)

@onready var _map : OptionButton = $MapRow/Map
@onready var _debug : CheckButton = $DebugRow/Debug
@onready var _mode : OptionButton = $ModeRow/Mode


func _ready() -> void:
	for option : MapOption in MatchSettings.MAPS:
		_map.add_item(option.display_name)
	for mode_name : String in MatchSettings.MODE_NAMES:
		_mode.add_item(mode_name)
	_debug.button_pressed = MatchSettings.new().debug
	_map.item_selected.connect(func(_i : int) -> void: changed.emit(settings()))
	_mode.item_selected.connect(func(_i : int) -> void: changed.emit(settings()))
	_debug.toggled.connect(func(_on : bool) -> void: changed.emit(settings()))


func settings() -> MatchSettings:
	var chosen : MatchSettings = MatchSettings.new()
	chosen.map = maxi(_map.selected, 0)
	chosen.debug = _debug.button_pressed
	chosen.mode = maxi(_mode.selected, 0)
	return chosen
