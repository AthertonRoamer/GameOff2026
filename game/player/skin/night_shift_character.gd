## Night Shift character visuals (Godot 4), from the sprite kit (https://claude.ai/artifact/3vjw1tkGREJeaXT8mbr5Mc).
## This copy uses the smooth cel-shaded sheets in guard/ (the kit's cel/ folder): pixel_art is off. The sheets are drawn at 176 px per metre,
## so the Skin node is scaled 0.25 to fit the world's 44 px per metre. Add other roles by copying their cel/ folder next to guard/.
## Scene setup: a Node2D with three AnimatedSprite2D children, in this order: Legs, Torso, Full
## (later children draw on top, so the torso covers the hips).
## Copy the sprites folder into res://sprites, pick a role, and call update_visual() every frame.
class_name NightShiftCharacter
extends Node2D

@export var role := "guard"
@export var sprite_root := "res://game/player/skin"
## On for the pixel-art sheets: crisp nearest-neighbour pixels. Off for the smooth cel-shaded sheets.
@export var pixel_art := false

@onready var legs: AnimatedSprite2D = $Legs
@onready var torso: AnimatedSprite2D = $Torso
@onready var full: AnimatedSprite2D = $Full

## How far the torso kicks back when a shot is fired, in the sprite sheets' pixels (the node is scaled 0.25, so a quarter of this in the world).
@export var recoil_px := 8.0
@export var recoil_out_time := 0.05
@export var recoil_back_time := 0.18

## Drawing and holstering the gun: the sheets have no frames between the arms-down and arms-up poses, so the old pose fades out over the new one
## while swelling slightly (draw) or shrinking slightly (holster).
## The shoulder lamp follows the right shoulder through every animation: the sheets' sprites.json carry the shoulder positions per frame (measured from
## the rig, see tools/rig), and the lamp sits this far out from the joint, on the shoulder's surface. In a mirrored torso (a left strafe) it uses the mirrored left shoulder.
@export var draw_time := 0.16
@export var lamp_outward_px := 11.0
@export var lamp_forward_px := -4.0

## Standing still, turning on the spot: the feet stay put until the upper body is this far round, then step to catch up at this speed.
@export var turn_threshold_deg := 70.0
@export var turn_clip_deg := 96.0 #how far the legs_turn sheet turns the body (measured from the Mixamo clip)
@export var turn_clip_time := 1.0 #how long the legs_turn sheet takes at its natural pace (96 degrees in 1 s)
## The turn clip plays at the pace the player is turning at (the torso's turn speed, smoothed), between these multiples of its natural pace:
## a slow turn gives an unhurried step, a fast flick a quick one.
## Moving sideways relative to the torso (within this cosine of straight sideways, 0.5 = 60 degrees either side of it) plays the strafe sheets
## instead of the forward or backward walk and run.
@export var strafe_cone := 0.5
## Changing between movement animations (idle, walk, run, strafe) fades the old pose out over this long, so the change is not a pop.
@export var move_blend_time := 0.14
@export var turn_clip_min_scale := 0.8
@export var turn_clip_max_scale := 3.5
## Playback speed of the idle cycle, which is the breathing (the sheets' idle is 8 frames at 8 fps, a bit quick for a breath).
@export var idle_breath_speed := 0.5

var meta: Dictionary = {}
var dead := false
const GAIT_CYCLES : Array[String] = ["legs_walk", "legs_run", "legs_strafe_walk", "legs_strafe_run", "torso_walk", "torso_run", "torso_walk_aim",
	"torso_strafe_walk", "torso_strafe_walk_aim", "torso_strafe_run"] #12-frame stride cycles that can hand over to each other at the same phase
var _ready_done := false
var _stepping := false #the turn clip is playing
var _stepping_now := false
var _step_t := 0.0 #0 to 1 through the clip
var _step_from := 0.0
var _step_dir := 1.0
var _legs_placed := false
var _torso_turn_speed := 0.0 #radians per second, smoothed
var _recoil_tween: Tween
var _was_aiming := false
var _ghost: AnimatedSprite2D
var _lamp: Node2D


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/sprites.json" % [sprite_root, role]))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name in meta.keys():
		var m: Dictionary = meta[anim_name]
		var tex: Texture2D = load("%s/%s/%s" % [sprite_root, role, m["file"]])
		var size := int(m["frame_size"])
		var cols := int(m["hframes"])
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, m["fps"])
		frames.set_animation_loop(anim_name, m["loop"])
		for i in int(m["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2((i % cols) * size, (i / cols) * size, size, size)
			frames.add_frame(anim_name, at)
	for s in [legs, torso, full]:
		s.sprite_frames = frames
		s.centered = true
		if pixel_art:
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	full.visible = false
	_lamp = torso.get_node_or_null("Lamp") as Node2D
	_play(legs, "legs_idle")
	_play(torso, "torso_idle")
	_ready_done = true


## move_vel: current velocity. aim_dir: direction the player is aiming.
## aiming: aim button held (gun out). running: sprint held (forces holster).
func update_visual(move_vel: Vector2, aim_dir: Vector2, aiming: bool, running: bool, interacting := false) -> void:
	if dead:
		return
	var moving := move_vel.length() > 5.0
	if running:
		aiming = false  # running always holsters
	var drew := aiming != _was_aiming #the draw transition has its own crossfade on the torso
	if drew:
		_was_aiming = aiming
		_start_draw_transition(aiming)

	# sprites are drawn facing up, so add 90 degrees to a direction's angle
	# the torso (and the flashlight on it) always follows the mouse, drawn gun or not; it only falls back to the movement when there is no aim
	var torso_before := torso.rotation
	if aim_dir != Vector2.ZERO:
		torso.rotation = aim_dir.angle() + PI / 2
	elif moving:
		torso.rotation = move_vel.angle() + PI / 2
	# how fast the player is turning (smoothed), which sets how fast the feet's turn clip plays
	var dt := get_process_delta_time()
	if dt > 0.0:
		var instant := absf(angle_difference(torso_before, torso.rotation)) / dt
		var tau := 0.05 if instant > _torso_turn_speed else 0.45 #quick to notice a flick, slow to forget it, so the feet keep up
		_torso_turn_speed = lerpf(_torso_turn_speed, instant, 1.0 - exp(-dt / tau))

	var legs_anim := "legs_idle"
	var strafing := false
	var legs_flip := false
	var side_amount := 0.0 #positive: moving to the character's right
	if moving:
		# which way the player moves relative to where the torso faces: forward and back follow the movement (back plays the walk in reverse),
		# sideways is a strafe: the legs face the torso and the strafe sheet (a right strafe, mirrored for left) plays
		var facing := Vector2.from_angle(torso.rotation - PI / 2)
		var heading := move_vel.normalized()
		var forward_amount := heading.dot(facing)
		side_amount = heading.dot(facing.rotated(PI / 2))
		strafing = absf(forward_amount) < strafe_cone and meta.has("legs_strafe_walk")
		var target_rotation : float
		if strafing:
			legs_anim = "legs_strafe_run" if running and meta.has("legs_strafe_run") else "legs_strafe_walk"
			target_rotation = torso.rotation
			legs_flip = side_amount < 0.0
			legs.speed_scale = 1.0
		else:
			legs_anim = "legs_run" if running else "legs_walk"
			var backwards := forward_amount < 0.0
			target_rotation = (-move_vel if backwards else move_vel).angle() + PI / 2
			legs.speed_scale = -1.0 if backwards else 1.0  # backpedal = walk cycle in reverse
		legs.rotation += angle_difference(legs.rotation, target_rotation) * (1.0 - exp(-dt * 24.0)) #the legs swing round to a new heading rather than snapping
		_stepping = false
		_stepping_now = false
	else:
		# standing still: the feet stay planted while the torso turns, and take a stepping turn once the twist gets too large
		_stepping_now = _update_step_turn(get_process_delta_time())
		legs.speed_scale = idle_breath_speed

	# the upper body: a strafe has its own torso animations (the sheets are a right strafe; a left strafe is the mirror image, and the lamp and
	# muzzle on the torso are separate nodes, so they stay where they are)
	var torso_anim := "torso_idle"
	var torso_strafe := strafing and meta.has("torso_strafe_walk")
	if interacting:
		torso_anim = "torso_interact"
	elif aiming:
		torso_anim = ("torso_strafe_walk_aim" if torso_strafe and meta.has("torso_strafe_walk_aim") else "torso_walk_aim") if moving else "torso_idle_aim"
		torso_strafe = torso_strafe and torso_anim == "torso_strafe_walk_aim"
	elif moving:
		if torso_strafe:
			torso_anim = "torso_strafe_run" if running and meta.has("torso_strafe_run") else "torso_strafe_walk"
		else:
			torso_anim = "torso_run" if running else "torso_walk"
	var torso_flip := torso_strafe and side_amount < 0.0
	torso.speed_scale = idle_breath_speed if torso_anim in ["torso_idle", "torso_idle_aim"] else 1.0 # breathing is a slow idle cycle
	if not _stepping_now: #mid-step the legs hold their own frozen pose
		_play(legs, legs_anim, legs_flip, true)
	_play(torso, torso_anim, torso_flip, not drew)


## Turning on the spot. Still players do not spin their feet with the mouse: the legs stay planted until the torso has twisted more than
## turn_threshold_deg away, then they play the turn clip (legs_turn, a Mixamo turn rendered from the rig): a right turn of turn_clip_deg
## that starts and ends in the standing stance, mirrored for a left turn. The body's own turning is baked into the frames, so the legs node holds
## still while the sheet plays and is turned by turn_clip_deg when it ends. That fixes the turn rate at turn_clip_deg per turn_clip_time. If the
## torso is still far round afterwards, the next clip starts at once.
## Returns true while the clip is playing (the caller must then leave the legs' frame alone).
func _update_step_turn(delta: float) -> bool:
	if not _legs_placed:
		_legs_placed = true
		legs.rotation = torso.rotation
		return false
	if _stepping:
		var natural_speed := deg_to_rad(turn_clip_deg) / turn_clip_time
		var pace := clampf(_torso_turn_speed / natural_speed, turn_clip_min_scale, turn_clip_max_scale)
		_step_t = minf(_step_t + delta / turn_clip_time * pace, 1.0)
		legs.frame = roundi(_step_t * (legs.sprite_frames.get_frame_count("legs_turn") - 1))
		if _step_t < 1.0:
			return true
		_fade_copy(legs, 0.14) #the last frame of the clip fades into the idle pose (done here, before the legs are turned, so _play must not fade again)
		legs.animation = "legs_idle"
		_stepping = false
		legs.flip_h = false
		legs.rotation = _step_from + _step_dir * deg_to_rad(turn_clip_deg)
		return false
	var twist := angle_difference(legs.rotation, torso.rotation)
	if absf(twist) <= deg_to_rad(turn_threshold_deg) or not legs.sprite_frames.has_animation("legs_turn"):
		return false
	_fade_copy(legs, 0.12) #the idle pose fades into the first frame of the clip
	_stepping = true
	_step_t = 0.0
	_step_dir = signf(twist)
	_step_from = legs.rotation
	legs.flip_h = _step_dir < 0.0 #the clip is a right turn, a left turn is its mirror image
	legs.animation = "legs_turn"
	legs.offset = _offset("legs_turn")
	legs.stop()
	legs.frame = 0
	return true


## A frozen copy of a sprite that fades out where it is, to hide the jump between two poses.
func _fade_copy(sprite: AnimatedSprite2D, time: float) -> void:
	if not sprite.visible or sprite.sprite_frames == null:
		return
	var copy := AnimatedSprite2D.new()
	copy.sprite_frames = sprite.sprite_frames
	copy.animation = sprite.animation
	copy.frame = sprite.frame
	copy.centered = true
	copy.offset = sprite.offset
	copy.rotation = sprite.rotation
	copy.flip_h = sprite.flip_h
	copy.texture_filter = sprite.texture_filter
	add_child(copy)
	move_child(copy, sprite.get_index() + 1)
	var tween := create_tween()
	tween.tween_property(copy, "modulate:a", 0.0, time)
	tween.tween_callback(copy.queue_free)


## Keeps the lamp on the shoulder, whatever the torso is doing.
func _process(delta: float) -> void:
	if _lamp == null or not torso.visible or not meta.has(torso.animation):
		return
	var rows: Array = meta[torso.animation].get("shoulders", [])
	if rows.is_empty():
		return
	var row: Array = rows[clampi(torso.frame, 0, rows.size() - 1)]
	var shoulder := Vector2(-float(row[0]), float(row[1])) if torso.flip_h else Vector2(float(row[2]), float(row[3])) #[left x, left y, right x, right y]
	var target := shoulder + Vector2(lamp_outward_px, lamp_forward_px)
	_lamp.position = _lamp.position.lerp(target, 1.0 - exp(-delta * 30.0))


## Called the moment the gun is drawn or put away, before the torso switches to its new animation.
func _start_draw_transition(drawing: bool) -> void:
	if _ghost:
		_ghost.queue_free()
	if torso.visible and torso.sprite_frames != null:
		var ghost := AnimatedSprite2D.new() #a frozen copy of the old pose, on top of the torso
		ghost.sprite_frames = torso.sprite_frames
		ghost.animation = torso.animation
		ghost.frame = torso.frame
		ghost.centered = true
		ghost.offset = torso.offset
		ghost.rotation = torso.rotation
		ghost.flip_h = torso.flip_h
		ghost.texture_filter = torso.texture_filter
		add_child(ghost)
		move_child(ghost, torso.get_index() + 1)
		_ghost = ghost
		var tween := create_tween().set_parallel(true)
		tween.tween_property(ghost, "modulate:a", 0.0, draw_time).set_ease(Tween.EASE_OUT)
		tween.tween_property(ghost, "scale", Vector2.ONE * (1.07 if drawing else 0.94), draw_time).set_ease(Tween.EASE_OUT)
		tween.chain().tween_callback(ghost.queue_free)



## The shot animation, which the sheets do not have: the torso (and the flashlight on it) kicks back along the barrel and eases forward again,
## and the muzzle flash, if the skin has one under the torso, fires. Call it once per shot.
func play_shot() -> void:
	if dead or not torso.visible:
		return
	var back := -Vector2.from_angle(torso.rotation - PI / 2) * recoil_px #the sprites face up, so the barrel points along rotation - 90 degrees
	if _recoil_tween:
		_recoil_tween.kill()
	torso.position = Vector2.ZERO
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(torso, "position", back, recoil_out_time).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(torso, "position", Vector2.ZERO, recoil_back_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var flash := torso.get_node_or_null("Muzzle") as MuzzleFlash
	if flash:
		flash.flash()


func go_down() -> void:
	_show_full("downed")


func revive() -> void:
	dead = false
	full.visible = false
	legs.visible = true
	torso.visible = true


## Dead players stay in the downed pose (add a death effect on top, e.g. fade or tint).
func die() -> void:
	_show_full("downed")
	full.pause()
	dead = true


func _show_full(anim_name: String) -> void:
	full.rotation = torso.rotation
	legs.visible = false
	torso.visible = false
	full.visible = true
	full.play(anim_name)
	full.offset = _offset(anim_name)


## Starts an animation on a sprite. Changing from one animation to another (idle to walk, walk to run, run to strafe...) crossfades: a frozen copy
## of the old pose fades out over move_blend_time, and a change between two gait cycles keeps the stride's phase instead of restarting it.
func _play(s: AnimatedSprite2D, anim_name: String, flip := false, fade := false) -> void:
	if s.animation != anim_name or not s.is_playing():
		var changing := s.animation != anim_name
		var phase := 0.0
		if changing and GAIT_CYCLES.has(s.animation) and GAIT_CYCLES.has(anim_name):
			phase = float(s.frame) / maxf(1.0, s.sprite_frames.get_frame_count(s.animation))
		if changing and fade and move_blend_time > 0.0 and _ready_done:
			_fade_copy(s, move_blend_time) #copies the old pose, flip included
		s.flip_h = flip
		s.offset = _offset(anim_name)
		s.play(anim_name)
		if phase > 0.0:
			s.frame = clampi(int(phase * s.sprite_frames.get_frame_count(anim_name)), 0, s.sprite_frames.get_frame_count(anim_name) - 1)
	else:
		s.flip_h = flip

## Shifts the sprite so the character's position (the hips) sits on the node origin.
func _offset(anim_name: String) -> Vector2:
	var o: Array = meta[anim_name]["godot_offset"]
	return Vector2(o[0], o[1])
