class_name UtilityConsoles
extends Node

##Gives every control console in the facility its screen. The consoles are ControlPanel scenes placed in the map scene, under its Props node (the Door
##Control room has one: drag more in from game/utility/ and set their `title`, `function` and `screen_scene`). build() makes each console's screen from
##its screen_scene, on a canvas layer of its own, and hands it the map and the facility's control. A new kind of console is a new screen scene and an
##inherited control_panel.tscn that points at it; nothing needs registering here.
##Call build() once the map is built. The consoles are interactables (see PlayerInteractor); what their screens change goes through `control`.
##
##One player at a console. Nobody takes a console directly: claim() asks the lobby, which gives it to the first player who asks (standing at it, alive) and
##tells every peer who has it (ControlPanel.occupant), so a console somebody is at says so to everyone and cannot be used. A player's screen opens at once and
##closes again if the lobby refuses. The lobby also checks a door request comes from the player who has a door console (is_occupant, see Level), and lets a
##console go when its player dies, leaves or walks off. Offline (the playground) the local peer is the lobby, so the same path runs with no network.

signal beeped(at : Vector2, powered : bool) ## every peer: a console beeped as a change made from it was accepted (heard round the console). powered: the higher beep

const SCREEN_LAYER : int = 20
const CLAIM_REACH_SLACK : float = 1.5 #the lobby's view of a player can be a few ticks behind, so its reach check is a little looser
const CHECK_SECONDS : float = 0.5 #how often the lobby looks for a player who is no longer at the console they hold

@export var facility : FacilityMap
@export var control : FacilityControl

var panels : Array[ControlPanel] = []
var player_of : Callable = Callable() ## (peer_id : int) -> Player or null. Set by the level; unset, the lobby does not check who holds a console

var _screen_layer : CanvasLayer
var _occupants : Dictionary = {} #panel index -> peer id, kept on every peer
var _active : bool = true
var _since_check : float = 0.0


func build() -> void:
	_screen_layer = CanvasLayer.new()
	_screen_layer.name = "Screens"
	_screen_layer.layer = SCREEN_LAYER
	add_child(_screen_layer)
	for node : Node in _descendants(facility.props_node):
		if node is ControlPanel:
			_add_console(node)


func _process(delta : float) -> void:
	if not _active or not _is_lobby() or _occupants.is_empty():
		return
	_since_check += delta
	if _since_check < CHECK_SECONDS:
		return
	_since_check = 0.0
	for index : int in _occupants.keys():
		if not _is_at(_occupants[index], panels[index]):
			_set_occupant(index, 0)


##The first console that works this function, or null.
func panel_for(function : String) -> ControlPanel:
	for panel in panels:
		if panel.function == function:
			return panel
	return null


##Is this position at a console that works this function? The lobby uses it to check requests, with some slack because the lobby's view of a
##player can be a few ticks behind what the player saw when they clicked.
func is_at_console(function : String, world_position : Vector2, slack : float = 1.0) -> bool:
	for panel in panels:
		if panel.function == function and panel.is_in_reach(world_position, slack):
			return true
	return false


##Lobby: does this peer have a console that works this function?
func is_occupant(peer_id : int, function : String) -> bool:
	for index : int in _occupants:
		if _occupants[index] == peer_id and panels[index].function == function:
			return true
	return false


##Lobby: the console this peer is at beeps, on every peer (it is heard round it, see `beeped`). powered: what was changed now takes power (a higher beep).
##Nothing if the peer has no console.
func beep_for(peer_id : int, powered : bool) -> void:
	if not _active or not _is_lobby():
		return
	for index : int in _occupants:
		if _occupants[index] == peer_id:
			_beep(index, powered)
			if not multiplayer.get_peers().is_empty():
				_beep_remote.rpc(index, powered)
			return


func _beep(index : int, powered : bool) -> void:
	if index >= 0 and index < panels.size():
		beeped.emit(panels[index].global_position, powered)


##Asks for the console, as the player at it. Safe to call on any peer; only the lobby decides.
func claim(panel : ControlPanel) -> void:
	var index : int = panels.find(panel)
	if not _active or index < 0:
		return
	if _is_lobby():
		_decide_claim(multiplayer.get_unique_id(), index)
	else:
		_claim_request.rpc_id(1, index)


##Gives the console up (the player closed its screen).
func release(panel : ControlPanel) -> void:
	var index : int = panels.find(panel)
	if not _active or index < 0:
		return
	if _is_lobby():
		_decide_release(multiplayer.get_unique_id(), index)
	else:
		_release_request.rpc_id(1, index)


##Stops sending and applying changes. Call it when the game starts to end, before the node is freed (see NetworkUnloader).
func quiesce() -> void:
	_active = false


func _decide_claim(peer_id : int, index : int) -> void:
	if index < 0 or index >= panels.size():
		return
	var holder : int = _occupants.get(index, 0)
	if (holder != 0 and holder != peer_id and _is_at(holder, panels[index])) or not _is_at(peer_id, panels[index]):
		_refuse(peer_id, index)
		return
	_set_occupant(index, peer_id)


func _decide_release(peer_id : int, index : int) -> void:
	if _occupants.get(index, 0) == peer_id:
		_set_occupant(index, 0)


##Lobby: sets who has a console, here and on every other peer.
func _set_occupant(index : int, peer_id : int) -> void:
	_apply_occupant(index, peer_id)
	if not multiplayer.get_peers().is_empty():
		_occupant_changed.rpc(index, peer_id)


func _apply_occupant(index : int, peer_id : int) -> void:
	if index < 0 or index >= panels.size():
		return
	if peer_id == 0:
		_occupants.erase(index)
	else:
		_occupants[index] = peer_id
	panels[index].occupant = peer_id


func _refuse(peer_id : int, index : int) -> void:
	if peer_id == multiplayer.get_unique_id():
		panels[index].refused()
	else:
		_claim_refused.rpc_id(peer_id, index)


## Lobby: is this peer's player alive and at the console (as the lobby sees them)? Unchecked while there is no way to find the player.
func _is_at(peer_id : int, panel : ControlPanel) -> bool:
	if not player_of.is_valid():
		return true
	var player : Player = player_of.call(peer_id)
	return player != null and is_instance_valid(player) and player.is_alive() and panel.is_in_reach(player.global_position, CLAIM_REACH_SLACK)


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("any_peer", "call_remote", "reliable")
func _claim_request(index : int) -> void:
	if _active and multiplayer.is_server():
		_decide_claim(multiplayer.get_remote_sender_id(), index)


@rpc("any_peer", "call_remote", "reliable")
func _release_request(index : int) -> void:
	if _active and multiplayer.is_server():
		_decide_release(multiplayer.get_remote_sender_id(), index)


@rpc("authority", "call_remote", "reliable")
func _occupant_changed(index : int, peer_id : int) -> void:
	if _active:
		_apply_occupant(index, peer_id)


@rpc("authority", "call_remote", "reliable")
func _beep_remote(index : int, powered : bool) -> void:
	if _active:
		_beep(index, powered)


@rpc("authority", "call_remote", "reliable")
func _claim_refused(index : int) -> void:
	if _active and index >= 0 and index < panels.size():
		panels[index].refused()


func _add_console(panel : ControlPanel) -> void:
	panel.consoles = self
	if panel.screen_scene == null:
		push_warning("%s has no screen_scene, so using it opens nothing" % panel.get_path())
		panels.append(panel)
		return
	var screen : Control = panel.screen_scene.instantiate()
	screen.name = "%sScreen" % panel.name
	screen.set("facility", facility)
	screen.set("control", control)
	_screen_layer.add_child(screen)
	panel.screen = screen
	panels.append(panel)


func _descendants(node : Node) -> Array[Node]:
	var result : Array[Node] = []
	for child : Node in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result
