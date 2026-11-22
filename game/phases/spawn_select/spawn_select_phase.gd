class_name SpawnSelectPhase
extends MatchPhase

##Each player chooses where to start: a map of the facility with the spawn rooms of their kind lit up (guard rooms for guards, secretly attacking
##guards included; intruder rooms for intruders, see SpawnRoomMarker), and the other kind's shown dimmed so they know where the other side may start. Clicking one asks the lobby, which checks it is a room of the right kind and
##then tells each player the picks they may see (RoleAssigner.sees_spawn_of): guards see guards, the intruder and the secretly attacking guard see
##each other. Attackers also see the designated exit on the map. Picks can be changed until the end.
##It ends linger_seconds after everyone has picked (so the last picks can be seen), or when its duration runs out. When it ends the lobby gives
##anyone who didn't pick a random room of their kind and moves every player to their room (Player.teleport, so it syncs like any movement).

@export var linger_seconds : float = 5.0 #how long it stays up once everyone has picked
@export var spread_px : float = 40.0 #players who start in the same room stand this far apart, side by side around its marker

var _picks : Dictionary = {} #lobby: member id -> room id
var _all_picked_since : int = -1 #lobby: the tick everyone had picked by, -1 while someone hasn't
var _active : bool = false
var _rng : RandomNumberGenerator = RandomNumberGenerator.new()

@onready var screen : CanvasLayer = $Screen
@onready var map : FacilityMapView = $Screen/Margin/Box/Map
@onready var spawn_layer : SpawnLayer = $Screen/Margin/Box/Map/Spawns
@onready var exits_layer : ExitsLayer = $Screen/Margin/Box/Map/Exits
@onready var status_label : Label = $Screen/Margin/Box/Status
@onready var legend_label : Label = $Screen/Margin/Box/Legend
@onready var countdown_label : Label = $Screen/Margin/Box/Countdown


func _ready() -> void:
	screen.visible = false
	set_process(false)
	spawn_layer.room_clicked.connect(_on_room_clicked)
	_rng.randomize()


func enter() -> void:
	_active = true
	_picks.clear()
	_all_picked_since = -1
	var player : Player = _local_player()
	if player == null: #a lobby process plays nobody: it only decides
		return
	var kind : int = SpawnRoomMarker.kind_for(player.role)
	spawn_layer.spawn_kind = kind
	spawn_layer.local_id = _local_id() #players are keyed by peer id
	spawn_layer.own_pick = ""
	spawn_layer.set_picks({}, {})
	exits_layer.highlighted = game.exit_chooser.designated
	map.facility = game.level.facility
	legend_label.text = _legend(kind, exits_layer.highlighted != "")
	status_label.text = "Click a room to start there."
	screen.visible = true
	set_process(true)
	_frame_rooms.call_deferred(kind) #once the screen has been laid out


func exit() -> void:
	_active = false
	screen.visible = false
	set_process(false)
	if _is_lobby():
		place_players()


func lobby_is_done(tick : int) -> bool:
	var members : Array = member_ids()
	if members.is_empty() or not members.all(func(id : int) -> bool: return _picks.has(id)):
		_all_picked_since = -1
		return false
	if _all_picked_since < 0:
		_all_picked_since = tick
	return tick >= _all_picked_since + ceili(linger_seconds * NetworkTime.tickrate)


##Every player in the match (they are all spawned before the phases start).
func member_ids() -> Array:
	return game.spawner.players.keys().filter(func(id : int) -> bool: return is_instance_valid(game.spawner.players[id]))


##The spawn kind a member starts as, from their role (public, the same on every peer).
func kind_of(member_id : int) -> int:
	var player : Player = game.spawner.players.get(member_id)
	return SpawnRoomMarker.kind_for(player.role if is_instance_valid(player) else null)


##Lobby only: a member asks to start in a room. Refused unless the phase is running and the room is a spawn room of the member's kind.
func decide_pick(member_id : int, room_id : String) -> bool:
	if not _active or not member_ids().has(member_id) or not game.level.facility.spawn_rooms(kind_of(member_id)).has(room_id):
		return false
	_picks[member_id] = room_id
	_send_picks()
	return true


##Lobby only: the picks one member may see.
func picks_visible_to(viewer_id : int) -> Dictionary:
	var visible : Dictionary = {}
	for member : int in _picks:
		if game.role_assigner.sees_spawn_of(viewer_id, member, game.assignment):
			visible[member] = _picks[member]
	return visible


##Lobby only, when the phase ends: everyone who didn't pick gets a random room of their kind, then every player is moved to their room.
func place_players() -> void:
	var facility : FacilityMap = game.level.facility
	var in_room : Dictionary = {} #room id -> [member ids], to stand them side by side
	for member : int in member_ids():
		var allowed : Array[String] = facility.spawn_rooms(kind_of(member))
		if allowed.is_empty():
			continue #a map without spawn rooms of this kind: they stay where PlayerSetup put them
		if not _picks.has(member) or not allowed.has(_picks[member]):
			_picks[member] = allowed[_rng.randi_range(0, allowed.size() - 1)]
		if not in_room.has(_picks[member]):
			in_room[_picks[member]] = []
		in_room[_picks[member]].append(member)
	for room : String in in_room:
		var members : Array = in_room[room]
		members.sort()
		for i in members.size():
			var player : Player = game.spawner.players[members[i]]
			var offset : Vector2 = Vector2((i - (members.size() - 1) / 2.0) * spread_px, 0.0)
			player.teleport(facility.spawn_point(room, kind_of(members[i])) + offset)


func picks() -> Dictionary:
	return _picks.duplicate()


func _on_room_clicked(room_id : String) -> void:
	spawn_layer.own_pick = room_id #shown at once; the lobby's answer confirms it
	status_label.text = "You will start in the %s. Click another room to change." % game.level.facility.rooms[room_id]["name"]
	if _is_lobby():
		decide_pick(_local_id(), room_id)
	else:
		_request_pick.rpc_id(1, room_id)


func _send_picks() -> void:
	for member : int in member_ids():
		var visible : Dictionary = picks_visible_to(member)
		if member == _local_id():
			_show_picks(visible)
		elif not multiplayer.get_peers().is_empty():
			_receive_picks.rpc_id(member, visible)


func _show_picks(visible : Dictionary) -> void:
	var names : Dictionary = {}
	for member : int in visible:
		var player : Player = game.spawner.players.get(member)
		names[member] = player.player_name if is_instance_valid(player) else "?"
	spawn_layer.set_picks(visible, names)
	if visible.has(_local_id()):
		spawn_layer.own_pick = visible[_local_id()]


##Centres the map on the rooms this player can choose.
func _frame_rooms(kind : int) -> void:
	var bounds : Rect2
	var first : bool = true
	for room : String in game.level.facility.spawn_rooms(kind):
		for rect : Rect2 in game.level.facility.room_rects_px(room):
			bounds = rect if first else bounds.merge(rect)
			first = false
	map.reset_view()
	if not first:
		map.center_on(bounds.get_center())


static func _legend(kind : int, sees_exit : bool) -> String:
	var other : int = SpawnRoomMarker.Kind.INTRUDER if kind == SpawnRoomMarker.Kind.GUARD else SpawnRoomMarker.Kind.GUARD
	var colour_names : Array[String] = ["blue", "red"] #SpawnRoomMarker.COLOURS
	var text : String = "Pick one of the %s %s SPAWN rooms. The dashed %s %s SPAWN rooms are where the other side may start. Allies' picks show their names." % [
		colour_names[kind], SpawnRoomMarker.name_of(kind).to_upper(), colour_names[other], SpawnRoomMarker.name_of(other).to_upper()]
	if sees_exit:
		text += "  The green exit is the one you must escape through."
	return text + "  Drag to scroll, wheel to zoom."


func _process(_delta : float) -> void:
	countdown_label.text = "Starting in %d" % ceili(seconds_left())


func _local_player() -> Player:
	var player : Player = game.spawner.local_player if game != null and game.spawner != null else null
	return player if is_instance_valid(player) else null


func _local_id() -> int:
	return multiplayer.get_unique_id()


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("any_peer", "call_remote", "reliable")
func _request_pick(room_id : String) -> void:
	if multiplayer.is_server():
		decide_pick(multiplayer.get_remote_sender_id(), room_id)


@rpc("authority", "call_remote", "reliable")
func _receive_picks(visible : Dictionary) -> void:
	if _active:
		_show_picks(visible)
