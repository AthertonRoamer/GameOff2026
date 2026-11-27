class_name ChatRelay
extends Node

##The text chat's network side. A client never sends a message to other clients: it sends it to the lobby (`submit`), and the lobby checks it
##(ChatRules: the sender is on that channel, alive, not sending too fast, the text cleaned) and sends it on to ONLY the members on that channel, each
##with the sender's name as that member may see it. So a peer is never sent a message it may not read, and nobody can pretend to be someone else.
##The window (ChatWindow) listens to message_received and notice.

signal message_received(channel : int, sender : String, text : String, is_own : bool)
signal notice(text : String) #the lobby refused a message, or something to tell this player only

@export var reveal_unknown_attackers : bool = false ## on: imposters see each other's names on the intruder channel even when they are not told about each other (Game.attacking_guards_know_each_other off). Off: such a sender shows as "Unknown ally"
@export var dead_can_send : bool = false ## dead players may send. Off: they can still read

var game : Game #set by Game
var _limiters : Dictionary = {} #lobby: member id -> ChatRules.RateLimiter


##Any peer: send a message from this peer's player. The lobby decides whether it goes anywhere.
func submit(channel : int, text : String) -> void:
	text = text.left(ChatRules.MAX_LENGTH * 2) #(the lobby cleans it properly; this only keeps a huge paste off the wire)
	if multiplayer.is_server():
		_receive_submission(multiplayer.get_unique_id(), channel, text)
	else:
		_submit.rpc_id(1, channel, text)


##Lobby only: whether chat is on in this match at all (not in a deathmatch).
func is_enabled() -> bool:
	return game != null and not game.settings.is_deathmatch()


@rpc("any_peer", "call_remote", "reliable")
func _submit(channel : Variant, text : Variant) -> void:
	_receive_submission(multiplayer.get_remote_sender_id(), channel, text)


func _receive_submission(sender : int, channel : Variant, text : Variant) -> void:
	if not multiplayer.is_server() or game == null or game.spawner.lobby == null:
		return
	var lobby : Lobby = game.spawner.lobby
	if not lobby.has_member_with_id(sender) or not ChatRules.is_channel(channel) or typeof(text) != TYPE_STRING or not is_enabled():
		return #not a member, or not a message this game sends: ignored without an answer
	var assignment : Dictionary = game.assignment
	if not ChatRules.is_on(sender, channel, assignment, game.role_assigner):
		return #a channel this player is not on (a modified client): ignored
	var player : Player = game.spawner.players.get(sender)
	if not dead_can_send and is_instance_valid(player) and not player.is_alive():
		_tell(sender, "Dead players can't send messages.")
		return
	var clean : String = ChatRules.sanitize(text)
	if clean == "":
		return
	var now : float = Time.get_ticks_msec() / 1000.0
	var limiter : ChatRules.RateLimiter = _limiters.get(sender)
	if limiter == null:
		limiter = ChatRules.RateLimiter.new()
		_limiters[sender] = limiter
	match limiter.check(clean, now):
		ChatRules.RateLimiter.TOO_FAST:
			_tell(sender, "Slow down: you're sending too fast.")
			return
		ChatRules.RateLimiter.REPEATED:
			_tell(sender, "You just sent that.")
			return
		ChatRules.RateLimiter.MUTED:
			_tell(sender, "Muted for spamming: %d s left." % ceili(limiter.muted_for(now)))
			return
	var sender_name : String = _name_of(sender)
	var member_ids : Array = []
	for member in lobby.members:
		member_ids.append(member.id)
	for id : int in ChatRules.recipients(channel, member_ids, assignment, game.role_assigner):
		var label : String = ChatRules.sender_label(id, sender, channel, assignment, game.role_assigner, sender_name, reveal_unknown_attackers)
		if id == multiplayer.get_unique_id():
			_deliver(channel, label, clean, id == sender)
		else:
			_deliver.rpc_id(id, channel, label, clean, id == sender)


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
