extends Node

# Offline test of chat said aloud (SpeechBubbles): a syllable per letter and none for spaces or punctuation, the words shown only while the voice is audible,
# gone after it stops, a new message replacing the last, nothing from the dead, and ChatRelay.speech_bubbles_enabled switching it off. The sound system is a
# stand-in that counts what it is asked to play and says whether it is audible. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_speech.tscn

const PLAYER : PackedScene = preload("res://game/player/player.tscn")
const VOICE : SoundDef = preload("res://game/audio/definitions/chat_voice.tres")

var failures : int = 0


class FakeSound extends SoundSystem:
	var audible : bool = true
	var plays : int = 0
	func _ready() -> void:
		chat_voice = VOICE
	func play(_def : SoundDef, _at : Vector2, _own : bool = false, _cue : bool = true) -> float:
		plays += 1
		return 0.5 if audible else 0.0
	func audibility(_def : SoundDef, _at : Vector2, _own : bool = false) -> float:
		return 0.5 if audible else 0.0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	var sound : FakeSound = FakeSound.new()
	add_child(sound)
	var speaker : Player = PLAYER.instantiate()
	add_child(speaker)
	var bubbles : SpeechBubbles = SpeechBubbles.new()
	bubbles.size = Vector2(800, 600)
	add_child(bubbles)
	bubbles.sound = sound
	bubbles.player_of = func(id : int) -> Player: return speaker if id == 7 else null
	bubbles.local_player = func() -> Player: return null
	var relay : ChatRelay = ChatRelay.new()
	add_child(relay)
	bubbles.listen_to(relay)
	await get_tree().process_frame

	relay._speak(7, "hi, you")
	check(_count(bubbles) == 1, "a message said aloud makes a bubble")
	_run(bubbles, 3.0)
	check(sound.plays == 5, "one syllable per letter, none for the space or the comma (%d)" % sound.plays)
	_run(bubbles, 3.0)
	check(_count(bubbles) == 0, "the bubble goes once the voice has stopped and the words have lingered")

	sound.plays = 0
	relay._speak(7, "first message")
	_run(bubbles, 0.2)
	relay._speak(7, "second")
	check(_count(bubbles) == 1, "a new message from the same player replaces the one being said")
	check(_shown_text(bubbles) == "second", "and shows the new words")
	_run(bubbles, 6.0)

	sound.audible = false
	relay._speak(7, "out of earshot")
	_run(bubbles, 0.5)
	check(not _any_visible(bubbles), "words that are not audible are not shown")
	_run(bubbles, 6.0)
	check(_count(bubbles) == 0, "and their bubble still goes away")
	sound.audible = true

	relay._speak(99, "nobody")
	check(_count(bubbles) == 0, "a member with no player says nothing")

	relay.speech_bubbles_enabled = false
	relay._speak(7, "switched off")
	check(_count(bubbles) == 0, "speech_bubbles_enabled off: nothing is said aloud")
	relay.speech_bubbles_enabled = true

	speaker.take_damage(1000.0)
	await get_tree().process_frame
	relay._speak(7, "from the grave")
	check(_count(bubbles) == 0, "the dead say nothing aloud")

	print("RESULT: " + ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)


##Runs the bubbles' clock on by this much, in small steps.
func _run(bubbles : SpeechBubbles, seconds : float) -> void:
	bubbles.set_process(false)
	var step : float = 1.0 / 60.0
	var t : float = 0.0
	while t < seconds:
		bubbles._process(step)
		t += step


func _count(bubbles : SpeechBubbles) -> int:
	return bubbles._bubbles.size()


func _any_visible(bubbles : SpeechBubbles) -> bool:
	return bubbles._bubbles.any(func(b : Dictionary) -> bool: return (b["panel"] as Control).visible)


func _shown_text(bubbles : SpeechBubbles) -> String:
	return ((bubbles._bubbles[0]["panel"] as PanelContainer).get_child(0) as Label).text if not bubbles._bubbles.is_empty() else ""
