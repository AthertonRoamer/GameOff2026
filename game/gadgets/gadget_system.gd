class_name GadgetSystem
extends Node2D

##What the gadgets do once they are out of the inventory, and the two that work while carried.
##  smoke bombs   thrown (a PickupControl "throw" change, so on every peer on the same tick): a SmokeCloud where it lands, which hides what is behind it
##  tripwires     placed (dropped or clicked down) by a player, a wire is strung across the way they faced (TripwireItem). The lobby watches every living player:
##                one who crosses a wire that is not theirs trips it, and only its owner is told: a ping on their maps and a line in their chat, saying where, not who
##  coms hackers  placed by a player, one listens round it (ComsHackerItem). The lobby hands every chat message to intercept(): a message said within
##                listen_radius_m of a hacker, on a channel its owner is not on, is passed to the owner as well. A shot breaks it (PickupControl.destroy)
##  night vision  carried: N switches it on and off (NightVision). Local only: nobody else is told
##  radar         carried: a pulse every few seconds shows the players moving round you (RadarDisplay). Local only
##Found ones (put out at the start) and ones fallen from a dead player have no owner: a tripwire or hacker does nothing until someone picks it up and puts it down.

const GROUP : StringName = &"gadgets"

@export_range(0.5, 10.0, 0.5, "suffix:s") var tripwire_cooldown_seconds : float = 3.0 ## a wire that was just tripped says nothing again for this long
@export_range(2.0, 40.0, 0.5, "suffix:m") var listen_radius_m : float = 12.0 ## how far round it a coms hacker hears

var facility : FacilityMap
var players : Callable = Callable() ## () -> Array of every Player
var player_lookup : Callable = Callable() ## (member id) -> Player or null
var local_player : Callable = Callable() ## () -> this peer's Player or null
var chat : ChatRelay
var map_intel : MapIntel
var sight : PlayerSight

var night_vision : NightVision
var radar : RadarDisplay
var trips_sent : int = 0 #lobby: how many tripwire alarms it has sent (for tests)
var intercepts_sent : int = 0 #lobby: how many intercepted messages it has passed on

var _tripwires : Dictionary = {} #pickup id -> {"pickup", "a", "b" (world), "owner", "quiet_until" (msec)}
var _hackers : Dictionary = {} #pickup id -> Pickup
var _last_positions : Dictionary = {} #lobby: player -> where they were last physics frame
var _active : bool = true


func _ready() -> void:
	add_to_group(GROUP)
	night_vision = NightVision.new()
	night_vision.name = "NightVision"
	night_vision.gadgets = self
	add_child(night_vision)
	var radar_layer : CanvasLayer = CanvasLayer.new() #(its own layer, over the darkness, following the world)
	radar_layer.name = "RadarLayer"
	radar_layer.follow_viewport_enabled = true
	radar_layer.layer = 2
	add_child(radar_layer)
	radar = RadarDisplay.new()
	radar.name = "Radar"
	radar.gadgets = self
	radar_layer.add_child(radar)


func quiesce() -> void:
	_active = false


## The local player, alive, or null.
func me() -> Player:
	var player : Variant = local_player.call() if local_player.is_valid() else null
	return player if is_instance_valid(player) and (player as Player).is_alive() else null


## Whether this player carries an item of this script.
static func carries(player : Player, script : Script) -> bool:
	if not is_instance_valid(player):
		return false
	for item : Item in player.inventory.slots:
		if item != null and item.get_script() == script:
			return true
	return false


# ------------------------------------------------------------------ smoke
func add_smoke(at : Vector2, radius_px : float = 120.0, hold_seconds : float = 14.0) -> SmokeCloud:
	var cloud : SmokeCloud = SmokeCloud.new()
	cloud.radius_px = radius_px
	cloud.hold_seconds = hold_seconds
	cloud.position = at - global_position #(before it is in the tree: its look is made from where it is)
	add_child(cloud)
	cloud.global_position = at
	return cloud


# ------------------------------------------------------------------ tripwires
func add_tripwire(pickup : Pickup, a : Vector2, b : Vector2) -> void:
	_tripwires[pickup.pickup_id] = {"pickup": pickup, "a": a, "b": b, "owner": pickup.placed_by, "quiet_until": 0}


func remove_tripwire(pickup : Pickup) -> void:
	_tripwires.erase(pickup.pickup_id)


func tripwire_count() -> int:
	return _tripwires.size()


func _physics_process(_delta : float) -> void:
	if not _active or not _is_lobby() or not players.is_valid():
		return
	var now : int = Time.get_ticks_msec()
	for player in players.call():
		if not is_instance_valid(player):
			continue
		var at : Vector2 = player.global_position
		var was : Vector2 = _last_positions.get(player, at)
		_last_positions[player] = at
		if not player.is_alive() or was == at:
			continue
		for id in _tripwires.keys():
			var wire : Dictionary = _tripwires[id]
			if not is_instance_valid(wire["pickup"]):
				_tripwires.erase(id)
				continue
			if player.member_id() == wire["owner"] or now < int(wire["quiet_until"]):
				continue
			if Geometry2D.segment_intersects_segment(was, at, wire["a"], wire["b"]) != null:
				wire["quiet_until"] = now + int(tripwire_cooldown_seconds * 1000.0)
				_trip(wire)
	for key in _last_positions.keys(): #(players who left)
		if not is_instance_valid(key):
			_last_positions.erase(key)


## Lobby: tells the wire's owner it was crossed.
func _trip(wire : Dictionary) -> void:
	var pickup : Pickup = wire["pickup"]
	var at : Vector2 = pickup.global_position
	var room : String = _room_name(at)
	trips_sent += 1
	var owner_id : int = wire["owner"]
	if owner_id == multiplayer.get_unique_id() or multiplayer.multiplayer_peer == null:
		_tripped(at, room)
	elif multiplayer.get_peers().has(owner_id):
		_tripped_remote.rpc_id(owner_id, at, room)


@rpc("authority", "call_remote", "reliable")
func _tripped_remote(at : Vector2, room : String) -> void:
	if _active:
		_tripped(at, room)


## The owner's peer: a ping where the wire is, and a line in the chat.
func _tripped(at : Vector2, room : String) -> void:
	if map_intel != null:
		map_intel.add_ping(ChatRules.Channel.GUARDS, "Tripwire", at, "Tripwire")
	if chat != null:
		chat.notice.emit("Your tripwire %swas crossed." % ("in %s " % room if room != "" else ""))


# ------------------------------------------------------------------ coms hackers
func add_hacker(pickup : Pickup) -> void:
	_hackers[pickup.pickup_id] = pickup


func remove_hacker(pickup : Pickup) -> void:
	_hackers.erase(pickup.pickup_id)


func hacker_count() -> int:
	return _hackers.size()


##Lobby: a chat message was sent. Every hacker within reach of the sender passes it to its owner, if the owner was not sent it already (not on that channel).
##Returns the owners it went to.
func intercept(sender_id : int, channel : int, sender_name : String, text : String, recipients : Array) -> Array[int]:
	var told : Array[int] = []
	if not _active or not player_lookup.is_valid():
		return told
	var speaker : Variant = player_lookup.call(sender_id)
	if not is_instance_valid(speaker):
		return told
	var reach_px : float = listen_radius_m * Acoustics.PX_PER_METRE
	for id in _hackers.keys():
		var hacker : Variant = _hackers[id]
		if not is_instance_valid(hacker):
			_hackers.erase(id)
			continue
		var owner_id : int = (hacker as Pickup).placed_by
		if owner_id < 0 or owner_id == sender_id or recipients.has(owner_id) or told.has(owner_id):
			continue
		if (speaker as Player).global_position.distance_to((hacker as Pickup).global_position) > reach_px:
			continue
		told.append(owner_id)
	for owner_id in told:
		intercepts_sent += 1
		var line : String = "[Intercepted, %s channel] %s: %s" % [ChatRules.channel_name(channel), sender_name, text]
		if chat != null:
			chat._tell(owner_id, line)
	return told


## Lobby: a shot struck a hacker: it breaks, for everyone.
func break_hacker(pickup : Pickup) -> void:
	if _is_lobby() and is_instance_valid(pickup) and pickup.control != null:
		pickup.control.destroy(pickup)


func _room_name(world : Vector2) -> String:
	if facility == null:
		return ""
	var id : String = facility.room_at(facility.to_local(world))
	return facility.rooms[id]["name"] if facility.rooms.has(id) else ""


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()
