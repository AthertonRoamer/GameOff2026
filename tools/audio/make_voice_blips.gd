extends SceneTree

# Makes the chat voice's syllables: short muted-trombone "wah"s, the sound of someone talking without the words (SpeechBubbles plays one per letter).
# Each is a buzzy tone through a resonant filter that opens and closes (the plunger's wah), with a little downward slide. Run it from the project folder:
#   Godot_console.exe --headless --path . -s tools/audio/make_voice_blips.gd
# then import (open the editor, or Godot_console.exe --headless --path . --import). The files land in game/audio/sounds/voice; recorded ones can replace them.

const RATE : int = 22050
const OUT_DIR : String = "res://game/audio/sounds/voice"

#base pitch (Hz), length (s), how far the filter opens (0 to 1), the slide over the syllable (a ratio)
const VARIANTS : Array = [
	[180.0, 0.11, 0.85, 0.94],
	[205.0, 0.09, 0.70, 0.97],
	[165.0, 0.13, 1.00, 0.92],
	[225.0, 0.08, 0.60, 1.02],
	[190.0, 0.12, 0.90, 0.90],
	[170.0, 0.10, 0.75, 1.04],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for i in VARIANTS.size():
		var v : Array = VARIANTS[i]
		var path : String = OUT_DIR.path_join("wah_%02d.wav" % (i + 1))
		var error : Error = _syllable(v[0], v[1], v[2], v[3]).save_to_wav(path)
		print("%s %s" % [path, "ok" if error == OK else "FAILED (%d)" % error])
	quit()


func _syllable(pitch : float, seconds : float, opening : float, slide : float) -> AudioStreamWAV:
	var count : int = int(seconds * RATE)
	var samples : PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	var phase : float = 0.0
	var low : float = 0.0 #the filter's state (a Chamberlin state variable filter, resonant low-pass)
	var band : float = 0.0
	var damping : float = 1.0 / 3.5 #resonance: a vowel-like peak at the cutoff
	var peak : float = 0.0
	for n in count:
		var t : float = float(n) / count #0 to 1 through the syllable
		var f0 : float = pitch * lerpf(1.0, slide, t) * (1.0 + 0.012 * sin(TAU * 6.0 * n / RATE))
		phase = fposmod(phase + f0 / RATE, 1.0)
		var saw : float = 2.0 * phase - 1.0
		var square : float = 1.0 if phase < 0.5 else -1.0
		var tone : float = saw * 0.7 + square * 0.3 #a brassy buzz
		var cutoff : float = lerpf(320.0, 1500.0, pow(sin(PI * t), 0.8) * opening) #the plunger opens and shuts: wah
		var f : float = 2.0 * sin(PI * cutoff / RATE)
		low += f * band
		var high : float = tone - low - damping * band
		band += f * high
		var envelope : float = minf(t * seconds / 0.012, 1.0) * (1.0 - smoothstep(0.55, 1.0, t))
		samples[n] = low * envelope
		peak = maxf(peak, absf(samples[n]))
	var data : PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	var gain : float = 0.6 / maxf(peak, 0.0001)
	for n in count:
		data.encode_s16(n * 2, clampi(int(samples[n] * gain * 32767.0), -32768, 32767))
	var wav : AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
