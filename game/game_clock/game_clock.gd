class_name GameClock
extends Node

##Keeps the time of the night. Game minutes pass at whatever speed makes the whole span from the start time to the end time take
##real_minutes of real time, and the time shown moves in steps of minutes_per_step: 9:00, 9:15, 9:30...
##An end time at or before the start time means the next day, so 9:00 PM to 6:00 AM is nine hours.
##Time is counted from the network tick the game started on, so every peer shows the same time and a stalled frame doesn't put one behind.

signal time_changed(time_text : String) #the displayed time moved to its next step
signal finished #the end time was reached

enum Period { AM, PM }

const MINUTES_PER_DAY : int = 24 * 60

@export_range(0.1, 120.0, 0.1, "or_greater") var real_minutes : float = 5.0 #how long the whole game lasts, in real minutes
@export_range(1, 60, 1, "or_greater") var minutes_per_step : int = 15 #how many game minutes the displayed time jumps by

@export_group("Start time")
@export_range(1, 12) var start_hour : int = 9
@export_range(0, 59) var start_minute : int = 0
@export var start_period : Period = Period.PM

@export_group("End time")
@export_range(1, 12) var end_hour : int = 10
@export_range(0, 59) var end_minute : int = 0
@export var end_period : Period = Period.PM

var real_seconds_elapsed : float = 0.0
var real_minutes_elapsed : float:
	get:
		return real_seconds_elapsed / 60.0
var game_minutes_elapsed : float = 0.0 #exact, moves every tick. What the clock shows is this rounded down to a step
var is_finished : bool = false

var _shown_game_minutes : int = 0
var _start_tick : int = 0


##Starts counting from start_tick, the tick every peer agreed to start on.
func start(start_tick : int) -> void:
	_start_tick = start_tick
	if not NetworkTime.on_tick.is_connected(_on_network_tick):
		NetworkTime.on_tick.connect(_on_network_tick)


func stop() -> void:
	if NetworkTime.on_tick.is_connected(_on_network_tick):
		NetworkTime.on_tick.disconnect(_on_network_tick)


##How many game minutes the whole game covers.
func total_game_minutes() -> int:
	var total : int = _minute_of_day(end_hour, end_minute, end_period) - _minute_of_day(start_hour, start_minute, start_period)
	return total if total > 0 else total + MINUTES_PER_DAY


##Sets how much real time has passed and updates the game time from it.
func set_real_seconds_elapsed(seconds : float) -> void:
	if is_finished:
		return
	var duration : float = real_minutes * 60.0
	real_seconds_elapsed = clampf(seconds, 0.0, duration)
	game_minutes_elapsed = real_seconds_elapsed * total_game_minutes() / duration
	var reached_end : bool = real_seconds_elapsed >= duration
	#the end time is always shown, even when the steps don't land on it exactly
	var shown : int = total_game_minutes() if reached_end else floori(game_minutes_elapsed / minutes_per_step) * minutes_per_step
	if shown != _shown_game_minutes:
		_shown_game_minutes = shown
		time_changed.emit(get_time_text())
	if reached_end:
		is_finished = true
		stop()
		finished.emit()


##The displayed time as minutes since midnight.
func get_current_minute_of_day() -> int:
	return (_minute_of_day(start_hour, start_minute, start_period) + _shown_game_minutes) % MINUTES_PER_DAY


##The displayed time, for example "9:15 PM".
func get_time_text() -> String:
	var minute_of_day : int = get_current_minute_of_day()
	var hour : int = minute_of_day / 60
	var period : String = "AM" if hour < 12 else "PM"
	return "%d:%02d %s" % [12 if hour % 12 == 0 else hour % 12, minute_of_day % 60, period]


func _minute_of_day(hour : int, minute : int, period : Period) -> int:
	return (hour % 12 + (12 if period == Period.PM else 0)) * 60 + minute


func _on_network_tick(_delta : float, tick : int) -> void:
	set_real_seconds_elapsed(NetworkTime.ticks_to_seconds(tick - _start_tick))
