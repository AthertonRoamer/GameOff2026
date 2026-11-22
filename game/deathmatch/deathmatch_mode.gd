class_name DeathmatchMode
extends Node

##The rules of a deathmatch: a kill is a point, and when the time is up the most kills win. Only Game makes this node, and only in a deathmatch (see MatchSettings).
##The lobby decides: it counts the kills (Game tells it who shot whom) and ends the match; every peer is told the scores as they change and the result at the end.
##The time is counted from the network tick the match started on, so every peer shows the same clock.

signal scores_changed
signal time_changed(seconds_left : float) #once a second
signal finished(result : Array) #on every peer. result: [{id, name, kills}], most kills first
signal return_to_lobby #lobby only: the results have been up for results_seconds

@export var duration_seconds : float = 300.0 ## five minutes
@export var results_seconds : float = 10.0 ## how long the result stays up before everyone goes back to the lobby

var scores : Dictionary = {} #member id -> kills
var is_over : bool = false
var name_of : Callable = Callable() #(member id) -> String, set by Game
var member_ids : Callable = Callable() #() -> Array of every member's id, lobby only, set by Game

var _is_lobby : bool = false
var _start_tick : int = 0
var _running : bool = false
var _shown_second : int = -1


static func format_time(seconds : float) -> String:
	var whole : int = maxi(ceili(seconds), 0)
	return "%d:%02d" % [whole / 60, whole % 60]


## Every peer, on the tick the match starts.
func begin(start_tick : int, is_lobby : bool) -> void:
	_start_tick = start_tick
	_is_lobby = is_lobby
	_running = true
	if not NetworkTime.on_tick.is_connected(_on_network_tick):
		NetworkTime.on_tick.connect(_on_network_tick)


func _exit_tree() -> void:
	if NetworkTime.on_tick.is_connected(_on_network_tick):
		NetworkTime.on_tick.disconnect(_on_network_tick)


## Lobby only: the killer's point (nothing for a death nobody caused, or for killing oneself).
func record_kill(killer_id : int, victim_id : int) -> void:
	if not _is_lobby or not _running or is_over or killer_id == victim_id or killer_id <= 0:
		return
	scores[killer_id] = scores.get(killer_id, 0) + 1
	_receive_scores.rpc(scores)


@rpc("authority", "call_local", "reliable")
func _receive_scores(new_scores : Dictionary) -> void:
	scores = new_scores
	scores_changed.emit()


## The first lines of the board for a player: their own kills, then the best three.
func scoreboard_text(local_id : int) -> String:
	var lines : PackedStringArray = ["Kills  %d" % scores.get(local_id, 0)]
	var ranking : Array = ranked()
	for i in mini(ranking.size(), 3):
		var entry : Dictionary = ranking[i]
		lines.append("%d. %s  %d%s" % [i + 1, entry["name"], entry["kills"], "  <" if entry["id"] == local_id else ""])
	return "\n".join(lines)


## Everyone who has a point, most kills first.
func ranked() -> Array:
	var result : Array = []
	for id : int in scores:
		result.append({"id": id, "name": _name(id), "kills": scores[id]})
	result.sort_custom(func(a : Dictionary, b : Dictionary) -> bool: return a["kills"] > b["kills"])
	return result


func _name(id : int) -> String:
	return name_of.call(id) if name_of.is_valid() else str(id)


func _on_network_tick(_delta : float, tick : int) -> void:
	var left : float = duration_seconds - NetworkTime.ticks_to_seconds(tick - _start_tick)
	var second : int = ceili(maxf(left, 0.0))
	if second != _shown_second:
		_shown_second = second
		time_changed.emit(maxf(left, 0.0))
	if left <= 0.0 and _is_lobby and not is_over:
		_finish()


## Lobby only: everyone is told the final table: every member, with the kills they made.
func _finish() -> void:
	is_over = true
	var table : Array = []
	var ids : Array = member_ids.call() if member_ids.is_valid() else scores.keys()
	for id : int in scores:
		if not ids.has(id): #(a player who left still has their kills on the table)
			ids.append(id)
	for id : int in ids:
		table.append({"id": id, "name": _name(id), "kills": scores.get(id, 0)})
	table.sort_custom(func(a : Dictionary, b : Dictionary) -> bool: return a["kills"] > b["kills"])
	_show_result.rpc(table)
	await get_tree().create_timer(results_seconds).timeout
	return_to_lobby.emit()


@rpc("authority", "call_local", "reliable")
func _show_result(table : Array) -> void:
	is_over = true
	_running = false
	finished.emit(table)
