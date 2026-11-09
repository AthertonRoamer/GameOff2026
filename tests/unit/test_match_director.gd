extends Node

# Offline test for the win rules and the end screen. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_match_director.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const A1 : int = 11
const A2 : int = 12
const D1 : int = 21
const D2 : int = 22

var failures : int = 0
var teams : Dictionary = {A1: Team.ATTACKERS, A2: Team.ATTACKERS, D1: Team.DEFENDERS, D2: Team.DEFENDERS}
var roster : Array = [
	{"id": A1, "name": "Ann", "role": "Infiltrator", "team": Team.ATTACKERS},
	{"id": D1, "name": "Dee", "role": "Medic", "team": Team.DEFENDERS},
]


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func in_play_except(out : Array) -> Callable:
	return func(id : int) -> bool: return not out.has(id)


func make_director(is_in_play : Callable, results : Array) -> MatchDirector:
	var director : MatchDirector = MatchDirector.new()
	director.results_seconds = 0.05
	add_child(director)
	director.match_ended.connect(func(reason : int, _r : Array) -> void: results.append(reason))
	director.begin(teams, roster, is_in_play)
	return director


func _ready() -> void:
	#who wins
	check(MatchDirector.winner_of(MatchDirector.Reason.TIME_UP) == Team.DEFENDERS, "the clock running out is a defender win")
	check(MatchDirector.winner_of(MatchDirector.Reason.ATTACKERS_ELIMINATED) == Team.DEFENDERS, "eliminating the attackers is a defender win")
	check(MatchDirector.winner_of(MatchDirector.Reason.ARTIFACT_STOLEN) == Team.ATTACKERS, "getting the artifact out is an attacker win")

	#elimination
	check(not MatchDirector.are_all_attackers_out(teams, in_play_except([A1])), "one attacker left: not eliminated")
	check(MatchDirector.are_all_attackers_out(teams, in_play_except([A1, A2])), "every attacker out: eliminated")
	check(not MatchDirector.are_all_attackers_out(teams, in_play_except([D1, D2])), "every defender out: the attackers have not won or lost")
	check(not MatchDirector.are_all_attackers_out({D1: Team.DEFENDERS}, in_play_except([D1])), "a match with no attackers never counts them eliminated")

	#the director, driven as the game drives it
	var results : Array = []
	var not_begun : MatchDirector = MatchDirector.new()
	add_child(not_begun)
	not_begun.on_time_up()
	check(not not_begun.is_decided, "nothing can end a match that hasn't begun (every client's clock also finishes)")
	not_begun.free()

	var out : Array = [D1, D2]
	var director : MatchDirector = make_director(in_play_except(out), results)
	var returned : Array[bool] = [false]
	director.return_to_lobby.connect(func() -> void: returned[0] = true)
	director.check_elimination()
	await get_tree().process_frame
	check(results.is_empty(), "killing every defender does not end the match")
	out.append_array([A1, A2])
	director.check_elimination()
	check(results.is_empty(), "elimination waits for the end of the frame")
	await get_tree().process_frame
	check(results == [MatchDirector.Reason.ATTACKERS_ELIMINATED], "the last attacker going down ends the match")
	director.on_time_up()
	director.report_artifact_escaped()
	check(results.size() == 1, "the first result is final")
	await get_tree().create_timer(0.2).timeout
	check(returned[0], "the lobby returns everyone once the results have been up")
	director.free()

	results = []
	director = make_director(in_play_except([]), results)
	director.report_artifact_escaped()
	check(results == [MatchDirector.Reason.ARTIFACT_STOLEN], "the artifact leaving the facility ends the match")
	director.free()

	#the real scene: the clock is wired to the director, and the result reaches the end screen
	var game : Game = GAME_SCENE.instantiate()
	add_child(game)
	check(not game.end_screen.visible, "the end screen starts hidden")
	game.match_director.begin(teams, roster, in_play_except([]))
	game.game_clock.set_real_seconds_elapsed(game.game_clock.real_minutes * 60.0)
	check(game.match_director.is_decided, "the clock running out decides the match")
	check(game.end_screen.visible and not game.player_hud.visible, "the end screen replaces the HUD")
	check(game.end_screen.reason_label.text.begins_with("Defenders win."), "the end screen says who won")
	check(game.end_screen.roster_box.get_child_count() == roster.size(), "the end screen lists every player")
	check(game.end_screen.countdown_label.text == "Returning to lobby in 10", "the default countdown is 10 seconds")
	game.free()

	#victory or defeat depends on who is looking
	var screen : EndScreen = preload("res://game/end_screen/end_screen.tscn").instantiate()
	add_child(screen)
	screen.show_result(MatchDirector.Reason.ARTIFACT_STOLEN, roster, A1, 10.0)
	check(screen.title_label.text == "Victory", "an attacker sees victory when attackers win")
	screen.free()
	screen = preload("res://game/end_screen/end_screen.tscn").instantiate()
	add_child(screen)
	screen.show_result(MatchDirector.Reason.ARTIFACT_STOLEN, roster, D1, 10.0)
	check(screen.title_label.text == "Defeat", "a defender sees defeat when attackers win")
	screen.free()
	screen = preload("res://game/end_screen/end_screen.tscn").instantiate()
	add_child(screen)
	screen.show_result(MatchDirector.Reason.TIME_UP, roster, 999, 10.0)
	check(screen.title_label.text == "Defenders win", "a peer with no player just sees who won")
	screen.free()

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
