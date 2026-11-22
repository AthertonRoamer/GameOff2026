class_name MatchPhase
extends Node

##One step between the match starting and play beginning (showing each player their role, picking a spawn point...). Phases are the children of
##MatchPhases and run in tree order, one at a time; add one by dropping its scene under MatchPhases in game.tscn.
##A phase is a scene: a script extending this, with its own screen (a CanvasLayer) as children, designed in the editor.
##Every peer runs the same phase over the same ticks: enter() on the tick it starts and exit() on the tick it ends. When it ends is the lobby's
##decision (duration_seconds running out, or lobby_is_done() saying so sooner), see MatchPhases. Players are inactive the whole time and the
##HUD is hidden. A phase that needs a player's input sends it with an RPC on its own node, which is at the same path on every peer.

@export var duration_seconds : float = 5.0 #the longest this phase lasts. The lobby can end it sooner, see lobby_is_done()

var game : Game #set by MatchPhases before enter(): the local player, roles, the map...
var started_tick : int = -1 #the tick this phase began on, the same on every peer


##Every peer, on the tick this phase starts. Show its screen here.
func enter() -> void:
	pass


##Every peer, on the tick this phase ends. Hide its screen and apply what it decided here (players are still inactive, so moving them is safe).
func exit() -> void:
	pass


##Lobby only, asked every tick while this phase runs (with that tick): true ends it before its duration is up (say, once every player has chosen).
func lobby_is_done(_tick : int) -> bool:
	return false


func duration_ticks() -> int:
	return ceili(duration_seconds * NetworkTime.tickrate)


##Seconds until duration_seconds runs out, for a countdown on the phase's screen. The lobby may still end the phase sooner.
func seconds_left() -> float:
	if started_tick < 0:
		return duration_seconds
	return maxf(0.0, (started_tick + duration_ticks() - NetworkTime.tick) / float(NetworkTime.tickrate))
