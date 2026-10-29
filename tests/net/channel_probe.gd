extends Node

# Measures how long different RPC transfer modes take to arrive over a lossy connection.
# Run a server and a client (the client usually goes through tests/harness/latency_proxy.py):
#   Godot_console.exe --path . res://tests/net/channel_probe.tscn -- --role server --port 5200
#   Godot_console.exe --path . res://tests/net/channel_probe.tscn -- --role client --port 5201
# The client sends the same stream through each mode, with a trickle of reliable traffic alongside, like a real game.
# The server prints, per mode, how many arrived and the delay (ms) at the median, 95th percentile and worst case.

const SEND_HZ : int = 60
const DURATION : float = 10.0
const MODES : Array[String] = ["unreliable", "ordered", "ordered_own_channel", "reliable"]

var role : String = "server"
var port : int = 5200
var sent : Dictionary = {}
var delays : Dictionary = {}
var seq : int = 0
var elapsed : float = 0.0
var accumulator : float = 0.0
var finished : bool = false


func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var idx : int = args.find("--role")
	if idx != -1:
		role = args[idx + 1]
	idx = args.find("--port")
	if idx != -1:
		port = int(args[idx + 1])
	for mode in MODES:
		sent[mode] = 0
		delays[mode] = []
	var peer : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if role == "server":
		peer.create_server(port, 4)
		print("PROBE server listening on ", port)
	else:
		peer.create_client("127.0.0.1", port)
	multiplayer.multiplayer_peer = peer
	set_physics_process(role == "client")


func _physics_process(delta : float) -> void:
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or finished:
		return
	elapsed += delta
	seq += 1
	var now : float = Time.get_unix_time_from_system() #wall clock, so the client and server timestamps are comparable
	_unreliable.rpc_id(1, now)
	_ordered.rpc_id(1, now)
	_ordered_own_channel.rpc_id(1, now)
	sent["unreliable"] += 1
	sent["ordered"] += 1
	sent["ordered_own_channel"] += 1
	if seq % 6 == 0: #reliable traffic, ten messages a second, which is what keeps retransmissions happening
		_reliable.rpc_id(1, now)
		sent["reliable"] += 1
	if elapsed >= DURATION:
		finished = true
		_report.rpc_id(1, sent)
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


func _record(mode : String, sent_at : float) -> void:
	delays[mode].append((Time.get_unix_time_from_system() - sent_at) * 1000.0)


@rpc("any_peer", "call_remote", "unreliable")
func _unreliable(sent_at : float) -> void:
	_record("unreliable", sent_at)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _ordered(sent_at : float) -> void:
	_record("ordered", sent_at)


@rpc("any_peer", "call_remote", "unreliable_ordered", 7)
func _ordered_own_channel(sent_at : float) -> void:
	_record("ordered_own_channel", sent_at)


@rpc("any_peer", "call_remote", "reliable")
func _reliable(sent_at : float) -> void:
	_record("reliable", sent_at)


@rpc("any_peer", "call_remote", "reliable")
func _report(client_sent : Dictionary) -> void:
	for mode in MODES:
		var list : Array = delays[mode]
		list.sort()
		var count : int = list.size()
		var median : float = list[count / 2] if count > 0 else -1.0
		var p95 : float = list[int(count * 0.95)] if count > 0 else -1.0
		var worst : float = list[count - 1] if count > 0 else -1.0
		print("PROBE %-20s arrived %4d of %4d   median %6.0f ms   p95 %6.0f ms   worst %6.0f ms" % [mode, count, client_sent[mode], median, p95, worst])
	print("PROBE done")
	get_tree().quit()
