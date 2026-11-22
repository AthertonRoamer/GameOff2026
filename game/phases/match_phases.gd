class_name MatchPhases
extends Node

##Runs the phases before play begins: its MatchPhase children, in tree order. Add, remove or reorder phases by moving their scenes under this
##node; nothing is registered in code. Game calls run() on the shared start tick and begins play when `finished` fires.
##
##Every peer enters the first phase on the start tick by itself. After that, the lobby decides when each phase ends, the way FacilityControl decides
##doors: once the phase's duration is up or its lobby_is_done() says so, it picks a tick a little in the future and tells every peer, and every peer
##(the lobby too) leaves that phase and enters the next on that same tick. So the screens change together, and a phase's exit() runs on the same
##tick everywhere. With no phases, `finished` fires straight from run(), on the start tick.
##
##The game scene loads a little before the start tick (the lobby waits for every clock to sync first). A Cover child (any CanvasLayer, saved hidden
##so it does not hide game.tscn in the editor) is shown over the world from the moment the game loads until the first phase starts or play begins.

signal phase_changed(phase : MatchPhase) #every peer, when a phase starts. null once the last one has ended
signal finished(tick : int) #every peer, on the tick the last phase ended (or the start tick, with none): play begins on it

@export var apply_delay_ticks : int = 8 #how far ahead the lobby schedules the end of a phase. Should cover the lobby -> client delay

var game : Game #handed to each phase before it starts

var _phases : Array[MatchPhase] = []
var _index : int = -1 #the running phase, -1 before run() and once finished
var _end_ticks : Dictionary = {} #phase index -> the tick it ends on, once the lobby has said so (kept by index: a late peer may hear of the next one early)
var _running : bool = false

@onready var cover : CanvasLayer = get_node_or_null("Cover")


func _ready() -> void:
	if cover != null:
		cover.visible = true #until the first phase, see _hide_cover


##Every peer, on the start tick.
func run(start_tick : int) -> void:
	_phases.clear()
	for child : Node in get_children():
		if child is MatchPhase:
			_phases.append(child)
	_end_ticks.clear()
	_running = true
	if not NetworkTime.on_tick.is_connected(_on_tick):
		NetworkTime.on_tick.connect(_on_tick)
	_start_phase(0, start_tick)


func current_phase() -> MatchPhase:
	return _phases[_index] if _index >= 0 and _index < _phases.size() else null


func is_running() -> bool:
	return _running


##Stops everything without finishing (the game is being unloaded, see NetworkUnloader). The running phase's screen is hidden.
func quiesce() -> void:
	var phase : MatchPhase = current_phase()
	_running = false
	_index = -1
	if NetworkTime.on_tick.is_connected(_on_tick):
		NetworkTime.on_tick.disconnect(_on_tick)
	if phase != null:
		phase.exit()
	hide_cover()


func _exit_tree() -> void:
	if NetworkTime.on_tick.is_connected(_on_tick):
		NetworkTime.on_tick.disconnect(_on_tick)


func _start_phase(index : int, tick : int) -> void:
	_index = index
	var phase : MatchPhase = current_phase()
	if phase == null: #past the last one
		_running = false
		_index = -1
		if NetworkTime.on_tick.is_connected(_on_tick):
			NetworkTime.on_tick.disconnect(_on_tick)
		hide_cover()
		phase_changed.emit(null)
		finished.emit(tick)
		return
	phase.game = game
	phase.started_tick = tick
	phase.enter()
	hide_cover() #after enter(), so the phase's screen is already up: no frame of the world in between
	phase_changed.emit(phase)


##Takes the loading cover away. Called when the first phase starts or play begins (Game calls it too when it skips the phases).
func hide_cover() -> void:
	if cover != null:
		cover.visible = false


func _on_tick(_delta : float, tick : int) -> void:
	if not _running:
		return
	var phase : MatchPhase = current_phase()
	if phase != null and _is_lobby() and not _end_ticks.has(_index) and (tick >= phase.started_tick + phase.duration_ticks() or phase.lobby_is_done(tick)):
		_end_ticks[_index] = tick + apply_delay_ticks
		if not multiplayer.get_peers().is_empty():
			_schedule_end_remote.rpc(_index, _end_ticks[_index])
	while _running and tick >= _end_ticks.get(_index, tick + 1): #(a peer that heard late catches up, through more than one phase if it has to)
		current_phase().exit()
		_start_phase(_index + 1, tick)


func _is_lobby() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


@rpc("authority", "call_remote", "reliable")
func _schedule_end_remote(index : int, tick : int) -> void:
	if _running and index >= _index:
		_end_ticks[index] = tick #a tick that has already passed is caught up on the next one
