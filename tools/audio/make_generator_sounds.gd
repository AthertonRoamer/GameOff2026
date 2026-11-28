extends SceneTree

# Makes the generators' sounds: an engine starting up (a few turns of the starter, then it catches and settles), the starter cranking on a loop (heard while
# someone holds E to start one) and the hum of one running, the loops made to loop
# without a seam (every tone fits a whole number of times in the clip, and the noise's end is blended into its start). Run it from the project folder:
#   Godot_console.exe --headless --path . -s tools/audio/make_generator_sounds.gd
# then import (open the editor, or Godot_console.exe --headless --path . --import). The files land in game/audio/sounds/machines; recorded ones can replace them
# (keep the hum's .import set to loop: edit/loop_mode=2).

const RATE : int = 22050
const START_DIR : String = "res://game/audio/sounds/machines/generator_start"
const HUM_DIR : String = "res://game/audio/sounds/machines/generator_hum"
const CRANK_DIR : String = "res://game/audio/sounds/machines/generator_crank"
const HUM_SECONDS : float = 2.0
const CRANK_TURN_SECONDS : float = 0.22 #one turn of the starter (the same as in a start)
const CRANK_TURNS : int = 4 #turns in the looped crank
const FIRING_HZ : float = 27.5 #the engine's beat once running: 55 strokes a second, two to a beat


func _initialize() -> void:
	for dir : String in [START_DIR, HUM_DIR, CRANK_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_save(_start(1), START_DIR.path_join("generator_start_01.wav"))
	_save(_start(2), START_DIR.path_join("generator_start_02.wav"))
	_save(_hum(), HUM_DIR.path_join("generator_hum_01.wav"))
	_save(_crank(), CRANK_DIR.path_join("generator_crank_01.wav"))
	quit()


func _save(samples : PackedFloat32Array, path : String) -> void:
	var error : Error = _to_wav(samples).save_to_wav(path)
	print("%s %s" % [path, "ok" if error == OK else "FAILED (%d)" % error])


## The engine at a beat (Hz): a rough, buzzy pulse train with a little low thump, and the hiss of the exhaust.
static func _engine(phase : float, noise : float) -> float:
	var stroke : float = fposmod(phase * 2.0, 1.0)
	var pulse : float = exp(-stroke * 7.0) * 2.0 - 0.6 #each stroke: a sharp rise and a quick decay
	var thump : float = sin(TAU * phase)
	return pulse * 0.55 + thump * 0.35 + noise * 0.18


func _start(variant : int) -> PackedFloat32Array:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4100 + variant
	var cranks : int = 2 + variant #turns of the starter before it catches
	var crank_seconds : float = 0.22
	var catch_at : float = cranks * crank_seconds + 0.05
	var seconds : float = catch_at + 1.5
	var count : int = int(seconds * RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	var phase : float = 0.0
	var low : float = 0.0
	for n in count:
		var t : float = float(n) / RATE
		var noise : float = rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.08) #a darker noise, for the engine's breath
		var sample : float = 0.0
		if t < catch_at: #the starter: a whirring grind that rises and falls with each turn
			var turn : float = fposmod(t / crank_seconds, 1.0)
			var effort : float = sin(PI * turn)
			phase += (9.0 + 5.0 * effort) / RATE
			sample = _engine(phase, low) * 0.45 * (0.4 + 0.6 * effort) + sin(TAU * t * 310.0) * 0.06 * effort
		else: #it catches: the beat climbs to a run and settles, louder at first, then down to the level of the hum
			var since : float = t - catch_at
			var rev : float = 1.0 - exp(-since * 3.0)
			var beat : float = lerpf(11.0, FIRING_HZ, rev) * (1.0 + 0.12 * exp(-since * 2.0) * sin(since * 9.0))
			phase += beat / RATE
			var level : float = lerpf(0.7, 0.55, rev) + 0.35 * exp(-pow(since - 0.35, 2.0) * 18.0)
			sample = _engine(phase, low) * level
		samples[n] = sample * minf(t / 0.01, 1.0) * minf((seconds - t) / 0.4, 1.0)
	return samples


## The starter turning the engine over without it catching: the whirring grind of a start's first part, played on a loop while E is held. Every turn is
## the same (the beat is worked out from the time in the turn, and fits exactly 3 strokes a turn), the whine fits whole cycles in the clip, and the noise's
## end is blended into its start, so the loop has no seam.
func _crank() -> PackedFloat32Array:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5200
	var seconds : float = CRANK_TURN_SECONDS * CRANK_TURNS
	var count : int = int(seconds * RATE)
	var blend : int = int(0.12 * RATE)
	var noise : PackedFloat32Array = PackedFloat32Array()
	noise.resize(count + blend)
	var low : float = 0.0
	for n in noise.size():
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.08)
		noise[n] = low
	for n in blend:
		var w : float = float(n) / blend
		noise[n] = noise[n] * w + noise[count + n] * (1.0 - w)
	var base : float = 3.0 / CRANK_TURN_SECONDS - 10.0 / PI #beats a second at the slowest, so a turn holds exactly 3 (with the 5 more at its hardest)
	var whine_hz : float = round(310.0 * seconds) / seconds #the starter motor's whine, a whole number of cycles in the loop
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for n in count:
		var t : float = float(n) / RATE
		var in_turn : float = fposmod(t, CRANK_TURN_SECONDS)
		var effort : float = sin(PI * in_turn / CRANK_TURN_SECONDS)
		var phase : float = base * in_turn + 5.0 * CRANK_TURN_SECONDS / PI * (1.0 - cos(PI * in_turn / CRANK_TURN_SECONDS)) #the beat, summed over the turn
		samples[n] = _engine(phase, noise[n]) * 0.45 * (0.4 + 0.6 * effort) + sin(TAU * whine_hz * t) * 0.06 * effort
	return samples


func _hum() -> PackedFloat32Array:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var count : int = int(HUM_SECONDS * RATE)
	var blend : int = int(0.25 * RATE)
	var noise : PackedFloat32Array = PackedFloat32Array()
	noise.resize(count + blend)
	var low : float = 0.0
	for n in noise.size():
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.08)
		noise[n] = low
	for n in blend: #the noise's end runs into its start, so the loop has no seam
		var w : float = float(n) / blend
		noise[n] = noise[n] * w + noise[count + n] * (1.0 - w)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for n in count:
		var t : float = float(n) / RATE
		var phase : float = FIRING_HZ * t #(27.5 Hz fits 55 times in 2 s: the beat loops too)
		var electric : float = sin(TAU * 110.0 * t) * 0.12 + sin(TAU * 220.0 * t) * 0.05 #the alternator's whine
		var wobble : float = 1.0 + 0.08 * sin(TAU * 1.5 * t) #a slow unevenness, 3 times round in the loop
		samples[n] = (_engine(phase, noise[n] * 3.0) * 0.6 + electric) * wobble
	return samples


func _to_wav(samples : PackedFloat32Array) -> AudioStreamWAV:
	var peak : float = 0.0001
	for sample in samples:
		peak = maxf(peak, absf(sample))
	var gain : float = 0.7 / peak
	var data : PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for n in samples.size():
		data.encode_s16(n * 2, clampi(int(samples[n] * gain * 32767.0), -32768, 32767))
	var wav : AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
