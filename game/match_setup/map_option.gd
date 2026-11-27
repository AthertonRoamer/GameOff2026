class_name MapOption
extends Resource

##One map the host can pick for a match. To add a map: make a facility scene (like game/environment/facility_map.tscn), make a MapOption resource for it in
##game/match_setup/maps/ and add that resource to MatchSettings.MAPS.

@export var display_name : String = ""
@export_file("*.tscn") var scene_path : String = "" ## the facility: a FacilityMap scene. A path, not the scene itself: only the map a match uses is loaded, when it begins
@export var spawn_room : String = "" ## the id of the room the players start in (the middle of it). Empty: the map picks its biggest corridor (FacilityMap.start_room)
