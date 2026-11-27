class_name ConnectionMonitor
extends RefCounted

## Works out how good this peer's connection to the lobby is, from the lobby's heartbeats (ConnectionStatus sends them, numbered, unreliably) and the ping.
## Plain numbers in and out, so it can be tested without a network.

enum State { GOOD, WEAK, LOST }

var lost_after_seconds : float = 3.5 ## this long without a heartbeat: nothing is getting through (loading a match stops the lobby's frames for up to 2.5 s)
var weak_loss : float = 0.08 ## this share of the recent heartbeats missing is a weak connection (0 to 1)
var weak_ping_ms : float = 300.0 ## so is a round trip this long
var weak_after_seconds : float = 2.0 ## a problem has to last this long to be shown: the moment a match loads looks bad on any connection
var pause_seconds : float = 1.0 ## after a gap this long the loss is measured afresh: what went missing around a pause is not the connection's usual loss
var window_seconds : float = 5.0 ## the loss is measured over the heartbeats of the last this many seconds
var linger_seconds : float = 2.0 ## a weak connection is shown at least this long, so the symbol does not flicker

var state : State = State.GOOD
var loss : float = 0.0 ## the share of the recent heartbeats that never arrived, 0 to 1
var silence : float = 0.0 ## seconds since the last heartbeat

var _beats : Array[Vector2] = [] #(when it arrived, its number), the ones inside the window
var _last_beat : float = -1.0
var _weak_until : float = 0.0
var _bad_since : float = -1.0


func reset() -> void:
	_beats.clear()
	_last_beat = -1.0
	_weak_until = 0.0
	_bad_since = -1.0
	state = State.GOOD
	loss = 0.0
	silence = 0.0


## A heartbeat arrived. `number` goes up by one for each the lobby sends, so a gap is a lost one.
func beat(number : int, now : float) -> void:
	if not _beats.is_empty() and number <= int(_beats[-1].y): #late (overtaken by a newer one): it counts as lost
		return
	if _last_beat >= 0.0 and now - _last_beat >= pause_seconds:
		_beats.clear()
	_beats.append(Vector2(now, number))
	_last_beat = now


## The state now. Nothing is judged before the first heartbeat.
func evaluate(now : float, ping_ms : float) -> State:
	if _last_beat < 0.0:
		return State.GOOD
	silence = now - _last_beat
	while _beats.size() > 1 and now - _beats[0].x > window_seconds:
		_beats.remove_at(0)
	var expected : int = int(_beats[-1].y - _beats[0].y) + 1
	loss = 1.0 - float(_beats.size()) / float(expected) if expected >= 10 else 0.0 #(too few to say)
	if silence >= lost_after_seconds:
		state = State.LOST
		_bad_since = -1.0
		_weak_until = now + linger_seconds
	else:
		if loss >= weak_loss or ping_ms >= weak_ping_ms:
			if _bad_since < 0.0:
				_bad_since = now
			if now - _bad_since >= weak_after_seconds:
				_weak_until = now + linger_seconds
		else:
			_bad_since = -1.0
		state = State.WEAK if now < _weak_until else State.GOOD
	return state
