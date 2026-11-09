extends Node

# Offline test for GameClock and its HUD label. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_game_clock.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func make_clock(real : float, step : int, from : Array, to : Array) -> GameClock:
	var clock : GameClock = GameClock.new()
	clock.real_minutes = real
	clock.minutes_per_step = step
	clock.start_hour = from[0]
	clock.start_minute = from[1]
	clock.start_period = from[2]
	clock.end_hour = to[0]
	clock.end_minute = to[1]
	clock.end_period = to[2]
	return clock


func _ready() -> void:
	var am : GameClock.Period = GameClock.Period.AM
	var pm : GameClock.Period = GameClock.Period.PM

	#the example: 9 to 10 PM in 5 real minutes, 15 minute steps
	var clock : GameClock = make_clock(5.0, 15, [9, 0, pm], [10, 0, pm])
	var shown : Array[String] = []
	var finish_count : Array[int] = [0]
	clock.time_changed.connect(func(text : String) -> void: shown.append(text))
	clock.finished.connect(func() -> void: finish_count[0] += 1)
	check(clock.total_game_minutes() == 60, "9 PM to 10 PM is 60 game minutes")
	check(clock.get_time_text() == "9:00 PM", "starts at the start time")
	clock.set_real_seconds_elapsed(74.9)
	check(clock.get_time_text() == "9:00 PM", "just before the first step still shows the start time")
	check(is_equal_approx(clock.game_minutes_elapsed, 74.9 / 5.0), "game minutes pass continuously between steps")
	clock.set_real_seconds_elapsed(75.0)
	check(clock.get_time_text() == "9:15 PM", "a quarter of the real time is the first step")
	check(is_equal_approx(clock.real_minutes_elapsed, 1.25), "real minutes are tracked")
	clock.set_real_seconds_elapsed(150.0)
	clock.set_real_seconds_elapsed(225.0)
	check(clock.get_time_text() == "9:45 PM", "three quarters of the real time is the third step")
	check(finish_count[0] == 0 and not clock.is_finished, "not finished before the real time is up")
	clock.set_real_seconds_elapsed(300.0)
	check(clock.get_time_text() == "10:00 PM", "shows the end time when the real time is up")
	check(finish_count[0] == 1 and clock.is_finished, "finished when the real time is up")
	clock.set_real_seconds_elapsed(400.0)
	check(finish_count[0] == 1, "finishes only once")
	check(", ".join(shown) == "9:15 PM, 9:30 PM, 9:45 PM, 10:00 PM", "time_changed fires once per step, in order")
	clock.free()

	#the 12 o'clock hours and crossing midnight
	clock = make_clock(9.0, 60, [9, 0, pm], [6, 0, am])
	check(clock.total_game_minutes() == 9 * 60, "an end time earlier in the day is the next morning")
	clock.set_real_seconds_elapsed(3.0 * 60.0)
	check(clock.get_time_text() == "12:00 AM", "midnight is 12:00 AM")
	clock.set_real_seconds_elapsed(4.0 * 60.0)
	check(clock.get_time_text() == "1:00 AM", "the hour after midnight is 1:00 AM")
	clock.free()
	clock = make_clock(2.0, 30, [11, 30, am], [12, 30, pm])
	check(clock.total_game_minutes() == 60, "11:30 AM to 12:30 PM is 60 game minutes")
	clock.set_real_seconds_elapsed(60.0)
	check(clock.get_time_text() == "12:00 PM", "noon is 12:00 PM")
	clock.free()

	#steps that don't divide the span: the last one is cut short so the end time is still reached on time
	clock = make_clock(1.0, 25, [9, 0, pm], [10, 0, pm])
	clock.set_real_seconds_elapsed(59.0)
	check(clock.get_time_text() == "9:50 PM", "uneven steps stay on the step before the end")
	clock.set_real_seconds_elapsed(60.0)
	check(clock.get_time_text() == "10:00 PM" and clock.is_finished, "uneven steps still end on the end time")
	clock.free()

	#the real scene: the GameClock node exists and drives the label, which is anchored to the top right
	var game : Game = GAME_SCENE.instantiate()
	add_child(game)
	var label : Label = game.player_hud.clock_label
	check(game.get_node("GameClock") == game.game_clock, "the game has a GameClock node")
	check(label.visible and label.text == game.game_clock.get_time_text(), "the HUD shows the time as soon as the game loads")
	check(label.anchor_left == 1.0 and label.anchor_right == 1.0 and label.anchor_top == 0.0 and label.anchor_bottom == 0.0, "the label is anchored to the top right")
	game.game_clock.set_real_seconds_elapsed(game.game_clock.real_minutes * 60.0 / 4.0)
	check(label.text == game.game_clock.get_time_text() and label.text != "9:00 PM", "the HUD follows the clock")
	game.free()

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
