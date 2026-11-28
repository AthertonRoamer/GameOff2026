class_name SoundSystem
extends Node

##Plays the game's sounds for the local player. play() takes a SoundDef and where it was made; the AcousticMap works out how far it seems, from which side and how dull
##(round corners, through open and closed doors and walls), and it is played from there on a pool of AudioStreamPlayer2D voices: a dry one (SFX buses: clear,
##muffled or very muffled) and an echo one (the reverb bus). Nothing here is networked: sounds are made by things every peer already sees (the legs' footfalls, a shot
##everyone is told about, a door that changed state), and each peer hears them from where its own player is.
##Tweak the numbers in acoustics.tres, a sound's loudness and reach in its SoundDef, the filters and reverb in audio_bus_layout.tres, then the clips in game/audio/sounds.

const OWN_RADIUS_PX : float = 24.0 ## a sound this close to the listener comes from their own player: it is heard, but gives no cue

signal heard(direction : Vector2, strength : float) ## a sound reached the listener from this direction (SoundCue shows it)

@export var acoustics : Acoustics
@export var facility : FacilityMap
@export var acoustic_map : AcousticMap
@export_group("Combat")
@export var bullet_wall : SoundDef ## a bullet hits a wall
@export var bullet_ricochet : SoundDef ## a bullet hits a wall close to a player
@export var bullet_flesh : SoundDef ## a bullet hits a player
@export var kill : SoundDef ## a player dies
@export_group("Blood")
@export var blood_splat : SoundDef ## a hit's splash, a body's puddle
@export var blood_drip : SoundDef ## a bleeding player's drop on the floor
@export_group("Doors")
@export var door_open : SoundDef
@export var door_close : SoundDef
@export var door_locked : SoundDef
@export_group("Machines")
@export var generator_crank : SoundDef ## a generator's starter grinding: looped while someone holds E to start it (see on_generator_work)
@export var repair : SoundDef ## tools at work: looped while someone holds E to repair a shot-down generator or turret (see on_repair)
@export var generator_start : SoundDef ## a generator's engine starting up (also a portable one put down)
@export var generator_hum : SoundDef ## a running generator's hum: looped for as long as it runs (see set_hum), heard through the map like any sound
@export var turret_turn : SoundDef ## a turret's servo whir: looped while it turns (see TurretSystem), silent while it stands still
@export var turret_shot : SoundDef ## one shot of a turret
@export var turret_lock : SoundDef ## a turret locking on to an intruder, just before it fires (none: the lock-on is silent)
@export_group("Consoles")
@export var console_beep_on : SoundDef ## a console accepting a change that takes power (a door shut, a light, camera or turret switched on)
@export var console_beep_off : SoundDef ## a console accepting a change that frees power (a door opened, something switched off)
@export_group("Voice")
@export var chat_voice : SoundDef ## one syllable of a chat message said aloud, played once per letter (SpeechBubbles): its range_m is also how far the words are seen

var listener : Callable = Callable() ## () -> Vector2 (the listener's world position) or null when there is no listener. Set by the scene that knows the local player

var _dry : Array[AudioStreamPlayer2D] = []
var _echo : Array[AudioStreamPlayer2D] = []
var _next : int = 0
var _quiet : bool = true
var _hums : Dictionary = {} #key -> {"def", "at", "voice"}: the looping sounds (running generators)
var _hum_clock : float = 0.0

const HUM_UPDATE_SECONDS : float = 0.2 #how often a hum's loudness and direction are worked out again (they follow the listener)


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


##A sound made at a world position. own: made by the listener, so a little quieter and from right where they stand. cue: false for a sound that must not show a marker (the impact of the listener's own shot).
##Returns how loud it was heard, 0 (not at all) to 1.
func play(def : SoundDef, at : Vector2, own : bool = false, cue : bool = true) -> float:
	if def == null or not listener.is_valid():
		return 0.0
	var origin : Variant = listener.call()
	if origin == null:
		return 0.0
	var stream : AudioStream = def.pick()
	if stream == null:
		return 0.0
	var range_px : float = def.range_m * Acoustics.PX_PER_METRE
	var hearing : AcousticMap.Hearing = acoustic_map.hear(at, origin, range_px)
	if hearing == null:
		return 0.0
	if own:
		hearing.distance_px = 0.0
	var loudness : float = pow(1.0 - hearing.distance_px / range_px, def.falloff)
	if loudness < 0.01:
		return 0.0
	var seems_at : Vector2 = origin + hearing.direction * hearing.distance_px #the voice sits where the sound seems to come from, the engine fades and pans it from there
	var volume : float = def.volume_db + randf_range(-def.volume_jitter_db, def.volume_jitter_db) + (acoustics.own_sound_db if own else 0.0)
	var pitch : float = randf_range(def.pitch_min, def.pitch_max)
	_start(_voice(_dry), stream, seems_at, volume, pitch, def.falloff, range_px, acoustics.bus_for(hearing.muffle))
	var echo : float = acoustics.echo_of(hearing.room_kind) * def.echo
	if echo > 0.02:
		_start(_voice(_echo), stream, seems_at, volume + acoustics.echo_gain_db + linear_to_db(echo), pitch, def.falloff * acoustics.echo_carry, range_px, acoustics.echo_bus)
	var from_listener : bool = own or at.distance_to(origin) < OWN_RADIUS_PX #(a hit, a bleed or a death of the listener's own player is not a cue to look somewhere else)
	if def.show_cue and cue and not from_listener and not hearing.direction.is_zero_approx():
		heard.emit(hearing.direction, def.cue_strength * loudness)
	return loudness


##How loud this sound would be heard if it were made here now, 0 (not at all) to 1, without playing it. own: made by the listener.
func audibility(def : SoundDef, at : Vector2, own : bool = false) -> float:
	if def == null or not listener.is_valid():
		return 0.0
	var origin : Variant = listener.call()
	if origin == null:
		return 0.0
	if own:
		return 1.0
	var range_px : float = def.range_m * Acoustics.PX_PER_METRE
	var hearing : AcousticMap.Hearing = acoustic_map.hear(at, origin, range_px)
	if hearing == null:
		return 0.0
	var loudness : float = pow(1.0 - hearing.distance_px / range_px, def.falloff)
	return loudness if loudness >= 0.01 else 0.0


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


##A machine started or stopped running (PowerGrid.generator_switched, on every peer): its hum comes and goes, and a start is heard as the engine starting up.
func on_machine(key : String, at : Vector2, running : bool, announce : bool) -> void:
	if running and announce and not _quiet:
		play(generator_start, at)
	set_hum(key, generator_hum if running else null, at)


##Someone began or stopped holding E on a generator (PowerGrid.generator_worked, on every peer): its starter grinds while it is being started, and
##a repair is heard while it is being repaired.
func on_generator_work(key : String, at : Vector2, work : int) -> void:
	set_hum("crank:" + key, generator_crank if work == PowerGrid.Work.CRANK and not _quiet else null, at)
	on_repair("repair:" + key, at, work == PowerGrid.Work.REPAIR)


##A console beeped as a change made from it was accepted (UtilityConsoles.beeped, on every peer): heard round the console.
func on_console_beep(at : Vector2, powered : bool) -> void:
	var def : SoundDef = console_beep_on if powered else console_beep_off
	if def != null and not _quiet:
		play(def, at)


##Someone began or stopped repairing something by hand (a generator, a turret: key names it), on every peer: it is heard while they work.
func on_repair(key : String, at : Vector2, repairing : bool) -> void:
	set_hum(key, repair if repairing and not _quiet else null, at)


##A sound looped at a world position until it is set to null (key names it: one hum per key). It is heard the way play() hears a sound, from where the listener is
##now, worked out again every HUM_UPDATE_SECONDS; out of earshot the loop is paused.
func set_hum(key : String, def : SoundDef, at : Vector2) -> void:
	if def == null:
		if _hums.has(key):
			(_hums[key]["voice"] as Node).queue_free()
			_hums.erase(key)
		return
	if _hums.has(key):
		_hums[key]["at"] = at
		return
	var stream : AudioStream = _looped(def.pick())
	if stream == null:
		return
	var voice : AudioStreamPlayer2D = _make_voice()
	voice.stream = stream
	voice.volume_db = -80.0
	_hums[key] = {"def": def, "at": at, "voice": voice}
	_update_hum(_hums[key])


func hum_count() -> int:
	return _hums.size()


func _process(delta : float) -> void:
	if _hums.is_empty():
		return
	_hum_clock -= delta
	if _hum_clock > 0.0:
		return
	_hum_clock = HUM_UPDATE_SECONDS
	for key : String in _hums:
		_update_hum(_hums[key])


func _update_hum(hum : Dictionary) -> void:
	var voice : AudioStreamPlayer2D = hum["voice"]
	var def : SoundDef = hum["def"]
	var origin : Variant = listener.call() if listener.is_valid() else null
	var range_px : float = def.range_m * Acoustics.PX_PER_METRE
	var at : Vector2 = hum["at"]
	var hearing : AcousticMap.Hearing = null
	if origin != null and (origin as Vector2).distance_to(at) <= range_px: #(no path is looked for to a machine further off than the sound can carry)
		hearing = acoustic_map.hear(at, origin, range_px)
	if hearing == null or hearing.distance_px >= range_px:
		if voice.playing:
			voice.stream_paused = true
		return
	voice.global_position = origin + hearing.direction * hearing.distance_px
	voice.volume_db = def.volume_db
	voice.attenuation = def.falloff
	voice.max_distance = range_px
	voice.bus = acoustics.bus_for(hearing.muffle)
	if not voice.playing:
		voice.pitch_scale = randf_range(def.pitch_min, def.pitch_max)
		voice.play(randf() * maxf(voice.stream.get_length() - 0.05, 0.0)) #(two generators started together do not hum in step)
	voice.stream_paused = false


##A copy of a clip that loops from end to start (a WAV clip; anything else is used as it is, looping if it already does).
static func _looped(stream : AudioStream) -> AudioStream:
	var wav : AudioStreamWAV = stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED or not (wav.format == AudioStreamWAV.FORMAT_16_BITS or wav.format == AudioStreamWAV.FORMAT_8_BITS):
		return stream #(already looping: the hum clips are imported to loop, see their .import)
	var copy : AudioStreamWAV = wav.duplicate()
	var bytes_per_frame : int = (2 if copy.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if copy.stereo else 1)
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = copy.data.size() / bytes_per_frame
	return copy
