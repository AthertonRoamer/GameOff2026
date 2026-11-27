extends Node

# Offline test of the text chat: who is on which channel, the names readers see, cleaning the text, the rate limiter, the lobby's relay (who it sends
# to) and the window (tabs, unread bubbles, history). Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_chat.tscn

const GUARD : Role = preload("res://game/roles/guard.tres")
const MEDIC : Role = preload("res://game/roles/medic.tres")
const INFILTRATOR : Role = preload("res://game/roles/infiltrator.tres")
const WINDOW : PackedScene = preload("res://game/chat/chat_window.tscn")
const PLAYER : PackedScene = preload("res://game/player/player.tscn")

const G := ChatRules.Channel.GUARDS
const I := ChatRules.Channel.INTRUDERS

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


## Members: 10 loyal guard, 11 loyal guard, 20 imposter, 21 imposter, 30 intruder.
func make_assigner(attackers_know_each_other : bool = false) -> RoleAssigner:
	var assigner : RoleAssigner = RoleAssigner.new()
	assigner.guard_roles = [GUARD, MEDIC]
	assigner.intruder_roles = [INFILTRATOR]
	assigner.attacking_guards_know_each_other = attackers_know_each_other
	return assigner


func make_assignment() -> Dictionary:
	return {
		"roles": {10: 0, 11: 1, 20: 0, 21: 1, 30: 2},
		"teams": {10: Team.DEFENDERS, 11: Team.DEFENDERS, 20: Team.ATTACKERS, 21: Team.ATTACKERS, 30: Team.ATTACKERS},
	}


func _ready() -> void:
	test_channels()
	test_labels()
	test_sanitize()
	test_rate_limiter()
	await test_window()
	print("RESULT: " + ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func test_channels() -> void:
	print("channels")
	var a : RoleAssigner = make_assigner()
	var s : Dictionary = make_assignment()
	check(ChatRules.channels_for(10, s, a) == [G], "a loyal guard is on GUARDS only")
	check(ChatRules.channels_for(20, s, a) == [G, I], "an imposter is on both")
	check(ChatRules.channels_for(30, s, a) == [I], "an intruder is on INTRUDERS only")
	check(ChatRules.channels_for(99, s, a).is_empty(), "a member with no role is on none")
	check(ChatRules.recipients(I, [10, 11, 20, 21, 30], s, a) == [20, 21, 30], "an INTRUDERS message goes to the attackers only")
	check(ChatRules.recipients(G, [10, 11, 20, 21, 30], s, a) == [10, 11, 20, 21], "a GUARDS message goes to every guard, imposters too")
	# a client knows only its own team and the ones it is told: the imposter's own view still puts it on both
	var own_view : Dictionary = {"roles": s["roles"], "teams": a.teams_visible_to(20, s)}
	check(ChatRules.channels_for(20, own_view, a) == [G, I], "an imposter's own view puts it on both channels")
	var guard_view : Dictionary = {"roles": s["roles"], "teams": a.teams_visible_to(10, s)}
	check(ChatRules.channels_for(10, guard_view, a) == [G], "a loyal guard's own view puts it on GUARDS only")
	check(not ChatRules.is_channel(5) and not ChatRules.is_channel("0") and ChatRules.is_channel(1), "only real channel numbers are channels")


func test_labels() -> void:
	print("names")
	var a : RoleAssigner = make_assigner(false)
	var s : Dictionary = make_assignment()
	check(ChatRules.sender_label(21, 20, I, s, a, "Ann", false) == ChatRules.UNKNOWN_ALLY, "an imposter not told about another sees Unknown ally")
	check(ChatRules.sender_label(21, 20, I, s, a, "Ann", true) == "Ann", "with the reveal export on, the name shows")
	check(ChatRules.sender_label(30, 20, I, s, a, "Ann", false) == "Ann", "the intruder (told about the imposters) sees the name")
	check(ChatRules.sender_label(20, 30, I, s, a, "Zed", false) == "Zed", "an intruder's name always shows (its role is public)")
	check(ChatRules.sender_label(20, 20, I, s, a, "Ann", false) == "Ann", "your own name shows to you")
	check(ChatRules.sender_label(10, 20, G, s, a, "Ann", false) == "Ann", "names always show on GUARDS")
	var knowing : RoleAssigner = make_assigner(true)
	check(ChatRules.sender_label(21, 20, I, s, knowing, "Ann", false) == "Ann", "imposters who know each other see names")


func test_sanitize() -> void:
	print("cleaning")
	check(ChatRules.sanitize("  hello   there  ") == "hello there", "spaces trimmed and collapsed")
	check(ChatRules.sanitize("a\nb\r\tc") == "a b c", "line breaks become spaces")
	check(ChatRules.sanitize("x" + String.chr(7) + String.chr(0x202E) + "y") == "xy", "control characters and text-reversal marks removed")
	check(ChatRules.sanitize("   \n ") == "", "only spaces is nothing")
	check(ChatRules.sanitize("a".repeat(500)).length() == ChatRules.MAX_LENGTH, "cut to the length limit")
	check(ChatRules.escape_bbcode("[color=red]hi[/color]") == "[lb]color=red]hi[lb]/color]", "tags are shown, not read")


func test_rate_limiter() -> void:
	print("rate limit")
	var r : ChatRules.RateLimiter = ChatRules.RateLimiter.new()
	var t : float = 100.0
	var ok : int = 0
	for i in 4:
		if r.check("msg %d" % i, t) == ChatRules.RateLimiter.OK:
			ok += 1
	check(ok == 4, "a burst of four goes")
	check(r.check("msg 5", t) == ChatRules.RateLimiter.TOO_FAST, "the fifth at once is too fast")
	check(r.check("msg 6", t + 1.6) == ChatRules.RateLimiter.OK, "one more after 1.5 s")
	check(r.check("MSG 6", t + 3.2) == ChatRules.RateLimiter.REPEATED, "the same text again (any case) is refused")
	check(r.check("msg 6", t + 3.3) == ChatRules.RateLimiter.MUTED, "three refusals within 10 s mute")
	check(r.check("something new", t + 20.0) == ChatRules.RateLimiter.MUTED, "still muted inside 20 s")
	check(r.check("something new", t + 24.0) == ChatRules.RateLimiter.OK, "unmuted after 20 s")


func test_window() -> void:
	print("window")
	var relay : ChatRelay = ChatRelay.new()
	add_child(relay)
	var player : Player = PLAYER.instantiate()
	add_child(player)
	var window : ChatWindow = WINDOW.instantiate()
	add_child(window)
	await get_tree().process_frame
	check(not window.visible, "hidden until bound")

	window.bind(relay, player, [G] as Array[int])
	check(window.visible and not window._header.visible, "one channel: shown, no header")
	window.bind(relay, player, [G, I] as Array[int])
	check(window._header.visible, "two channels: the header shows")
	check(window.current_channel() == G, "starts on GUARDS")

	relay.message_received.emit(I, "Zed", "[b]psst[/b]", false)
	relay.message_received.emit(I, "Zed", "again", false)
	check(window.unread(I) == 2 and window._bubbles[I].visible, "messages on the other channel count in its bubble")
	check(not window._bubbles[G].visible, "no bubble on the channel being read")
	check(window._log.get_parsed_text().strip_edges() == "", "the GUARDS log does not show intruder messages")

	window.switch_to(I)
	check(window.unread(I) == 0 and not window._bubbles[I].visible, "switching clears the bubble")
	check(window._log.get_parsed_text().contains("[b]psst[/b]"), "a typed tag shows as text")
	check(window._tabs[I].get_theme_font_size("font_size") > window._tabs[G].get_theme_font_size("font_size"), "the active tab is the big one")

	window.bind(relay, player, [G] as Array[int])
	check(window.current_channel() == G and not window._header.visible, "losing a channel moves to the one left")

	relay.message_received.emit(I, "Zed", "secret", false)
	check(window.unread(I) == 0 and not window._log.get_parsed_text().contains("secret"), "a message on a channel the window is not on is ignored")

	for i in window.history_lines + 20:
		relay.message_received.emit(G, "Bob", "line %d" % i, false)
	check(window._history[G].size() == window.history_lines, "history is capped")

	window.start_typing()
	await get_tree().process_frame
	check(window.is_typing() and player.input.typing, "typing stops the player's input")
	window.stop_typing()
	check(not window.is_typing() and not player.input.typing, "stopping gives it back")

	player.health = 0.0
	player.health_changed.emit(0.0)
	check(not window._line.editable, "dead players can't type")
	window.start_typing()
	await get_tree().process_frame
	check(not window.is_typing(), "Enter does nothing for a dead player")

	var chime : AudioStreamWAV = ChatWindow.make_chime()
	check(chime.data.size() > 10000, "the chime is made")
