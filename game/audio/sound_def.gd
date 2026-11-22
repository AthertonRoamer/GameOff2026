class_name SoundDef
extends Resource

##One sound the game can make, edited in the inspector: which clips, how loud, how far it carries. The clips are either listed in `clips` or simply every audio
##file in `folder`: drop another .wav or .ogg into the folder (game/audio/sounds/...) and it joins the variations, with nothing else to set up.
##A sound is played with SoundSystem.play(def, position); where it is heard, how much the map muffles it and how it echoes is the SoundSystem's job (see Acoustics).

const EXTENSIONS : PackedStringArray = ["wav", "ogg", "mp3"]

@export_dir var folder : String = "" ## every audio file in this folder is a variation of the sound
@export var clips : Array[AudioStream] = [] ## variations listed by hand (used as well as the folder's)

@export_group("Loudness")
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db : float = 0.0
@export_range(0.0, 8.0, 0.1, "suffix:dB") var volume_jitter_db : float = 1.5 ## each play is this much louder or quieter, at random
@export_range(0.5, 2.0, 0.01) var pitch_min : float = 0.97 ## each play's pitch is picked between these two (1 is the recording as it is)
@export_range(0.5, 2.0, 0.01) var pitch_max : float = 1.03

@export_group("Distance")
@export_range(1.0, 300.0, 0.5, "suffix:m") var range_m : float = 14.0 ## how far the sound carries: it is silent beyond this (counted along the way it travels, round corners and through doors)
@export_range(0.2, 4.0, 0.05) var falloff : float = 1.6 ## how quickly it fades with distance: 1 is steady, higher is quiet sooner
@export_range(0.0, 1.0, 0.05) var echo : float = 1.0 ## how much of the room's echo it gets (0 is a dry sound, like a close click)

@export_group("Cue")
@export var show_cue : bool = true ## the soft marker at the edge of the screen that points to where it came from (SoundCue)
@export_range(0.0, 1.0, 0.05) var cue_strength : float = 0.6 ## how bright that marker is for a sound heard at full volume

var _all : Array[AudioStream] = []
var _loaded : bool = false
var _last : int = -1


##Every variation: the listed clips and the folder's files (found once). Also works in an exported game, where a file is listed as name.wav.import.
func get_clips() -> Array[AudioStream]:
	if _loaded:
		return _all
	_loaded = true
	_all = clips.duplicate()
	if folder != "":
		for file : String in DirAccess.get_files_at(folder):
			var clean : String = file.trim_suffix(".import").trim_suffix(".remap")
			if clean.get_extension().to_lower() in EXTENSIONS:
				var stream : AudioStream = load(folder.path_join(clean)) as AudioStream
				if stream != null and not _all.has(stream):
					_all.append(stream)
	return _all


##A variation at random, never the one just played (null if the sound has no clips yet).
func pick() -> AudioStream:
	var all : Array[AudioStream] = get_clips()
	if all.is_empty():
		return null
	var index : int = randi() % all.size()
	if all.size() > 1 and index == _last:
		index = (index + 1 + randi() % (all.size() - 1)) % all.size()
	_last = index
	return all[index]
