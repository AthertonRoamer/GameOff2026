class_name SoundSystem
extends Node

##Plays the game's sounds for the local player. play() takes a SoundDef and where it was made; the AcousticMap works out how far it seems, from which side and how dull
##(round corners, through open and closed doors and walls), and it is played from there on a pool of AudioStreamPlayer2D voices: a dry one (SFX buses: clear,
##muffled or very muffled) and an echo one (the reverb bus). Nothing here is networked: sounds are made by things every peer already sees (the legs' footfalls, a shot
##everyone is told about, a door that changed state), and each peer hears them from where its own player is.
##Tweak the numbers in acoustics.tres, a sound's loudness and reach in its SoundDef, the filters and reverb in audio_bus_layout.tres, then the clips in game/audio/sounds.

signal heard(direction : Vector2, strength : float) ## a sound reached the listener from this direction (SoundCue shows it)

@export var acoustics : Acoustics
@export var facility : FacilityMap
@export var acoustic_map : AcousticMap
@export_group("Combat")
@export var bullet_wall : SoundDef ## a bullet hits a wall
@export var bullet_flesh : SoundDef ## a bullet hits a player
@export var kill : SoundDef ## a player dies
@export_group("Blood")
@export var blood_splat : SoundDef ## a hit's splash, a body's puddle
@export var blood_drip : SoundDef ## a bleeding player's drop on the floor
@export_group("Doors")
@export var door_open : SoundDef
@export var door_close : SoundDef
@export var door_locked : SoundDef

var listener : Callable = Callable() ## () -> Vector2 (the listener's world position) or null when there is no listener. Set by the scene that knows the local player

var _dry : Array[AudioStreamPlayer2D] = []
var _echo : Array[AudioStreamPlayer2D] = []
var _next : int = 0
var _quiet : bool = true


func _ready() -> void:
	acoustic_map.setup(facility, acoustics)
	for i in acoustics.voices:
		_dry.append(_make_voice())
		_echo.append(_make_voice())
	for door : FacilityDoor in facility.doors:
		door.state_changed.connect(_on_door_changed.bind(door))
	get_tree().create_timer(acoustics.quiet_at_start).timeout.connect(func() -> void: _quiet = false)


func _make_voice() -> AudioStreamPlayer2D:
	var voice : AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.panning_strength = 1.0
	add_child(voice)
	return voice


##A sound made at a world position. own: made by the listener, so a little quieter and from right where they stand.
func play(def : SoundDef, at : Vector2, own : bool = false) -> void:
	if def == null or not listener.is_valid():
		return
	var origin : Variant = listener.call()
	if origin == null:
		return
	var stream : AudioStream = def.pick()
	if stream == null:
		return
	var range_px : float = def.range_m * Acoustics.PX_PER_METRE
	var hearing : AcousticMap.Hearing = acoustic_map.hear(at, origin, range_px)
	if hearing == null:
		return
	if own:
		hearing.distance_px = 0.0
	var loudness : float = pow(1.0 - hearing.distance_px / range_px, def.falloff)
	if loudness < 0.01:
		return
	var seems_at : Vector2 = origin + hearing.direction * hearing.distance_px #the voice sits where the sound seems to come from, the engine fades and pans it from there
	var volume : float = def.volume_db + randf_range(-def.volume_jitter_db, def.volume_jitter_db) + (acoustics.own_sound_db if own else 0.0)
	var pitch : float = randf_range(def.pitch_min, def.pitch_max)
	_start(_voice(_dry), stream, seems_at, volume, pitch, def.falloff, range_px, acoustics.bus_for(hearing.muffle))
	var echo : float = acoustics.echo_of(hearing.room_kind) * def.echo
	if echo > 0.02:
		_start(_voice(_echo), stream, seems_at, volume + acoustics.echo_gain_db + linear_to_db(echo), pitch, def.falloff * acoustics.echo_carry, range_px, acoustics.echo_bus)
	if def.show_cue and not own and not hearing.direction.is_zero_approx():
		heard.emit(hearing.direction, def.cue_strength * loudness)


func _start(voice : AudioStreamPlayer2D, stream : AudioStream, at : Vector2, volume : float, pitch : float, falloff : float, range_px : float, bus : StringName) -> void:
	voice.stream = stream
	voice.global_position = at
	voice.volume_db = volume
	voice.pitch_scale = pitch
	voice.attenuation = falloff
	voice.max_distance = range_px
	voice.bus = bus
	voice.play()


##A voice that is free, or (all busy) the next in turn, cut off.
func _voice(pool : Array[AudioStreamPlayer2D]) -> AudioStreamPlayer2D:
	for i in pool.size():
		var voice : AudioStreamPlayer2D = pool[(_next + i) % pool.size()]
		if not voice.playing:
			_next = (_next + i + 1) % pool.size()
			return voice
	_next = (_next + 1) % pool.size()
	return pool[_next]


func _on_door_changed(state : FacilityDoor.State, door : FacilityDoor) -> void:
	if _quiet:
		return
	play(door_open if state == FacilityDoor.State.OPEN else (door_locked if state == FacilityDoor.State.LOCKED else door_close), door.global_position)
