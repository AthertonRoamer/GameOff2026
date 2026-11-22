class_name Acoustics
extends Resource

##How the facility carries sound: every number that decides what the player hears, in one resource (game/audio/acoustics.tres) to tweak in the inspector.
##Sound travels along the cheapest way from where it is made to the listener. Open floor and open doors are free, a closed door and a wall cost extra
##"metres" of distance (a wall is leaked through, just very quietly), so a sound carries down a hallway and out of an open door but is dull and faint
##through a wall. The distance it is then heard from is the length of that way, and its direction is the way it arrives (round the corner, from the doorway).

const PX_PER_METRE : float = 44.0 ## the world's scale (a map cell is a quarter metre)

@export_group("Travel")
@export_range(0.0, 30.0, 0.5, "suffix:m") var wall_extra_m : float = 9.0 ## added distance for each wall cell the sound goes through
@export_range(0.0, 30.0, 0.5, "suffix:m") var closed_door_extra_m : float = 5.0 ## a closed or locked door
@export_range(0.0, 10.0, 0.25, "suffix:m") var open_door_extra_m : float = 0.0
@export_range(0.5, 6.0, 0.25, "suffix:m") var lookahead_m : float = 1.5 ## the direction is taken from this far back along the path, so it points at the doorway rather than the next cell

@export_group("Muffling")
@export var clear_bus : StringName = &"SFX"
@export var muffled_bus : StringName = &"SFX Muffled" ## low-passed (see audio_bus_layout.tres: change the cutoff there)
@export var heavy_bus : StringName = &"SFX Heavy" ## very dull: through several walls
@export_range(0.0, 3.0, 0.05) var wall_muffle : float = 0.5 ## muffling added per wall cell crossed
@export_range(0.0, 3.0, 0.05) var closed_door_muffle : float = 0.45
@export_range(0.0, 2.0, 0.05) var indirect_muffle : float = 0.1 ## a sound that comes round a corner loses a little of its top
@export_range(0.0, 3.0, 0.05) var muffled_from : float = 0.3
@export_range(0.0, 3.0, 0.05) var heavy_from : float = 0.9

@export_group("Echo")
@export var echo_bus : StringName = &"SFX Echo" ## a reverb that is all echo (audio_bus_layout.tres: room size, damping, pre-delay)
@export_range(-30.0, 6.0, 0.5, "suffix:dB") var echo_gain_db : float = -14.0 ## the master echo level: lower for subtler
@export_range(0.0, 1.0, 0.05) var echo_carry : float = 0.5 ## how far the echo reaches compared to the sound itself (1: no further)
@export var echo_by_room : Dictionary = {"corridor": 1.0, "utility": 0.6, "item": 0.5, "office": 0.4, "exterior_room": 0.5, "outdoor": 0.1} ## room kind -> how echoey (0 to 1)

@export_group("Voices")
@export_range(4, 64) var voices : int = 24 ## sounds that can play at once
@export_range(-24.0, 6.0, 0.5, "suffix:dB") var own_sound_db : float = -5.0 ## the listener's own footsteps and shots are a little quieter
@export_range(0.0, 3.0, 0.1, "suffix:s") var quiet_at_start : float = 1.5 ## door sounds are ignored this long after the game loads (the doors settle into their starting state)


func echo_of(room_kind : String) -> float:
	return float(echo_by_room.get(room_kind, 0.5))


func bus_for(muffle : float) -> StringName:
	if muffle >= heavy_from:
		return heavy_bus
	return muffled_bus if muffle >= muffled_from else clear_bus
