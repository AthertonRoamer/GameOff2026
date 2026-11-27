extends Node

## Loads the noray relay with made-up traffic, no game: two processes join through the relay the way the game does, the client sends packets of a set size at a set
## rate, the host sends each one straight back, and every step reports the round trip, what came back and what was lost. Tells a slow or limited relay from a fault
## in the game. Run with tests/net/run_relay_load.ps1. It puts load on the shared noray server, so not during a playtest.

const NORAY_HOST : String = "159.89.237.170"
const NORAY_PORT : int = 8890
const STEP_SECONDS : float = 10.0
const SETTLE_SECONDS : float = 2.0 #left out at the start of a step: what is still on the way from the step before
## [name, packets per second, bytes per packet], each direction. The game sends about 20 kB/s each way in small packets, a few per tick at 60 ticks a second.
const STEPS : Array = [
	["tiny", 20, 100],
	["few big 20 kB/s", 40, 500],
	["few big 40 kB/s", 80, 500],
	["few big 80 kB/s", 80, 1000],
	["many small 60/s", 60, 100],
	["many small 120/s", 120, 100],
	["many small 180/s", 180, 100],
	["many small 300/s", 300, 100],
	["many small 600/s", 600, 100],
	["game-like 180/s 20 kB/s", 180, 112],
	["tiny again", 20, 100],
]

var _role : String = ""
var _oid_path : String = ""
var _oid : String = ""
var _peer : ENetMultiplayerPeer
var _connected : bool = false
var _step : int = -1
var _step_time : float = 0.0
var _owed : float = 0.0
var _sequence : int = 0
var _sent : int = 0
var _back : int = 0
var _round_trips : PackedFloat32Array = []
var _first_counted : int = 0 #the first sequence number of the step that is counted (after the settle time)
var _life : float = 0.0


func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	_role = args[0]
	_oid_path = args[1]
	if await _join_noray() != OK:
		_say("FAILED to register with noray")
		get_tree().quit(1)
		return
	if _role == "host":
		Noray.on_connect_nat.connect(_host_handshake)
		Noray.on_connect_relay.connect(_host_handshake)
		_peer = ENetMultiplayerPeer.new()
		_peer.create_server(Noray.local_port, 4)
		_peer.peer_connected.connect(func(_id : int) -> void:
			_connected = true
			_say("client connected"))
		_peer.peer_disconnected.connect(func(_id : int) -> void:
			_say("client left")
			get_tree().quit())
		var file : FileAccess = FileAccess.open(_oid_path, FileAccess.WRITE)
		file.store_string(Noray.oid)
		file.close()
		_say("ready")
	else:
		_oid = FileAccess.get_file_as_string(_oid_path).strip_edges()
		Noray.on_connect_relay.connect(_client_connect)
		Noray.connect_relay(_oid) #(straight to the relay: it is the relay being tested)


func _join_noray() -> Error:
	if await Noray.connect_to_host(NORAY_HOST, NORAY_PORT) != OK:
		return FAILED
	Noray.register_host()
	await Noray.on_pid
	return await Noray.register_remote()


func _host_handshake(address : String, port : int) -> void:
	await PacketHandshake.over_enet(_peer.host, address, port)


func _client_connect(address : String, port : int) -> void:
	var udp : PacketPeerUDP = PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)
	var error : Error = await PacketHandshake.over_packet_peer(udp, 8)
	udp.close()
	if error != OK:
		_say("FAILED handshake through the relay (%d)" % error)
		get_tree().quit(1)
		return
	_peer = ENetMultiplayerPeer.new()
	_peer.create_client(address, port, 0, 0, 0, Noray.local_port)
	_peer.peer_connected.connect(func(_id : int) -> void:
		_connected = true
		_say("connected through the relay at %s:%d" % [address, port])
		_next_step())
	_peer.peer_disconnected.connect(func(_id : int) -> void:
		_say("DISCONNECTED during step '%s'" % (STEPS[_step][0] if _step >= 0 else "none"))
		get_tree().quit(1))


func _process(delta : float) -> void:
	_life += delta
	if _life > 220.0:
		_say("time limit")
		get_tree().quit(1)
		return
	if _peer == null:
		return
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var from : int = _peer.get_packet_peer()
		var packet : PackedByteArray = _peer.get_packet()
		if _role == "host":
			_send(from, packet)
		elif packet.size() >= 12 and packet.decode_u32(0) >= _first_counted:
			_back += 1
			_round_trips.append((Time.get_ticks_usec() - packet.decode_u64(4)) / 1000.0)
	if _role != "client" or not _connected or _step < 0:
		return
	var was : float = _step_time
	_step_time += delta
	if was < SETTLE_SECONDS and _step_time >= SETTLE_SECONDS:
		_first_counted = _sequence
		_sent = 0
		_back = 0
		_round_trips.clear()
	_owed += delta * STEPS[_step][1]
	while _owed >= 1.0:
		_owed -= 1.0
		var packet : PackedByteArray = PackedByteArray()
		packet.resize(STEPS[_step][2])
		packet.encode_u32(0, _sequence)
		packet.encode_u64(4, Time.get_ticks_usec())
		_sequence += 1
		_sent += 1
		_send(1, packet)
	if _step_time >= STEP_SECONDS:
		_report()
		_next_step()


func _send(to : int, packet : PackedByteArray) -> void:
	_peer.set_target_peer(to)
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	_peer.put_packet(packet)


func _next_step() -> void:
	_step += 1
	_step_time = 0.0
	_owed = 0.0
	_sent = 0
	_back = 0
	_round_trips.clear()
	if _step >= STEPS.size():
		_say("DONE")
		_peer.close()
		get_tree().quit()
		_step = -1


func _report() -> void:
	_round_trips.sort()
	var count : int = _round_trips.size()
	var seconds : float = STEP_SECONDS - SETTLE_SECONDS
	#(packets sent in the last moments of a step have not had time to come back, so a little "missing" is normal)
	_say("STEP %-26s %4d pkt/s x %4d B = %5.1f kB/s each way | back %5.1f%% | round trip median %5.0f ms, 95th %5.0f ms, worst %5.0f ms" % [
		STEPS[_step][0], STEPS[_step][1], STEPS[_step][2], _sent / seconds * STEPS[_step][2] / 1000.0, 100.0 * _back / maxi(_sent, 1),
		_round_trips[count / 2] if count > 0 else -1.0, _round_trips[int(count * 0.95)] if count > 0 else -1.0, _round_trips[count - 1] if count > 0 else -1.0])


func _say(text : String) -> void:
	print("[%s] %s" % [_role.to_upper(), text])
