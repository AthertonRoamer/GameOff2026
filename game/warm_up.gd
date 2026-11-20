extends Node

##Does the game's expensive one-time loading when the program starts, so it does not happen while a networked game loads.
##It is an autoload (project settings, named WarmUp), so it runs once per process, the headless lobby included.
##
##Why: a game is loaded while netfox's clock is already running. A peer that freezes then stops sending its input, and the lobby stops confirming
##every player's state until it arrives, so everyone has to roll back further than netfox's history (128 ticks, about two seconds) allows:
##"Trying to run rollback for ticks ... past the history limit". The first player's skin (sprite sheets), the map's tile set and the flashlight
##texture froze the load for about a quarter of a second on a fast machine, and much longer in debug runs from the editor. Measured since: compiling
##the player's scripts (and netfox's rollback ones) the first time costs about as much again, so the whole game scene is loaded here too.
##Anything else that is slow the first time and happens during a game load belongs here too.

const SCENES : Array[String] = ["res://game/game.tscn"] #loaded in the background, with everything they need (scripts, the player, the level)

var _kept : Array[Resource] = [] #the loaded scenes: the resource cache only holds what something still references
var _loading : Array[String] = SCENES.duplicate()


func _ready() -> void:
	var started : int = Time.get_ticks_usec()
	SkinFrames.load_role("res://game/player/skin", "guard") #the sheets and frames every guard skin shares
	FacilityTileSet.shared() #the map's tile set (its art and wall shapes)
	Flashlight._get_cone_texture() #the beam's light texture
	print_verbose("WarmUp: %.0f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	for path in _loading:
		ResourceLoader.load_threaded_request(path) #off the main thread, so the menu does not wait for it
	set_process(not _loading.is_empty())


func _process(_delta : float) -> void:
	for path in _loading.duplicate():
		var status : ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_kept.append(ResourceLoader.load_threaded_get(path))
			_loading.erase(path)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("WarmUp: could not load %s" % path)
			_loading.erase(path)
	set_process(not _loading.is_empty())
