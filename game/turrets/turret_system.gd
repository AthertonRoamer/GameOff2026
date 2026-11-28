class_name TurretSystem
extends Node

##The facility's turrets (Turret, under the map's Props), owned by the lobby. Whether a turret is switched on is FacilityControl's (it is a switch like a light,
##worked from the door console or by a technician, and it costs power: PowerGrid); what a turret that is on does is decided here, on the lobby only:
##every physics tick it runs each turret's thinking (Turret.lobby_step), fires its shots through HitscanManager.fire_turret (the game deals the damage like any
##other hit), and tells every other peer, sync_hz times a second, where each turret points and what it is doing, so they draw and hear it the same.
##Its health is the lobby's too: a shot that ends on a turret damages it here and every peer is told. Shot down, its switch is forced off; a guard repairs it
##by holding E (the lobby checks the hold, as PowerGrid does for a generator).
##A turret is heard turning (a looped whir, SoundSystem.set_hum) and firing, and its lock-on beeps; standing still it makes no sound at all.
##Offline (the playground, tests) the local peer is the lobby, so the same path runs with no network.

const GROUP : StringName = &"turret_system"
const HOLD_SLACK_SECONDS : float = 0.6 #the lobby lets a hold be this much shorter than it should, for the time the messages take
const REACH_SLACK : float = 1.5
const FULL_SYNC_SECONDS : float = 1.0 #every turret is sent this often even if nothing changed (the sync is unreliable)
const STALE_HOLD_SECONDS : float = 2.0 #a repair hold this much longer than it needs was never ended (its player left): the lobby lets it go

signal turret_fired(turret : Turret) #every peer: a turret fired a shot (the sound and the flash)
signal turret_damaged(turret : Turret) #every peer: a turret's health changed
signal turret_repairing(turret : Turret, on : bool) #every peer: someone began (or stopped) holding E to repair a shot-down turret: it is heard meanwhile

@export var facility : FacilityMap
@export var control : FacilityControl
@export var hitscan : HitscanManager
@export var sound : SoundSystem

##() -> Array of Player: who a turret can see. Set by the scene that spawns the players; unset, turrets see nobody.
var players : Callable = Callable()
##(peer_id : int) -> Player or null. Set by the level; unset, the lobby does not check who repairs or switches a turret (tests).
var player_of : Callable = Callable()

var turrets : Array[Turret] = []

var _active : bool = true
var _holds : Dictionary = {} #lobby: peer id -> {index, since (msec)}
var _sync_in : float = 0.0
var _full_sync_in : float = 0.0
var _sent : Dictionary = {} #lobby: turret index -> [aim, phase] last sent
var _heard_phase : Dictionary = {} #every peer: turret index -> the phase it last showed (to hear a lock-on start)
var _humming : Dictionary = {} #every peer: turret index -> whether its whir is on
var _repairing : Dictionary = {} #every peer: turret index -> true while someone holds E to repair it


func _ready() -> void:
	add_to_group(GROUP)


##Finds the turrets (under the map's Props, in scene order: the same on every peer), gives each its switch for technicians, and sizes FacilityControl's turret
##switches. Call once the map is built, before PowerGrid.build.
func build() -> void:
	turrets.clear()
	if facility == null:
		return
	var regions : PackedStringArray = PackedStringArray()
	for node : Node in _descendants(facility.props_node):
		if node is Turret:
			var turret : Turret = node
			turret.system = self
			turret.index = turrets.size()
			turret.region = facility.region_at(facility.to_local(turret.global_position))
			turret.health = turret.max_health()
			turret.phase = Turret.Phase.OFF
			turrets.append(turret)
			regions.append(turret.region)
			if control != null and turret.get_node_or_null("TurretSwitch") == null:
				var turret_switch : TurretSwitch = TurretSwitch.new()
				turret_switch.name = "TurretSwitch"
				turret_switch.turret = turret
				turret_switch.control = control
				turret.add_child(turret_switch)
	if control != null:
		control.build_turrets(regions)
		control.can_turret_switch_on = func(index : int) -> bool: return index >= 0 and index < turrets.size() and not turrets[index].is_destroyed()


func is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func is_on(turret : Turret) -> bool:
	return control != null and control.is_turret_on(turret.index)


# ------------------------------------------------------------------ the lobby thinks
func _physics_process(delta : float) -> void:
	if not _active or turrets.is_empty():
		return
	if is_lobby():
		var everyone : Array = players.call() if players.is_valid() else []
		for turret in turrets:
			if not is_instance_valid(turret):
				continue
			for direction : Vector2 in turret.lobby_step(delta, is_on(turret), everyone):
				_fire(turret, direction)
		_send_sync(delta)
		_drop_stale_holds()
	_listen()


func _fire(turret : Turret, direction : Vector2) -> void:
	if hitscan != null:
		var settings : TurretSettings = turret.the_settings()
		var hittable : Callable = Callable() #friendly fire: anyone in the way is hit
		if not settings.friendly_fire: #off: its shots pass through guards
			hittable = Turret.is_quarry
		hitscan.fire_turret(turret, turret.muzzle(), direction, settings.damage, settings.range_px, settings.bullet_color, hittable)
	_on_fired(turret.index)
	if not multiplayer.get_peers().is_empty():
		_fired_remote.rpc(turret.index)


func _send_sync(delta : float) -> void:
	if multiplayer.get_peers().is_empty():
		return
	_sync_in -= delta
	_full_sync_in -= delta
	if _sync_in > 0.0:
		return
	_sync_in = 1.0 / maxf(1.0, turrets[0].the_settings().sync_hz)
	var full : bool = _full_sync_in <= 0.0
	if full:
		_full_sync_in = FULL_SYNC_SECONDS
	var indices : PackedInt32Array = PackedInt32Array()
	var aims : PackedFloat32Array = PackedFloat32Array()
	var phases : PackedByteArray = PackedByteArray()
	for turret in turrets:
		var last : Array = _sent.get(turret.index, [])
		if full or last.is_empty() or absf(angle_difference(float(last[0]), turret.aim)) > 0.001 or int(last[1]) != turret.phase:
			indices.append(turret.index)
			aims.append(turret.aim)
			phases.append(turret.phase)
			_sent[turret.index] = [turret.aim, turret.phase]
	if not indices.is_empty():
		_sync_remote.rpc(indices, aims, phases)


# ------------------------------------------------------------------ every peer: heard and seen
func _on_fired(index : int) -> void:
	if index < 0 or index >= turrets.size():
		return
	var turret : Turret = turrets[index]
	turret.show_shot()
	if sound != null and sound.turret_shot != null:
		sound.play(sound.turret_shot, turret.muzzle())
	turret_fired.emit(turret)


##The whir while a turret turns, and the beep as it locks on. Nothing while it stands still.
func _listen() -> void:
	for turret in turrets:
		if not is_instance_valid(turret):
			continue
		var turning : bool = turret.is_turning() and not turret.is_destroyed()
		if turning != _humming.get(turret.index, false):
			_humming[turret.index] = turning
			if sound != null:
				sound.set_hum(hum_key(turret), sound.turret_turn if turning else null, turret.global_position)
		var was : int = _heard_phase.get(turret.index, Turret.Phase.OFF)
		if turret.phase == Turret.Phase.LOCKING and was != Turret.Phase.LOCKING and was != Turret.Phase.FIRING and sound != null and sound.turret_lock != null:
			sound.play(sound.turret_lock, turret.global_position)
		_heard_phase[turret.index] = turret.phase


static func hum_key(turret : Turret) -> String:
	return "turret:%d" % turret.index


# ------------------------------------------------------------------ health: shot at by anyone, repaired by guards
##Lobby: a shot ended on a turret.
func damage_turret(turret : Turret, damage : float) -> void:
	if not _active or not is_lobby() or turret.is_destroyed() or damage <= 0.0:
		return
	_set_health(turret.index, maxf(0.0, turret.health - damage))


##Lobby, and tests: sets a turret's health here and on every peer (0 shoots it down, and switches it off).
func set_health(turret : Turret, health : float) -> void:
	if is_lobby():
		_set_health(turret.index, health)


func _set_health(index : int, health : float) -> void:
	_apply_health(index, health)
	if health <= 0.0 and control != null:
		if control.power != null:
			control.power.remove_load(PowerGrid.turret_key(index)) #(its power is free at once; the switch goes off on its tick)
		control.force_turret_off(index)
	if not multiplayer.get_peers().is_empty():
		_health_remote.rpc(index, health)
	_update_repairing() #(brought back some other way while someone was repairing it)


func _apply_health(index : int, health : float) -> void:
	if index < 0 or index >= turrets.size():
		return
	var turret : Turret = turrets[index]
	turret.health = health
	if health <= 0.0:
		turret.phase = Turret.Phase.DESTROYED
	elif turret.phase == Turret.Phase.DESTROYED:
		turret.phase = Turret.Phase.OFF
		turret.aim = turret.facing()
		turret.aim_target = turret.aim
	turret_damaged.emit(turret)


##Holding E on a shot-down turret began (started = true) or stopped before it was done.
func request_hold(turret : Turret, started : bool) -> void:
	if not _active:
		return
	if is_lobby():
		_decide_hold(multiplayer.get_unique_id(), turret.index, started)
	else:
		_hold_request.rpc_id(1, turret.index, started)


##The hold is done: repair it.
func request_finish(turret : Turret) -> void:
	if not _active:
		return
	if is_lobby():
		_decide_finish(multiplayer.get_unique_id(), turret.index)
	else:
		_finish_request.rpc_id(1, turret.index)


func _decide_hold(peer_id : int, index : int, started : bool) -> void:
	if index < 0 or index >= turrets.size():
		return
	if started and _may_repair(peer_id, turrets[index]):
		_holds[peer_id] = {"index": index, "since": Time.get_ticks_msec()}
	elif not started and _holds.has(peer_id) and _holds[peer_id]["index"] == index:
		_holds.erase(peer_id)
	_update_repairing()


func _decide_finish(peer_id : int, index : int) -> void:
	if index < 0 or index >= turrets.size() or not _holds.has(peer_id) or _holds[peer_id]["index"] != index:
		return
	var turret : Turret = turrets[index]
	var held : float = (Time.get_ticks_msec() - int(_holds[peer_id]["since"])) / 1000.0
	_holds.erase(peer_id)
	_update_repairing()
	if not turret.is_destroyed() or held < turret.hold_seconds(null) - HOLD_SLACK_SECONDS or not _may_repair(peer_id, turret):
		return
	_set_health(index, turret.max_health()) #back at full health, switched off


##Lobby: which turrets are being repaired now (someone holds E on a shot-down one), told to every peer when it changes: a repair is heard.
func _update_repairing() -> void:
	if not _active or not is_lobby():
		return
	var now : Dictionary = {}
	for peer_id : int in _holds:
		var index : int = _holds[peer_id]["index"]
		if index >= 0 and index < turrets.size() and turrets[index].is_destroyed():
			now[index] = true
	for index : int in _repairing.keys():
		if not now.has(index):
			_set_repairing(index, false)
	for index : int in now:
		if not _repairing.has(index):
			_set_repairing(index, true)


func _set_repairing(index : int, on : bool) -> void:
	_apply_repairing(index, on)
	if not multiplayer.get_peers().is_empty():
		_repairing_remote.rpc(index, on)


func _apply_repairing(index : int, on : bool) -> void:
	if index < 0 or index >= turrets.size() or _repairing.has(index) == on:
		return
	if on:
		_repairing[index] = true
	else:
		_repairing.erase(index)
	if sound != null:
		sound.on_repair("repair:" + hum_key(turrets[index]), turrets[index].global_position, on)
	turret_repairing.emit(turrets[index], on)


##Is someone repairing this turret now (every peer)?
func is_repairing(turret : Turret) -> bool:
	return _repairing.has(turret.index)


##Lobby: lets go of holds that were never ended (a player who left mid-repair), so the repair is not heard for ever.
func _drop_stale_holds() -> void:
	if _holds.is_empty():
		return
	var now_msec : int = Time.get_ticks_msec()
	var stale : Array = []
	for peer_id : int in _holds:
		var index : int = _holds[peer_id]["index"]
		var longest : float = turrets[index].hold_seconds(null) + STALE_HOLD_SECONDS if index >= 0 and index < turrets.size() else 0.0
		if (now_msec - int(_holds[peer_id]["since"])) / 1000.0 > longest:
			stale.append(peer_id)
	if stale.is_empty():
		return
	for peer_id : int in stale:
		_holds.erase(peer_id)
	_update_repairing()


func _may_repair(peer_id : int, turret : Turret) -> bool:
	if not turret.is_destroyed():
		return false
	if not player_of.is_valid():
		return true
	var player : Node2D = player_of.call(peer_id)
	if player == null or not is_instance_valid(player) or not player.is_alive() or not turret.can_interact(player):
		return false
	return turret.global_position.distance_to(player.global_position) <= turret.reach_px() * REACH_SLACK


##Lobby: may this peer's player switch this turret by hand now (a living player whose role works doors, standing by it, see TurretSwitch)?
func may_switch_by_hand(peer_id : int, index : int) -> bool:
	if index < 0 or index >= turrets.size() or turrets[index].is_destroyed():
		return false
	if not player_of.is_valid():
		return true
	var player : Node2D = player_of.call(peer_id)
	if player == null or not is_instance_valid(player) or not player.is_alive() or not TurretSwitch.may_work(player):
		return false
	var turret_switch : TurretSwitch = turrets[index].get_node_or_null("TurretSwitch")
	return turret_switch != null and turret_switch.is_in_reach(player.global_position, TurretSwitch.REACH_SLACK)


# ------------------------------------------------------------------ the match
##Lobby only: sends every turret's health to every peer. Called when the game starts, next to FacilityControl.broadcast_snapshot().
func broadcast_snapshot() -> void:
	if not _active or not is_lobby() or multiplayer.get_peers().is_empty():
		return
	var healths : PackedFloat32Array = PackedFloat32Array()
	for turret in turrets:
		healths.append(turret.health)
	_snapshot_remote.rpc(healths)


##Stops sending and applying changes, and silences the turrets. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false
	_holds.clear()
	for index : int in _repairing.keys():
		_apply_repairing(index, false)
	if sound != null:
		for turret in turrets:
			if is_instance_valid(turret):
				sound.set_hum(hum_key(turret), null, Vector2.ZERO)
	_humming.clear()


func _descendants(node : Node) -> Array[Node]:
	var result : Array[Node] = []
	if node == null:
		return result
	for child : Node in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_remote(indices : PackedInt32Array, aims : PackedFloat32Array, phases : PackedByteArray) -> void:
	if not _active:
		return
	for i in mini(indices.size(), mini(aims.size(), phases.size())):
		var index : int = indices[i]
		if index >= 0 and index < turrets.size():
			turrets[index].apply_sync(aims[i], phases[i] as Turret.Phase)


@rpc("authority", "call_remote", "unreliable")
func _fired_remote(index : int) -> void:
	if _active:
		_on_fired(index)


@rpc("authority", "call_remote", "reliable")
func _repairing_remote(index : int, on : bool) -> void:
	if _active:
		_apply_repairing(index, on)


@rpc("authority", "call_remote", "reliable")
func _health_remote(index : int, health : float) -> void:
	if _active:
		_apply_health(index, health)


@rpc("authority", "call_remote", "reliable")
func _snapshot_remote(healths : PackedFloat32Array) -> void:
	if not _active:
		return
	for i in mini(healths.size(), turrets.size()):
		_apply_health(i, healths[i])


@rpc("any_peer", "call_remote", "reliable")
func _hold_request(index : int, started : bool) -> void:
	if _active and multiplayer.is_server():
		_decide_hold(multiplayer.get_remote_sender_id(), index, started)


@rpc("any_peer", "call_remote", "reliable")
func _finish_request(index : int) -> void:
	if _active and multiplayer.is_server():
		_decide_finish(multiplayer.get_remote_sender_id(), index)
