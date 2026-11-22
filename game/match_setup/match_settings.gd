class_name MatchSettings
extends RefCounted

##What the host chose for a match: the map, whether the debug tools are on, and the game mode. The host menu makes one (MatchSetupPanel), the lobby keeps it as a
##Dictionary (Lobby.match_settings) and sends it to every peer as the match begins, and the Game reads it while it loads.
##The defaults are what a match is without the setup screen: the first map, debug on, the original mode.

enum Mode { ORIGINAL, DEATHMATCH }

const MODE_NAMES : Array[String] = ["Original", "Deathmatch"]
const MAPS : Array = [
	preload("res://game/match_setup/maps/facility.tres"),
	preload("res://game/match_setup/maps/wings.tres"),
]

var map : int = 0 ## index into MAPS
var debug : bool = true ## off: every debug setting is stripped (see DebugRemover)
var mode : int = Mode.ORIGINAL


func map_option() -> MapOption:
	return MAPS[clampi(map, 0, MAPS.size() - 1)]


## Deathmatch: no clock and no teams, artifacts or win to chase, only kills; a player who dies comes back somewhere else in the map.
func is_deathmatch() -> bool:
	return mode == Mode.DEATHMATCH


func to_dict() -> Dictionary:
	return {"map": map, "debug": debug, "mode": mode}


static func from_dict(data : Dictionary) -> MatchSettings:
	var settings : MatchSettings = MatchSettings.new()
	settings.map = clampi(int(data.get("map", 0)), 0, MAPS.size() - 1)
	settings.debug = bool(data.get("debug", true))
	settings.mode = clampi(int(data.get("mode", Mode.ORIGINAL)), 0, MODE_NAMES.size() - 1)
	return settings
