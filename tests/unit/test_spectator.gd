extends Node

## Spectator: who the camera follows once the local player is dead.

class FakePlayer extends Node2D:
	var alive : bool = true
	var camera : Camera2D = Camera2D.new()
	func _init() -> void:
		add_child(camera)
	func is_alive() -> bool:
		return alive

var _failures : int = 0


func _ready() -> void:
	var all : Array = []
	for i in 3:
		var player : FakePlayer = FakePlayer.new()
		player.name = "P%d" % i
		player.position = Vector2(100 * i, 0)
		add_child(player)
		all.append(player)
	var me : FakePlayer = all[0]
	me.camera.make_current()
	var spectator : Spectator = (load("res://game/spectator/spectator.tscn") as PackedScene).instantiate()
	spectator.delay_seconds = 0.2
	spectator.players = func() -> Array: return all
	spectator.local_player = func() -> Node2D: return me
	spectator.name_of = func(p : Node2D) -> String: return String(p.name)
	add_child(spectator)
	await _wait(0.4)
	check(not spectator.is_spectating() and me.camera.is_current(), "alive: your own camera")
	me.alive = false
	await get_tree().process_frame
	check(not spectator.is_spectating(), "just died: you watch your own fall first")
	await _wait(0.5)
	check(spectator.target == all[1] and spectator.camera.is_current() and spectator.camera.global_position == all[1].global_position, "then the camera follows a living player")
	check(spectator.label.text.contains("P1") and spectator.screen.visible, "with their name")
	all[1].position = Vector2(500, 40)
	await _wait(0.1)
	check(spectator.camera.global_position == Vector2(500, 40), "and follows them as they move")
	spectator.cycle(1)
	check(spectator.target == all[2], "D: the next one")
	spectator.cycle(1)
	check(spectator.target == all[1], "round again, never yourself")
	spectator.cycle(-1)
	check(spectator.target == all[2], "A: the one before")
	all[2].alive = false
	await _wait(0.1)
	check(spectator.target == all[1], "the watched one dies: on to another")
	all[1].alive = false
	await _wait(0.1)
	check(not spectator.is_spectating() and me.camera.is_current(), "nobody left: back by your body")
	all[1].alive = true
	await _wait(0.1)
	check(spectator.target == all[1], "someone alive again: watched again")
	me.alive = true
	await _wait(0.1)
	check(not spectator.is_spectating() and me.camera.is_current() and not spectator.screen.visible, "revived: your own camera again")
	spectator.allowed = func() -> bool: return false
	me.alive = false
	await _wait(0.5)
	check(not spectator.is_spectating(), "not allowed (a deathmatch, or before play): no spectating")
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(_failures)


func _wait(seconds : float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func check(ok : bool, what : String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
