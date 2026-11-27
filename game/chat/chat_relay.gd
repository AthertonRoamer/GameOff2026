class_name ChatRelay
extends Node

##The text chat's network side. A client never sends a message to other clients: it sends it to the lobby (`submit`), and the lobby checks it
##(ChatRules: the sender is on that channel, alive, not sending too fast, the text cleaned) and sends it on to ONLY the members on that channel, each
##with the sender's name as that member may see it. So a peer is never sent a message it may not read, and nobody can pretend to be someone else.
##The window (ChatWindow) listens to message_received and notice.

signal message_received(channel : int, sender : String, text : String, is_own : bool)
signal notice(text : String) #the lobby refused a message, or something to tell this player only
signal ping_received(channel : int, sender : String, at : Vector2, label : String, is_own : bool)
signal speech_received(member_id : int, text : String) ## a player said a message aloud near this peer (SpeechBubbles shows and voices it)

@export var speech_bubbles_enabled : bool = true ## a message is also said aloud: its words over the sender's head and a muffled voice, for everyone near enough to hear, whatever their channel. Off: chat is only the window
@export_range(0.0, 10.0, 0.5, "suffix:m") var speech_send_margin_m : float = 2.0 ## lobby: the words go to peers this much further than the voice carries (each peer then decides by what it hears; past that it is never sent them)
@export var reveal_unknown_attackers : bool = false ## on: imposters see each other's names on the intruder channel even when they are not told about each other (Game.attacking_guards_know_each_other off). Off: such a sender shows as "Unknown ally"
@export var dead_can_send : bool = false ## dead players may send. Off: they can still read

var game : Game #set by Game
var _limiters : Dictionary = {} #lobby: member id -> ChatRules.RateLimiter
var _ping_limiters : Dictionary = {} #lobby: pings have their own allowance
var _pings_sent : int = 0 #lobby: makes every ping a new "message" to the limiter (the same place may be pinged again)


##Any peer: send a message from this peer's player. The lobby decides whether it goes anywhere.
func submit(channel : int, text : String) -> void:
	text = text.left(ChatRules.MAX_LENGTH * 2) #(the lobby cleans it properly; this only keeps a huge paste off the wire)
	if multiplayer.is_server():
		_receive_submission(multiplayer.get_unique_id(), channel, text)
	else:
		_submit.rpc_id(1, channel, text)


##Any peer: place a ping at a world position, with a name or none, on a channel. The lobby checks it as it does a message, and only that channel gets it.
func submit_ping(channel : int, at : Vector2, label : String) -> void:
	label = label.left(ChatRules.MAX_PING_LABEL * 2)
	if multiplayer.is_server():
		_receive_ping_submission(multiplayer.get_unique_id(), channel, at, label)
	else:
		_submit_ping.rpc_id(1, channel, at, label)


##Lobby only: whether chat is on in this match at all (not in a deathmatch).
func is_enabled() -> bool:
	return game != null and not game.settings.is_deathmatch()


@rpc("any_peer", "call_remote", "reliable")
func _submit(channel : Variant, text : Variant) -> void:
	_receive_submission(multiplayer.get_remote_sender_id(), channel, text)


func _receive_submission(sender : int, channel : Variant, text : Variant) -> void:
	if typeof(text) != TYPE_STRING or not _may_send(sender, channel):
		return
	var clean : String = ChatRules.sanitize(text)
	if clean == "":
		return
	if not _allowed_now(_limiters, sender, clean):
		return
	var sender_name : String = _name_of(sender)
	for id : int in _recipients(channel):
		var label : String = _label_for(id, sender, channel, sender_name)
		if id == multiplayer.get_unique_id():
			_deliver(channel, label, clean, id == sender)
		else:
			_deliver.rpc_id(id, channel, label, clean, id == sender)
	_say_aloud(sender, clean)


##Lobby: a message is said aloud as well, to every peer near enough to hear it, whatever channel they are on (so a message to the intruders said near a guard
##gives the speaker away). Peers further than the voice carries are never sent the words. A dead peer, who watches from anywhere, is sent them all.
func _say_aloud(sender : int, text : String) -> void:
	if not speech_bubbles_enabled or not game.started:
		return
	var speaker : Player = game.spawner.players.get(sender)
	if not is_instance_valid(speaker) or not speaker.is_alive():
		return
	var voice : SoundDef = game.level.sound.chat_voice
	var reach_px : float = ((voice.range_m if voice != null else 9.0) + speech_send_margin_m) * Acoustics.PX_PER_METRE
	for member in game.spawner.lobby.members:
		var id : int = member.id
		var listener : Player = game.spawner.players.get(id)
		if not is_instance_valid(listener):
			continue
		if listener.is_alive() and listener.global_position.distance_to(speaker.global_position) > reach_px:
			continue
		if id == multiplayer.get_unique_id():
			_speak(sender, text)
		else:
			_speak.rpc_id(id, sender, text)


@rpc("authority", "call_remote", "reliable")
func _speak(member_id : int, text : String) -> void:
	if speech_bubbles_enabled:
		speech_received.emit(member_id, text)


@rpc("any_peer", "call_remote", "reliable")
func _submit_ping(channel : Variant, at : Variant, label : Variant) -> void:
	_receive_ping_submission(multiplayer.get_remote_sender_id(), channel, at, label)


func _receive_ping_submission(sender : int, channel : Variant, at : Variant, label : Variant) -> void:
	if typeof(at) != TYPE_VECTOR2 or not (at as Vector2).is_finite() or typeof(label) != TYPE_STRING or not _may_send(sender, channel):
		return
	_pings_sent += 1
	if not _allowed_now(_ping_limiters, sender, str(_pings_sent)):
		return
	var clean : String = ChatRules.sanitize(label).left(ChatRules.MAX_PING_LABEL)
	var sender_name : String = _name_of(sender)
	for id : int in _recipients(channel):
		var who : String = _label_for(id, sender, channel, sender_name)
		if id == multiplayer.get_unique_id():
			_deliver_ping(channel, who, at, clean, id == sender)
		else:
			_deliver_ping.rpc_id(id, channel, who, at, clean, id == sender)


@rpc("authority", "call_remote", "reliable")
func _deliver_ping(channel : int, sender : String, at : Vector2, label : String, is_own : bool) -> void:
	ping_received.emit(channel, sender, at, label, is_own)


##Lobby: whether this member may send anything on this channel now. Tells a dead player why not.
func _may_send(sender : int, channel : Variant) -> bool:
	if not multiplayer.is_server() or game == null or game.spawner.lobby == null:
		return false
	if not game.spawner.lobby.has_member_with_id(sender) or not ChatRules.is_channel(channel) or not is_enabled():
		return false #not a member, or not something this game sends: ignored without an answer
	if not ChatRules.is_on(sender, channel, game.assignment, game.role_assigner):
		return false #a channel this player is not on (a modified client): ignored
	var player : Player = game.spawner.players.get(sender)
	if not dead_can_send and is_instance_valid(player) and not player.is_alive():
		_tell(sender, "Dead players can't send messages.")
		return false
	return true


func _recipients(channel : int) -> Array[int]:
	var member_ids : Array = []
	for member in game.spawner.lobby.members:
		member_ids.append(member.id)
	return ChatRules.recipients(channel, member_ids, game.assignment, game.role_assigner)


func _label_for(reader : int, sender : int, channel : int, sender_name : String) -> String:
	return ChatRules.sender_label(reader, sender, channel, game.assignment, game.role_assigner, sender_name, reveal_unknown_attackers)


##Lobby: the rate limit. Tells the sender when it says no.
func _allowed_now(limiters : Dictionary, sender : int, text : String) -> bool:
	var now : float = Time.get_ticks_msec() / 1000.0
	var limiter : ChatRules.RateLimiter = limiters.get(sender)
	if limiter == null:
		limiter = ChatRules.RateLimiter.new()
		limiters[sender] = limiter
	match limiter.check(text, now):
		ChatRules.RateLimiter.TOO_FAST:
			_tell(sender, "Slow down: you're sending too fast.")
			return false
		ChatRules.RateLimiter.REPEATED:
			_tell(sender, "You just sent that.")
			return false
		ChatRules.RateLimiter.MUTED:
			_tell(sender, "Muted for spamming: %d s left." % ceili(limiter.muted_for(now)))
			return false
	return true


@rpc("authority", "call_remote", "reliable")
func _deliver(channel : int, sender : String, text : String, is_own : bool) -> void:
	message_received.emit(channel, sender, text, is_own)


@rpc("authority", "call_remote", "reliable")
func _notice(text : String) -> void:
	notice.emit(text)


func _tell(member_id : int, text : String) -> void:
	if member_id == multiplayer.get_unique_id():
		notice.emit(text)
	else:
		_notice.rpc_id(member_id, text)


func _name_of(member_id : int) -> String:
	for member in game.spawner.lobby.members:
		if member.id == member_id:
			return ChatRules.sanitize(member.name).left(24)
	return "Player %d" % member_id


func _on_member_left(member : LobbyMember) -> void:
	_limiters.erase(member.id)
	_ping_limiters.erase(member.id)
