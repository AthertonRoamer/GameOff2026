class_name MapOption
extends Resource

##One map the host can pick for a match. To add a map: make a facility scene (like game/environment/facility_map.tscn), make a MapOption resource for it in
##game/match_setup/maps/ and add that resource to MatchSettings.MAPS.

@export var display_name : String = ""
@export var scene : PackedScene ## the facility: a FacilityMap scene
@export var spawn_room : String = "" ## the id of the room the players start in (the middle of it)
