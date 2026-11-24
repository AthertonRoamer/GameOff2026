extends SceneTree

# Decodes an mp3 into a wav (Python's standard library cannot) by playing it into a recording bus. Run it from the project folder:
#   Godot_console.exe --headless --path . -s tools/audio/decode_mp3.gd -- <in.mp3> <out.wav> <seconds, at least as long as the clip>
# (Used by prepare_role_sounds.py for the pistol's reload.)

var _record : AudioEffectRecord
var _player : AudioStreamPlayer
var _seconds : float = 0.0
var _out : String
var _length : float


func _initialize() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- <in.mp3> <out.wav> <seconds>")
		quit(1)
		return
	_out = args[1]
	_length = float(args[2])
	AudioServer.add_bus()
	var bus : int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "Record")
	_record = AudioEffectRecord.new()
	_record.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, _record)
	var stream := AudioStreamMP3.new()
	stream.data = FileAccess.get_file_as_bytes(args[0])
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.bus = "Record"
	root.add_child(_player)


func _process(delta : float) -> bool:
	if _seconds == 0.0: #(playing starts once the player is in the tree)
		_record.set_recording_active(true)
		_player.play()
	_seconds += delta
	if _seconds > _length:
		_record.set_recording_active(false)
		_record.get_recording().save_to_wav(_out)
		quit()
	return false
