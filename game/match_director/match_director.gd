class_name MatchDirector
extends Node

##Decides who wins and when the match is over. The lobby decides: its players' health is the real one, and only it knows every team.
##Defenders win when the clock runs out or when every attacker is eliminated. Attackers win when the correct artifact has left the facility.
##Killing every defender wins nothing: the attackers still have to get the artifact out.
##The first result reached is final. Every peer is then told the result and shows it, and after results_seconds the lobby returns everyone to it.

signal match_ended(reason : int, roster : Array) #on every peer. roster: [{id, name, role, team}], see Game._build_roster
signal return_to_lobby #lobby only: the results have been up for results_seconds

enum Reason { TIME_UP, ATTACKERS_ELIMINATED, ARTIFACT_STOLEN }

@export var results_seconds : float = 10.0 #how long the end screen stays up before everyone goes back to the lobby

var is_decided : bool = false

var _running : bool = false #lobby only, from begin() on
var _teams : Dictionary = {} #member id -> Team, every member
var _roster : Array = []
var _is_in_play : Callable #(member id) -> bool


static func winner_of(reason : int) -> int:
	return Team.ATTACKERS if reason == Reason.ARTIFACT_STOLEN else Team.DEFENDERS


static func describe(reason : int) -> String:
	match reason:
		Reason.TIME_UP: return "The shift ended and the attackers never got away."
		Reason.ATTACKERS_ELIMINATED: return "Every attacker was eliminated."
		Reason.ARTIFACT_STOLEN: return "The artifact was carried out of the facility."
	return ""


static func are_all_attackers_out(teams : Dictionary, is_in_play : Callable) -> bool:
	var attackers : Array = teams.keys().filter(func(id : int) -> bool: return teams[id] == Team.ATTACKERS)
	return not attackers.is_empty() and not attackers.any(is_in_play)


##Lobby only, when the match starts. Nothing can end the match before this.
func begin(teams : Dictionary, roster : Array, is_in_play : Callable) -> void:
	_teams = teams
	_roster = roster
	_is_in_play = is_in_play
	_running = true


func on_time_up() -> void:
	_decide(Reason.TIME_UP)


##Lobby only. Call this when the player carrying the correct artifact has exited the facility.
func report_artifact_escaped() -> void:
	_decide(Reason.ARTIFACT_STOLEN)


##Lobby only. Call after a player dies or leaves. Waits for the end of the frame so players who go down together are all counted.
func check_elimination() -> void:
	_check_elimination.call_deferred()


func _check_elimination() -> void:
	if _running and are_all_attackers_out(_teams, _is_in_play):
		_decide(Reason.ATTACKERS_ELIMINATED)


func _decide(reason : int) -> void:
	if not _running or is_decided:
		return
	is_decided = true
	Main.output("Match over: %s win (%s)" % [Team.name_of(winner_of(reason)), Reason.find_key(reason)])
	_show_result.rpc(reason, _roster)
	await get_tree().create_timer(results_seconds).timeout
	return_to_lobby.emit()


@rpc("authority", "call_local", "reliable")
func _show_result(reason : int, roster : Array) -> void:
	match_ended.emit(reason, roster)
