extends SceneTree

# Makes the consoles' beeps, heard round a console when a change made from it is accepted: a short rising chirp for something that now takes power (a door
# shut, a light, camera or turret switched on) and a short falling one for something that frees it. Run it from the project folder:
#   Godot_console.exe --headless --path . -s tools/audio/make_console_sounds.gd
# then import (open the editor, or Godot_console.exe --headless --path . --import). The files land in game/audio/sounds/machines; recorded ones can replace them.

const RATE : int = 22050
const ON_DIR : String = "res://game/audio/sounds/machines/console_beep_on"
const OFF_DIR : String = "res://game/audio/sounds/machines/console_beep_off"
const NOTE_SECONDS : float = 0.045
const GAP_SECONDS : float = 0.018


func _initialize() -> void:
	for dir : String in [ON_DIR, OFF_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_save(_chirp([1760.0, 2350.0]), ON_DIR.path_join("console_beep_on_01.wav"))
	_save(_chirp([1570.0, 1180.0]), OFF_DIR.path_join("console_beep_off_01.wav"))
	quit()


func _save(samples : PackedFloat32Array, path : String) -> void:
	var error : Error = _to_wav(samples).save_to_wav(path)
	print("%s %s" % [path, "ok" if error == OK else "FAILED (%d)" % error])


## Two short notes, one after the other, in a soft square tone (a little electronic, like a panel's speaker).
func _chirp(notes : Array) -> PackedFloat32Array:
	var seconds : float = NOTE_SECONDS * notes.size() + GAP_SECONDS * (notes.size() - 1)
	var count : int = int(seconds * RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for n in count:
		var t : float = float(n) / RATE
		var note : int = int(t / (NOTE_SECONDS + GAP_SECONDS))
		var u : float = t - note * (NOTE_SECONDS + GAP_SECONDS)
		if note >= notes.size() or u > NOTE_SECONDS:
			continue
		var hz : float = notes[note]
		var envelope : float = minf(u / 0.003, 1.0) * minf((NOTE_SECONDS - u) / 0.008, 1.0)
		samples[n] = (sin(TAU * hz * u) * 0.65 + sin(TAU * hz * 3.0 * u) * 0.15) * envelope
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
