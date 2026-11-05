extends Node

##Does the game's expensive one-time loading when the program starts, so it does not happen while a networked game loads.
##It is an autoload (project settings, named WarmUp), so it runs once per process, the headless lobby included.
##
##Why: a game is loaded while netfox's clock is already running. A peer that freezes then stops sending its input, and the lobby stops confirming
##every player's state until it arrives, so everyone has to roll back further than netfox's history (64 ticks, about a second) allows:
##"Trying to run rollback for ticks ... past the history limit". The first player's skin (sprite sheets), the map's tile set and the flashlight
##texture together froze the load for about a quarter of a second on a fast machine, and much longer in debug runs from the editor.
##Anything else that is slow the first time and happens during a game load belongs here too.


func _ready() -> void:
	var started : int = Time.get_ticks_usec()
	NightShiftCharacter.load_role("res://game/player/skin", "guard") #the sheets and frames every guard skin shares
	FacilityTileSet.shared() #the map's tile set (its art and wall shapes)
	Flashlight._get_cone_texture() #the beam's light texture
	print_verbose("WarmUp: %.0f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
