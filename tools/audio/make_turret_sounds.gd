extends SceneTree

# Makes the turrets' sounds: the servo whir of a turning turret (made to loop without a seam: every tone and the gear ticks fit a whole number of times in the
# clip, and the noise's end is blended into its start), a sharp mechanical shot (two takes) and the two-tone beep of a lock-on. Run it from the project folder:
#   Godot_console.exe --headless --path . -s tools/audio/make_turret_sounds.gd
# then import (open the editor, or Godot_console.exe --headless --path . --import). The files land in game/audio/sounds/machines; recorded ones can replace them.

const RATE : int = 22050
const TURN_DIR : String = "res://game/audio/sounds/machines/turret_turn"
const SHOT_DIR : String = "res://game/audio/sounds/machines/turret_shot"
const LOCK_DIR : String = "res://game/audio/sounds/machines/turret_lock"
const TURN_SECONDS : float = 1.0


func _initialize() -> void:
	for dir : String in [TURN_DIR, SHOT_DIR, LOCK_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_save(_turn(), TURN_DIR.path_join("turret_turn_01.wav"))
	_save(_shot(1), SHOT_DIR.path_join("turret_shot_01.wav"))
	_save(_shot(2), SHOT_DIR.path_join("turret_shot_02.wav"))
	_save(_lock(), LOCK_DIR.path_join("turret_lock_01.wav"))
	quit()


func _save(samples : PackedFloat32Array, path : String) -> void:
	var error : Error = _to_wav(samples).save_to_wav(path)
	print("%s %s" % [path, "ok" if error == OK else "FAILED (%d)" % error])


## A servo motor's whine through a gearbox: a high tone and its octave, a buzz of gear teeth, a little hiss.
func _turn() -> PackedFloat32Array:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 311
	var count : int = int(TURN_SECONDS * RATE)
	var blend : int = int(0.15 * RATE)
	var noise : PackedFloat32Array = PackedFloat32Array()
	noise.resize(count + blend)
	var low : float = 0.0
	for n in noise.size():
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.3)
		noise[n] = low
	for n in blend:
		var w : float = float(n) / blend
		noise[n] = noise[n] * w + noise[count + n] * (1.0 - w)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for n in count:
		var t : float = float(n) / RATE
		var whine : float = sin(TAU * 420.0 * t) * 0.35 + sin(TAU * 840.0 * t) * 0.15 + sin(TAU * 1260.0 * t) * 0.05
		var tooth : float = fposmod(t * 60.0, 1.0) #60 teeth a second: a fine ratchet under the whine
		var ticks : float = exp(-tooth * 18.0) * 0.5
		var wobble : float = 1.0 + 0.1 * sin(TAU * 4.0 * t)
		samples[n] = (whine * wobble + ticks * (0.6 + 0.4 * noise[n]) + noise[n] * 0.08)
	return samples


## A clack of the bolt, a dry crack and a short tail of noise: lighter than a pistol, so a burst reads as a machine.
func _shot(variant : int) -> PackedFloat32Array:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var seconds : float = 0.28
	var count : int = int(seconds * RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	var low : float = 0.0
	var pitch : float = 1.0 + 0.06 * (variant - 1)
	for n in count:
		var t : float = float(n) / RATE
		var noise : float = rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.25)
		var crack : float = noise * exp(-t * 55.0)
		var body : float = low * exp(-t * 16.0) * 0.8
		var thump : float = sin(TAU * 140.0 * pitch * t) * exp(-t * 30.0) * 0.7
		var clack : float = sin(TAU * 2300.0 * pitch * t) * exp(-t * 160.0) * 0.5
		samples[n] = (crack + body + thump + clack) * minf(t / 0.0008, 1.0)
	return samples


## Two short rising beeps.
func _lock() -> PackedFloat32Array:
	var beep : float = 0.07
	var gap : float = 0.035
	var seconds : float = beep * 2.0 + gap
	var count : int = int(seconds * RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for n in count:
		var t : float = float(n) / RATE
		var sample : float = 0.0
		if t < beep:
			sample = _square(1500.0 * t) * _envelope(t, beep)
		elif t >= beep + gap:
			var u : float = t - beep - gap
			sample = _square(2000.0 * u) * _envelope(u, beep)
		samples[n] = sample
	return samples


static func _square(phase : float) -> float:
	return sin(TAU * phase) * 0.6 + sin(TAU * phase * 3.0) * 0.2 #a soft square: the fundamental and a little third


static func _envelope(t : float, length : float) -> float:
	return minf(t / 0.004, 1.0) * minf((length - t) / 0.01, 1.0)


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
