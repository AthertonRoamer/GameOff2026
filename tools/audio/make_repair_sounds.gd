extends SceneTree

# Makes the sound of a repair by hand (a shot-down generator or turret, while E is held): strokes of a ratchet wrench, a knock of metal on metal now and
# then, and a little scuffle, made to loop without a seam (every event's tail that runs past the end of the clip is wrapped round onto its start). Run it
# from the project folder:
#   Godot_console.exe --headless --path . -s tools/audio/make_repair_sounds.gd
# then import (open the editor, or Godot_console.exe --headless --path . --import). The file lands in game/audio/sounds/machines/repair; a recorded one can replace it.

const RATE : int = 22050
const DIR : String = "res://game/audio/sounds/machines/repair"
const SECONDS : float = 2.4


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var error : Error = _to_wav(_repair()).save_to_wav(DIR.path_join("repair_01.wav"))
	print("%s %s" % [DIR.path_join("repair_01.wav"), "ok" if error == OK else "FAILED (%d)" % error])
	quit()


func _repair() -> PackedFloat32Array:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 6600
	var count : int = int(SECONDS * RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for stroke : Array in [[0.05, 6, 1.0], [0.62, 5, 0.85], [1.25, 7, 1.0], [1.9, 4, 0.8]]: #ratchet strokes: when, clicks, loudness
		for i in int(stroke[1]):
			_add(samples, float(stroke[0]) + i * 0.055 + rng.randf_range(-0.004, 0.004), _click(rng, float(stroke[2]) * (0.85 + 0.15 * rng.randf())))
	for knock : Array in [[0.47, 1.0, 1.0], [1.68, 0.7, 1.13]]: #metal on metal: when, loudness, pitch
		_add(samples, float(knock[0]), _clank(float(knock[1]), float(knock[2])))
	var low : float = 0.0
	for n in count: #a quiet scuffle under it all (its seam is too soft to hear)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.05)
		var t : float = float(n) / RATE
		samples[n] += low * 0.05 * (0.6 + 0.4 * sin(TAU * t / SECONDS * 3.0))
	return samples


## Adds an event into the clip at a time, wrapping what runs past the end round onto the start.
func _add(samples : PackedFloat32Array, at : float, event : PackedFloat32Array) -> void:
	var start : int = int(at * RATE)
	for i in event.size():
		var n : int = posmod(start + i, samples.size())
		samples[n] += event[i]


## One click of a ratchet's pawl: a sharp tick with a small ring.
func _click(rng : RandomNumberGenerator, loudness : float) -> PackedFloat32Array:
	var count : int = int(0.04 * RATE)
	var event : PackedFloat32Array = PackedFloat32Array()
	event.resize(count)
	var ring : float = rng.randf_range(2900.0, 3400.0)
	for i in count:
		var t : float = float(i) / RATE
		event[i] = (rng.randf_range(-1.0, 1.0) * exp(-t * 700.0) * 0.7 + sin(TAU * ring * t) * exp(-t * 260.0) * 0.4) * loudness
	return event


## A knock of a wrench on a steel casing: a few partials that do not fit together (a metal sound), dying away.
func _clank(loudness : float, pitch : float) -> PackedFloat32Array:
	var count : int = int(0.45 * RATE)
	var event : PackedFloat32Array = PackedFloat32Array()
	event.resize(count)
	var partials : Array = [[620.0, 1.0, 9.0], [1190.0, 0.6, 12.0], [1870.0, 0.45, 16.0], [2730.0, 0.3, 22.0]] #Hz, strength, how fast it dies
	for i in count:
		var t : float = float(i) / RATE
		var sample : float = 0.0
		for p : Array in partials:
			sample += sin(TAU * float(p[0]) * pitch * t) * float(p[1]) * exp(-t * float(p[2]))
		event[i] = sample * 0.5 * loudness * minf(t / 0.0006, 1.0)
	return event


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
