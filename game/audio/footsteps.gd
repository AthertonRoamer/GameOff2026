class_name Footsteps
extends Node

##A player's footsteps: a step is made whenever the legs' stride reaches a foot-down frame, so the sound is exactly in time with what is on screen, on every peer,
##with nothing sent over the network. Child of the Player. The game connects `stepped` to the SoundSystem.
##Edit in the scene: the walk and run sounds (SoundDef), and which frames of the 12 frame stride a foot comes down on.

signal stepped(def : SoundDef, at : Vector2)

const WALKS : Array[StringName] = [&"legs_walk", &"legs_side_walk", &"legs_back"]
const RUNS : Array[StringName] = [&"legs_run", &"legs_side_run", &"legs_back_run"]

@export var legs : AnimatedSprite2D
@export var walk : SoundDef
@export var run : SoundDef
@export var step_frames : PackedInt32Array = [0, 6] ## the frames a foot comes down on, in the legs' 12 frame walk and run cycles
@export_range(0.05, 0.5, 0.01, "suffix:s") var min_gap : float = 0.25 ## two steps are never closer than this (a run steps every 0.4 s, a walk every 0.6)

const CYCLE : int = 12 #frames in a walk or run cycle

var _last_step : float = -1.0
var _last_frame : int = -1 #the frame the stride was on before this one, -1 when the legs were not in a gait


var _silent_walk : bool = false #the role's: walking makes no sound
var _run_override : SoundDef #the role's own run sound (a quiet runner)


func _ready() -> void:
	legs.frame_changed.connect(_on_frame_changed)


## The player's role decides how it sounds (a role is public, so every peer hears the same): see Role.silent_walk and Role.run_sound.
func use_role(role : Role) -> void:
	_silent_walk = role != null and role.silent_walk
	_run_override = role.run_sound if role != null else null


##A step is made when the stride runs on to a foot-down frame, or when a gait starts on one. A sheet that hands over to another mid-stride (or is set to a frame) does not
##make a step of its own, which is what made some steps land off the beat.
func _on_frame_changed() -> void:
	var gait : bool = legs.animation in WALKS or legs.animation in RUNS
	var previous : int = _last_frame
	_last_frame = legs.frame if gait else -1
	if not gait or not legs.frame in step_frames:
		return
	var advanced : bool = previous >= 0 and (legs.frame - previous + CYCLE) % CYCLE == 1 #on from the frame before, as the stride plays
	if not advanced and previous != -1:
		return #jumped in at this frame
	var now : float = Time.get_ticks_msec() / 1000.0
	if now - _last_step < min_gap:
		return
	var walking : bool = legs.animation in WALKS
	if walking and _silent_walk:
		return
	_last_step = now
	stepped.emit(walk if walking else (_run_override if _run_override != null else run), (get_parent() as Node2D).global_position)
