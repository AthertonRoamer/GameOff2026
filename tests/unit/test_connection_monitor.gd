extends Node

## ConnectionMonitor: what the connection symbol is told, from heartbeats and the ping.

var _failures : int = 0
var _now : float = 0.0
var _number : int = 0


func _ready() -> void:
	var monitor : ConnectionMonitor = ConnectionMonitor.new()
	check(monitor.evaluate(100.0, 5000.0) == ConnectionMonitor.State.GOOD, "nothing is judged before the first heartbeat")
	_run(monitor, 8.0, 80.0)
	check(monitor.state == ConnectionMonitor.State.GOOD and is_zero_approx(monitor.loss), "a steady connection is good")
	_run(monitor, 6.0, 80.0, 5) #every 5th lost: 20%
	check(monitor.state == ConnectionMonitor.State.WEAK and monitor.loss > 0.15 and monitor.loss < 0.25, "lost heartbeats make it weak, and the share is right (%.2f)" % monitor.loss)
	_run(monitor, 9.0, 80.0)
	check(monitor.state == ConnectionMonitor.State.GOOD, "and it is good again once they have left the window")
	_run(monitor, 1.0, 450.0)
	check(monitor.state == ConnectionMonitor.State.GOOD, "a short spike, like the one while a match loads, shows nothing")
	_run(monitor, 2.0, 450.0)
	check(monitor.state == ConnectionMonitor.State.WEAK, "a long ping that lasts makes it weak")
	_run(monitor, 0.5, 80.0)
	check(monitor.state == ConnectionMonitor.State.WEAK, "the symbol stays a moment, so it does not flicker")
	_run(monitor, 3.0, 80.0)
	check(monitor.state == ConnectionMonitor.State.GOOD, "then goes")
	_now += 2.6
	check(monitor.evaluate(_now, 80.0) == ConnectionMonitor.State.GOOD, "the lobby's pause while a match loads is not shown")
	_now += 3.4
	check(monitor.evaluate(_now, 80.0) == ConnectionMonitor.State.LOST and monitor.silence > 5.5, "silence is lost, and counts the seconds (%.1f)" % monitor.silence)
	_number += 60
	_run(monitor, 0.3, 80.0)
	check(monitor.state == ConnectionMonitor.State.WEAK and is_zero_approx(monitor.loss), "coming back it is weak for a moment, and the gap is not counted as loss")
	_run(monitor, 9.0, 80.0)
	check(monitor.state == ConnectionMonitor.State.GOOD, "and then good")
	monitor.beat(_number - 3, _now)
	check(is_zero_approx(monitor.loss), "a late heartbeat changes nothing")
	monitor.reset()
	check(monitor.evaluate(_now + 100.0, 80.0) == ConnectionMonitor.State.GOOD, "after leaving, nothing is shown")
	var status : Node = (load("res://game/net/connection_status.tscn") as PackedScene).instantiate()
	add_child(status)
	check(not status.panel.visible, "the symbol starts hidden")
	status._show(ConnectionMonitor.State.LOST, 0.0)
	check(status.panel.visible and status.title.text == "NO SIGNAL", "it shows when the signal is lost")
	status._show(ConnectionMonitor.State.GOOD, 0.0)
	check(not status.panel.visible, "and hides when all is well")
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(_failures)


## Heartbeats ten a second for a while, losing every `lose_every`th (0: none), judged as they come.
func _run(monitor : ConnectionMonitor, seconds : float, ping : float, lose_every : int = 0) -> void:
	for i in int(seconds * 10.0):
		_now += 0.1
		_number += 1
		if lose_every == 0 or _number % lose_every != 0:
			monitor.beat(_number, _now)
		monitor.evaluate(_now, ping)


func check(ok : bool, what : String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
