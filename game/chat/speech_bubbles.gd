class_name SpeechBubbles
extends Control

##Chat messages said aloud: the words in a bubble over the speaker's head while a muffled voice (SoundSystem.chat_voice: a "wah" per letter, the words
##never heard) plays from where they stand, then the bubble goes. You see the words exactly while you hear the voice: through walls, in the dark, and held on
##the screen's edge when the speaker is off it, but only as far as the voice carries (the voice's range_m), which is kept short. Part of the HUD, so walls and
##darkness never cover it. The lobby sends the words only to peers near enough (ChatRelay.speech_received), whatever their channel.
##Switch the whole thing off with ChatRelay.speech_bubbles_enabled.

@export_range(0.0, 80.0, 1.0, "suffix:px") var head_offset : float = 68.0 ## how far above the player's middle the bubble's bottom sits, in world pixels (just over their name, NameDisplay)
@export_range(0.02, 0.2, 0.005, "suffix:s") var letter_seconds : float = 0.065 ## between two letters' sounds
@export_range(0.01, 0.2, 0.005, "suffix:s") var fastest_letter_seconds : float = 0.035 ## a long message speeds up to fit talk_limit_seconds, but no faster than this
@export_range(1.0, 20.0, 0.5, "suffix:s") var talk_limit_seconds : float = 7.0
@export_range(0.0, 0.5, 0.01, "suffix:s") var pause_seconds : float = 0.12 ## extra quiet after . , ! ? and the like
@export_range(0.0, 5.0, 0.1, "suffix:s") var linger_seconds : float = 1.4 ## the words stay this long after the voice stops
@export_range(60.0, 600.0, 1.0, "suffix:px") var max_width : float = 240.0 ## longer messages wrap
@export_range(8, 32) var font_size : int = 14
@export var edge_margin : float = 28.0 ## how far in from the screen's edge an off screen speaker's bubble is held
@export_range(0.5, 20.0, 0.5) var fade_per_second : float = 8.0

const RECHECK_SECONDS : float = 0.2 #while the words linger with no voice to say whether they are heard, it is checked this often
const PAUSES : String = ".,!?;:"

var sound : SoundSystem
var player_of : Callable = Callable() ## (member id) -> Player, or null
var local_player : Callable = Callable() ## () -> this peer's own Player, or null

var _bubbles : Array[Dictionary] = [] #{player, text, index, clock, next, step, linger, heard, recheck, alpha, panel}
var _style : StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(Palette.PANEL, 0.88)
	_style.border_color = Palette.PANEL_LINE
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(4)
	_style.content_margin_left = 7.0
	_style.content_margin_right = 7.0
	_style.content_margin_top = 3.0
	_style.content_margin_bottom = 4.0


func listen_to(relay : ChatRelay) -> void:
	if not relay.speech_received.is_connected(say):
		relay.speech_received.connect(say)


##A player says this aloud now. A new message from the same player replaces the one they were saying.
func say(member_id : int, text : String) -> void:
	if sound == null or not player_of.is_valid() or text.strip_edges() == "":
		return
	var player : Variant = player_of.call(member_id)
	if not is_instance_valid(player) or not (player as Player).is_alive():
		return
	for bubble : Dictionary in _bubbles:
		if bubble["player"] == player:
			_drop(bubble)
	_bubbles = _bubbles.filter(func(b : Dictionary) -> bool: return b["player"] != player)
	var letters : int = 0
	for i in text.length():
		if _is_voiced(text[i]):
			letters += 1
	var bubble : Dictionary = {
		"player": player, "text": text, "index": 0, "clock": 0.0, "next": 0.0,
		"step": clampf(talk_limit_seconds / maxf(letters, 1), fastest_letter_seconds, letter_seconds),
		"linger": linger_seconds, "recheck": 0.0, "alpha": 0.0, "panel": _make_panel(text),
		"heard": sound.audibility(sound.chat_voice, (player as Node2D).global_position, _is_own(player)) > 0.0,
	}
	_bubbles.append(bubble)
	set_process(true)


func _process(delta : float) -> void:
	var to_screen : Transform2D = get_viewport().get_canvas_transform()
	var inner : Rect2 = Rect2(Vector2.ZERO, size).grow(-edge_margin)
	for bubble : Dictionary in _bubbles:
		var player : Variant = bubble["player"]
		if not is_instance_valid(player) or not (player as Player).is_alive():
			bubble["linger"] = 0.0 #a speaker who died or left stops at once
			bubble["heard"] = false
			bubble["index"] = (bubble["text"] as String).length()
		else:
			_talk(bubble, delta)
		bubble["alpha"] = move_toward(bubble["alpha"], 1.0 if bubble["heard"] else 0.0, fade_per_second * delta)
		var panel : PanelContainer = bubble["panel"]
		panel.modulate.a = bubble["alpha"]
		panel.visible = bubble["alpha"] > 0.0
		if panel.visible and is_instance_valid(player):
			var head : Vector2 = to_screen * _speaker_at(player)
			var panel_size : Vector2 = panel.get_combined_minimum_size()
			var at : Vector2 = head - Vector2(panel_size.x / 2.0, panel_size.y)
			panel.position = at.clamp(inner.position, (inner.end - panel_size).max(inner.position))
			panel.size = panel_size
	for bubble : Dictionary in _bubbles:
		if _is_done(bubble):
			_drop(bubble)
	_bubbles = _bubbles.filter(func(b : Dictionary) -> bool: return not _is_done(b))
	if _bubbles.is_empty():
		set_process(false)


##Says the letters that are due (one syllable each; spaces and punctuation are quiet), then lets the words linger. Whether the bubble shows follows the voice.
func _talk(bubble : Dictionary, delta : float) -> void:
	var text : String = bubble["text"]
	var player : Player = bubble["player"]
	bubble["clock"] += delta
	if bubble["index"] < text.length():
		while bubble["index"] < text.length() and bubble["clock"] >= bubble["next"]:
			var letter : String = text[bubble["index"]]
			bubble["index"] += 1
			bubble["next"] += bubble["step"]
			if _is_voiced(letter):
				bubble["heard"] = sound.play(sound.chat_voice, (player as Node2D).global_position, _is_own(player), false) > 0.0
			elif PAUSES.contains(letter):
				bubble["next"] += pause_seconds
		return
	bubble["linger"] -= delta
	if bubble["linger"] <= 0.0: #said and read: it fades out
		bubble["heard"] = false
		return
	bubble["recheck"] -= delta
	if bubble["recheck"] <= 0.0: #(the listener or the speaker may walk out of earshot while the words linger)
		bubble["recheck"] = RECHECK_SECONDS
		bubble["heard"] = sound.audibility(sound.chat_voice, (player as Node2D).global_position, _is_own(player)) > 0.0


func _is_done(bubble : Dictionary) -> bool:
	return bubble["index"] >= (bubble["text"] as String).length() and bubble["linger"] <= 0.0 and bubble["alpha"] <= 0.0


func _drop(bubble : Dictionary) -> void:
	var panel : Variant = bubble["panel"]
	if is_instance_valid(panel):
		(panel as Node).queue_free()


func _make_panel(text : String) -> PanelContainer:
	var panel : PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style)
	panel.modulate.a = 0.0
	var label : Label = Label.new()
	label.text = text #(a Label never reads BBCode, so the text shows as typed)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var width : float = label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if width > max_width:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = max_width
	panel.add_child(label)
	add_child(panel)
	return panel


func _speaker_at(player : Player) -> Vector2:
	return player.global_position + Vector2(0.0, -head_offset)


func _is_own(player : Player) -> bool:
	return local_player.is_valid() and local_player.call() == player


static func _is_voiced(letter : String) -> bool:
	var code : int = letter.unicode_at(0)
	return letter != " " and not PAUSES.contains(letter) and code > 32
