class_name ChatRules
extends RefCounted

##Who may read and write which chat channel, what a message may contain, and how fast a player may send. Pure logic, no networking: ChatRelay
##(on the lobby) asks it before passing a message on, and ChatWindow asks it which tabs to show.
##
##Two channels. GUARDS: every player with a guard role, loyal or secretly attacking. INTRUDERS: every attacker, intruders and the secretly attacking
##guards (the imposters). So an imposter is on both, a loyal guard only on GUARDS and an intruder only on INTRUDERS.
##An "assignment" is RoleAssigner's: {"roles": {member_id: role_index}, "teams": {member_id: Team}}. A client passes the roles and the teams it knows.

enum Channel { GUARDS, INTRUDERS }

const MAX_LENGTH : int = 200 ## characters in one message, after cleaning
const UNKNOWN_ALLY : String = "Unknown ally" ## an attacker's name on INTRUDERS, to a reader not allowed to know they are one


static func channel_name(channel : int) -> String:
	return "Intruders" if channel == Channel.INTRUDERS else "Guards"


static func is_channel(value : Variant) -> bool:
	return typeof(value) == TYPE_INT and (value == Channel.GUARDS or value == Channel.INTRUDERS)


##The channels a member is on. None for a member with no role (not in the match).
static func channels_for(member_id : int, assignment : Dictionary, role_assigner : RoleAssigner) -> Array[int]:
	var channels : Array[int] = []
	var role : Role = role_assigner.role_at(assignment.get("roles", {}).get(member_id, -1))
	if role == null:
		return channels
	if not role.is_intruder():
		channels.append(Channel.GUARDS)
	if role.is_intruder() or assignment.get("teams", {}).get(member_id, Team.UNKNOWN) == Team.ATTACKERS:
		channels.append(Channel.INTRUDERS)
	return channels


static func is_on(member_id : int, channel : int, assignment : Dictionary, role_assigner : RoleAssigner) -> bool:
	return channels_for(member_id, assignment, role_assigner).has(channel)


##The members that receive a message on a channel: everyone on it.
static func recipients(channel : int, member_ids : Array, assignment : Dictionary, role_assigner : RoleAssigner) -> Array[int]:
	var ids : Array[int] = []
	for id : int in member_ids:
		if is_on(id, channel, assignment, role_assigner):
			ids.append(id)
	return ids


##The name a reader sees on a message. On GUARDS every sender's role is public, so it is their name. On INTRUDERS a reader who may not know that the
##sender is an attacker (RoleAssigner.teams_visible_to: two imposters who are not told about each other) sees UNKNOWN_ALLY, unless reveal_unknown is on.
static func sender_label(reader_id : int, sender_id : int, channel : int, assignment : Dictionary, role_assigner : RoleAssigner, sender_name : String, reveal_unknown : bool) -> String:
	if channel == Channel.INTRUDERS and reader_id != sender_id and not reveal_unknown:
		if not role_assigner.teams_visible_to(reader_id, assignment).has(sender_id):
			return UNKNOWN_ALLY
	return sender_name


##A message as it may be passed on: no control characters or line breaks, runs of spaces made one, trimmed, at most MAX_LENGTH. Empty: nothing to send.
static func sanitize(text : String) -> String:
	var out : String = ""
	var last_space : bool = true #(drops the leading spaces)
	for i in text.length():
		var code : int = text.unicode_at(i)
		var is_space : bool = code == 32 or code == 9 or code == 10 or code == 13
		if is_space:
			if not last_space:
				out += " "
			last_space = true
		elif code < 32 or code == 127 or (code >= 0x80 and code < 0xA0) or code == 0x200B or code == 0x202E or code == 0x202D:
			continue #control characters, zero width space, and the right-to-left overrides that turn text around
		else:
			out += String.chr(code)
			last_space = false
	return out.strip_edges().left(MAX_LENGTH).strip_edges()


##BBCode-safe: the text is shown as typed, never read as tags.
static func escape_bbcode(text : String) -> String:
	return text.replace("[", "[lb]")


##One player's sending allowance, kept by the lobby. A token bucket (a burst of `burst`, then one message every `refill_seconds`), no repeat of the
##same message within `repeat_seconds`, and a player who is refused `strikes_to_mute` times within `strike_window_seconds` is muted for `mute_seconds`.
##Times are in seconds and passed in (the lobby passes Time.get_ticks_msec() / 1000.0), so tests can run the clock.
class RateLimiter extends RefCounted:
	enum { OK, TOO_FAST, REPEATED, MUTED }

	var burst : int = 4
	var refill_seconds : float = 1.5
	var repeat_seconds : float = 10.0
	var strikes_to_mute : int = 3
	var strike_window_seconds : float = 10.0
	var mute_seconds : float = 20.0

	var _tokens : float = -1.0 #-1: full, set on first use
	var _last_refill : float = 0.0
	var _last_text : String = ""
	var _last_text_at : float = -INF
	var _strikes : Array[float] = []
	var _muted_until : float = -INF

	##Whether this message may go now. A refusal counts as a strike, and enough strikes mute.
	func check(text : String, now : float) -> int:
		if now < _muted_until:
			return MUTED
		_refill(now)
		var verdict : int = OK
		if text.to_lower() == _last_text and now - _last_text_at < repeat_seconds:
			verdict = REPEATED
		elif _tokens < 1.0:
			verdict = TOO_FAST
		if verdict != OK:
			_strike(now)
			return MUTED if now < _muted_until else verdict
		_tokens -= 1.0
		_last_text = text.to_lower()
		_last_text_at = now
		return OK

	func muted_for(now : float) -> float:
		return maxf(_muted_until - now, 0.0)

	func _refill(now : float) -> void:
		if _tokens < 0.0:
			_tokens = burst
			_last_refill = now
			return
		_tokens = minf(burst, _tokens + (now - _last_refill) / refill_seconds)
		_last_refill = now

	func _strike(now : float) -> void:
		_strikes.append(now)
		while not _strikes.is_empty() and now - _strikes[0] > strike_window_seconds:
			_strikes.pop_front()
		if _strikes.size() >= strikes_to_mute:
			_muted_until = now + mute_seconds
			_strikes.clear()
