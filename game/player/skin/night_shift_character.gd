class_name NightShiftCharacter
extends Node2D

## What a player looks like, and how it moves: the director of the skin. Drawing is done by three AnimatedSprite2D children, in this order (later children draw on
## top, so the torso covers the hips): Legs, Torso and, for a body on the floor, Full. The sheets are rendered in Blender (tools/rig), cut into `sprite_frames`
## and described by `sprite_data` (sprites.json: per sheet its offset, scale and the shoulder positions); SkinFrames makes them. They are drawn at 176 px per
## metre, so the Skin node is scaled 0.25 to fit the world's 44. Call update_visual() every frame.
##
## The skin is made of nodes: this script (walking, aiming, drawing the gun), SkinHitReaction (flinch and blood), SkinDeath (the fall) and, under the Torso,
## the shoulder lamp with the flashlight, and the muzzle flash.
##
## The legs have three directions of walk and run, timed to the same stride, so one sheet hands over to the next at the same frame with no fade: forward
## (legs_walk / legs_run), sideways (legs_side_walk / legs_side_run, a step to the right, mirrored for the left) and backwards (legs_back / legs_back_run). Which
## one plays depends on the angle between the aim and the movement: within 45 degrees of the aim is forward, 45 to 135 sideways, past 135 backwards. Each sheet is
## turned so its stride runs along the way the player really moves, so the feet never slide sideways across the floor, and the hips (which each sheet carries)
## stay within 45 degrees of the torso. The upper body has the same set of sheets, and between idle and a gait, and between gaits, there are transitions
## rendered in Blender (see _request).

@export var sprite_frames : SpriteFrames
@export_file("*.json") var sprite_data : String ## the role's sprites.json

@export_group("Gaits")
## Play the Blender-rendered transitions between gaits and for drawing the gun (off: a new gait starts at once).
@export var blend_gaits := true
## Changing between idle and a walk or run where there is no transition sheet fades the old pose out over this long, so the change is not a pop.
@export var move_blend_time := 0.14
## How quickly the legs swing round while the player changes direction inside one of the three directions (per second, exponential). Lower is slower and
## heavier. Changing from one direction to the next turns the legs at once, because the stride stays along the movement.
@export_range(2.0, 40.0) var leg_turn_rate := 6.0
## How far past 45 or 135 degrees the aim and the movement have to go before the legs change direction (back inside by this much to change back), so a
## heading right on the line does not flicker between two sheets.
@export_range(0.0, 20.0) var direction_margin_deg := 8.0
## Playback speed of the idle cycle, which is the breathing (the sheets' idle is 8 frames at 8 fps, a bit quick for a breath).
@export var idle_breath_speed := 0.5

@export_group("Turning on the spot")
## Still players do not spin their feet with the mouse: the feet stay put until the upper body is this far round, then step to catch up.
@export var turn_threshold_deg := 70.0
@export var turn_clip_deg := 96.0 ## how far the legs_turn sheet turns the body (measured from the Mixamo clip)
@export var turn_clip_time := 1.0 ## how long the legs_turn sheet takes at its natural pace (96 degrees in 1 s)
## The turn clip plays at the pace the player is turning at (the torso's turn speed, smoothed), between these multiples of its natural pace:
## a slow turn gives an unhurried step, a fast flick a quick one.
@export var turn_clip_min_scale := 0.8
@export var turn_clip_max_scale := 3.5

@export_group("Gun")
## How far the torso kicks back when a shot is fired, in the sheets' pixels (the node is scaled 0.25, so a quarter of this in the world).
@export var recoil_px := 8.0
@export var recoil_out_time := 0.05
@export var recoil_back_time := 0.18
## Without a draw sheet the gun comes out (or goes away) by the old pose fading out over the new one while swelling slightly (draw) or shrinking (holster).
@export var draw_time := 0.16
## The shoulder lamp follows the right shoulder through every animation (the sheets' sprites.json carry the shoulder positions per frame, measured from the
## rig) and sits this far out from the joint, on the shoulder's surface.
@export var lamp_outward_px := 11.0
@export var lamp_forward_px := -4.0

@onready var legs : AnimatedSprite2D = $Legs
@onready var torso : AnimatedSprite2D = $Torso
@onready var full : AnimatedSprite2D = $Full ## the body on the floor (SkinDeath)
@onready var _hit_reaction : SkinHitReaction = $HitReaction
@onready var _death : SkinDeath = $Death

const GAIT_CYCLES : Array[String] = ["legs_walk", "legs_run", "legs_side_walk", "legs_side_run", "legs_back", "legs_back_run", "torso_walk", "torso_run",
	"torso_side_walk", "torso_side_run", "torso_back", "torso_back_run"] #12-frame stride cycles that hand over to each other at the same phase

var meta : Dictionary = {} ## sprites.json
var dead := false

var _ready_done := false
var _lamp : Node2D
var _recoil_tween : Tween
var _rest_scale : Dictionary = {} #each sprite's scale as the scene has it (a sheet's own "scale" is applied on top)
var _torso_turn_speed := 0.0 #radians per second, smoothed
# the legs
var _direction := 0 #which way the legs step: 0 forward, 1 sideways, 2 backwards (see _direction_for)
var _legs_mirrored := false #the sideways sheet is mirrored (moving to the left)
var _legs_placed := false
var _stepping := false #the turn clip is playing
var _stepping_now := false
var _step_t := 0.0 #0 to 1 through the clip
var _step_from := 0.0
var _step_dir := 1.0
# the gun
var _visual_started := false
var _was_aiming := false
var _held_item := -1 #the inventory slot of the item in the hands (-1 when none is out), so picking another one is noticed
var _draw_mode := "" #"draw", "holster" or "switch" while the torso plays the torso_draw sheet, see _begin_draw
var _ghost : AnimatedSprite2D
# transitions
var _blending : Dictionary = {} #sprite -> the transition it is playing (what it is going to, and where that carries on from), see _request


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(sprite_data))
	for s in [legs, torso, full]:
		s.sprite_frames = sprite_frames
		s.centered = true
	full.visible = false
	_lamp = torso.get_node_or_null("Lamp") as Node2D
	_play(legs, "legs_idle")
	_play(torso, "torso_idle")
	_ready_done = true


## move_vel: current velocity. aim_dir: direction the player is aiming.
## aiming: the gun is out. running: sprint held (forces holster).
func update_visual(move_vel: Vector2, aim_dir: Vector2, aiming: bool, running: bool, interacting := false, held_item := -1) -> void:
	if dead:
		return
	var moving := move_vel.length() > 5.0
	if not _visual_started: #the first call: the gun is simply out or away, it does not come out at the spawn
		_visual_started = true
		_was_aiming = aiming and not running
		_held_item = held_item if _was_aiming else -1
	var forced_away := running #running puts the gun away (and it comes out again when the run stops). The inventory has often put it away already, so aiming is false here
	if running:
		aiming = false  # running always holsters
	if interacting or String(torso.animation).contains("typing"):
		aiming = false #at a console the gun is away, and stays away until the typing has blended out (then it is drawn again, if it was out)
	var drew := aiming != _was_aiming #the draw transition has its own crossfade on the torso
	if drew:
		_was_aiming = aiming
		if forced_away:
			_cancel_draw() #a run puts the gun away with no animation: the run starts at once
		elif not _begin_draw(aiming, false):
			_cancel_draw()
			_start_draw_transition(aiming) #no draw sheet: just a fade
	elif aiming and held_item != _held_item and _held_item != -1 and held_item != -1:
		_begin_draw(true, true) #another item picked up with the gun out: put the first away and draw the next
	_held_item = held_item if aiming else -1

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
	var legs_flip := false
	if moving:
		# which way the player moves relative to where the torso aims decides the sheet; the sheet is then turned so that its stride runs along the movement
		var facing := Vector2.from_angle(torso.rotation - PI / 2)
		var heading := move_vel.normalized()
		var angle := rad_to_deg(facing.angle_to(heading)) #0 is straight ahead, positive to the right
		var previous_direction := _direction
		_direction = _direction_for(absf(angle), _direction)
		var target_rotation : float
		match _direction:
			0: #forward: the sheet faces up, so up is turned onto the movement
				legs_anim = "legs_run" if running else "legs_walk"
				target_rotation = heading.angle() + PI / 2
			1: #sideways: the sheet steps to its right, mirrored for the left; that step is turned onto the movement
				legs_anim = "legs_side_run" if running else "legs_side_walk"
				legs_flip = angle < 0.0
				target_rotation = heading.angle() + (PI if legs_flip else 0.0)
			_: #backwards: the sheet steps down, so down is turned onto the movement
				legs_anim = "legs_back_run" if running else "legs_back"
				target_rotation = heading.angle() - PI / 2
		legs.speed_scale = 1.0
		if _direction != previous_direction or legs_flip != _legs_mirrored:
			legs.rotation += angle_difference(legs.rotation, target_rotation) #a different sheet, the same stride along the movement: turn at once
		else:
			legs.rotation += angle_difference(legs.rotation, target_rotation) * (1.0 - exp(-dt * leg_turn_rate)) #a change of heading within a direction is eased
		_legs_mirrored = legs_flip
		_stepping = false
		_stepping_now = false
	else:
		# standing still: the feet stay planted while the torso turns, and take a stepping turn once the twist gets too large
		_stepping_now = _update_step_turn(get_process_delta_time())
		legs.speed_scale = idle_breath_speed

	# the upper body moves like the legs do: its own sheets for walking forward, sideways (a step to the right, mirrored for the left) and backwards,
	# holstered, at a run, or with the gun out (a run always holsters). The arms swing in step with the legs: same pace, same stride frame.
	var torso_anim := "torso_idle"
	var torso_flip := false
	if interacting:
		torso_anim = "torso_typing" #typing at the console
	elif aiming:
		torso_anim = "torso_idle_aim" #the gun stays up and steady whichever way the legs go: there is no walking-with-the-gun swing
	elif moving:
		if _direction == 1:
			torso_anim = "torso_side_run" if running else "torso_side_walk"
			torso_flip = legs_flip
		elif _direction == 2:
			torso_anim = "torso_back_run" if running else "torso_back"
		else:
			torso_anim = "torso_run" if running else "torso_walk"
	torso.speed_scale = idle_breath_speed if torso_anim in ["torso_idle", "torso_idle_aim"] else 1.0 # breathing is a slow idle cycle
	if not _stepping_now: #mid-step the legs hold their own frozen pose
		_request(legs, legs_anim, legs_flip, true)
	if _draw_mode != "":
		torso.speed_scale = 1.0 #the draw plays at its own pace, whatever the torso was doing
		return
	_request(torso, torso_anim, torso_flip, not drew)


## The gun coming out of the holster (or going back in, played backwards), in the torso_draw sheet: the right hand takes the gun and the arms come up to the aim.
## Picking another item with the gun out puts the gun away and takes it out again (switch). Returns false when the skin has no such sheet.
func _begin_draw(drawing: bool, switching: bool) -> bool:
	if not blend_gaits or not torso.visible or not meta.has("torso_draw") or not torso.sprite_frames.has_animation(&"torso_draw"):
		return false
	_abort_transitions()
	var on_sheet := torso.animation == &"torso_draw" and _draw_mode != ""
	if torso.animation_finished.is_connected(_on_draw_finished):
		torso.animation_finished.disconnect(_on_draw_finished)
	_draw_mode = "switch" if switching else ("draw" if drawing else "holster")
	torso.flip_h = false
	torso.offset = sheet_offset("torso_draw")
	_apply_scale(torso, "torso_draw")
	if drawing and not switching:
		if on_sheet:
			torso.play()
		else:
			torso.play(&"torso_draw")
	elif on_sheet:
		torso.play_backwards()
	else:
		torso.play_backwards(&"torso_draw")
	torso.animation_finished.connect(_on_draw_finished, CONNECT_ONE_SHOT)
	return true


func _on_draw_finished() -> void:
	if _draw_mode == "switch": #the old gun is away: the new one comes out
		_draw_mode = "draw"
		torso.play(&"torso_draw")
		torso.animation_finished.connect(_on_draw_finished, CONNECT_ONE_SHOT)
		return
	if _draw_mode == "holster": #the gun is away and the arms hang: the idle, so a run or a walk can start from it with the transition from idle
		_draw_mode = ""
		torso.offset = sheet_offset("torso_idle")
		_apply_scale(torso, "torso_idle")
		torso.play(&"torso_idle")
		return
	_draw_mode = ""


func _cancel_draw() -> void:
	if torso.animation_finished.is_connected(_on_draw_finished):
		torso.animation_finished.disconnect(_on_draw_finished)
	_draw_mode = ""


## Asks a sprite for an animation. Between two gaits (idle, walk, run, sideways, backwards, and a strafe to the other side) there is a transition rendered in
## Blender (sheets <layer>_tr_<from>_<to>_<frame>, and torso_flip_ for a strafe that changes sides) where the sheets exist: it plays first, then the new gait carries
## on from the frame after it. Anything else (the gun up, interacting, turning on the spot, two gaits without a sheet) starts at once, with a fade where it asked for one.
func _request(s: AnimatedSprite2D, anim_name: String, flip := false, fade := false) -> void:
	var full := anim_name
	if _blending.has(s):
		var t: Dictionary = _blending[s]
		if t["anim"] == full and t["flip"] == flip:
			s.speed_scale = 1.0 #the transition plays at its own pace, not at the idle breathing's
			return
		_cancel_transition(s) #something else was asked for part way through
	if not _begin_transition(s, full, flip):
		_play(s, anim_name, flip, fade)


## The gait an animation is one of ("" for the others: aiming, interacting, turning, a transition itself).
func _gait_of(anim_name: String) -> String:
	var base := anim_name.trim_prefix("legs_").trim_prefix("torso_")
	return base if base in ["idle", "walk", "run", "side_walk", "side_run", "back", "back_run", "typing"] else ""


## Starts the transition from what the sprite shows to `full` drawn the way `flip` says, when there is one. Where in the stride it starts is the nearer of the
## sheets' two (or four, for a strafe changing sides) starting frames. A mirrored sheet shows the other foot at any frame, which is the half cycle in the sums:
## the upper body and legs of a sideways step to the left are the right step's sheets drawn flipped.
func _begin_transition(s: AnimatedSprite2D, full: String, flip: bool) -> bool:
	var from := _gait_of(String(s.animation))
	var to := _gait_of(full)
	if not blend_gaits or from == "" or to == "" or not s.is_playing() and from != "idle":
		return false
	var layer := "torso" if s == torso else "legs"
	var count := s.sprite_frames.get_frame_count(s.animation)
	var half := count / 2
	var sheet := ""
	var draw_flip := false
	var resume := 0
	if from == to:
		if flip == s.flip_h or layer != "torso" or not to.begins_with("side_"):
			return false
		var quarter := count / 4
		var q := roundi(float(s.frame) / quarter) % 4
		sheet = "torso_flip_%s_%d" % ["run" if to == "side_run" else "walk", q]
		draw_flip = s.flip_h
		resume = (q * quarter + 1) % count
	else:
		var from_side := from.begins_with("side_")
		var to_side := to.begins_with("side_")
		if from_side and to_side and flip != s.flip_h:
			return false #a change of side as well as of gait: no sheet for both
		draw_flip = s.flip_h if from_side else (flip if to_side else false)
		var f0 := 0
		if from != "idle":
			var phase := s.frame if (from_side or not draw_flip) else s.frame - half #(a flipped forward or backward sheet starts half a cycle on)
			f0 = (roundi(float(posmod(phase, count)) / half) % 2) * half
		sheet = "%s_tr_%s_%s_%d" % [layer, from, to, f0]
	if not meta.has(sheet) or not s.sprite_frames.has_animation(sheet):
		return false
	var n: int = meta[sheet]["frames"]
	if from != to:
		resume = (int(sheet.get_slice("_", sheet.get_slice_count("_") - 1)) + n + 1 + (half if (not to.begins_with("side_") and draw_flip) else 0)) % count
	_start_blend(s, sheet, draw_flip, full, flip, resume)
	return true


func _start_blend(s: AnimatedSprite2D, sheet: String, draw_flip: bool, full: String, flip: bool, resume: int) -> void:
	_blending[s] = {"anim": full, "flip": flip, "resume": resume, "n": meta[sheet]["frames"]}
	s.flip_h = draw_flip
	s.offset = sheet_offset(sheet, draw_flip)
	_apply_scale(s, sheet)
	s.speed_scale = 1.0
	s.play(sheet)
	s.frame = 0
	s.animation_finished.connect(_end_transition.bind(s), CONNECT_ONE_SHOT)


func _end_transition(s: AnimatedSprite2D) -> void:
	if not _blending.has(s):
		return
	var t: Dictionary = _blending[s]
	_blending.erase(s)
	s.flip_h = t["flip"]
	s.offset = sheet_offset(t["anim"], t["flip"])
	_apply_scale(s, t["anim"])
	s.play(t["anim"])
	if _gait_of(t["anim"]) != "idle":
		s.frame = t["resume"]


## Cut short (something else was asked for): the new gait is shown at the frame the transition had got to.
func _cancel_transition(s: AnimatedSprite2D) -> void:
	if not _blending.has(s):
		return
	if s.animation_finished.is_connected(_end_transition.bind(s)):
		s.animation_finished.disconnect(_end_transition.bind(s))
	var t: Dictionary = _blending[s]
	var count := s.sprite_frames.get_frame_count(t["anim"])
	var reached := posmod(int(t["resume"]) - (int(t["n"]) - s.frame), count)
	_end_transition(s)
	if _gait_of(t["anim"]) != "idle":
		s.frame = reached


func _abort_transitions() -> void:
	for s: AnimatedSprite2D in _blending.keys():
		if s.animation_finished.is_connected(_end_transition.bind(s)):
			s.animation_finished.disconnect(_end_transition.bind(s))
	_blending.clear()


## Which way the legs step (0 forward, 1 sideways, 2 backwards) for an angle between the aim and the movement of 0 to 180 degrees. The lines are at 45
## and 135 degrees; the current direction is kept until the angle is direction_margin_deg past a line.
func _direction_for(angle_deg: float, current: int) -> int:
	var low : float = [0.0, 45.0, 135.0][current] - direction_margin_deg #the current direction's range, a little wider than it is
	var high : float = [45.0, 135.0, 180.0][current] + direction_margin_deg
	if angle_deg >= low and angle_deg <= high:
		return current
	return 0 if angle_deg < 45.0 else (1 if angle_deg <= 135.0 else 2)


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
	legs.offset = sheet_offset("legs_turn", legs.flip_h)
	_apply_scale(legs, "legs_turn")
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
	copy.self_modulate = sprite.self_modulate
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


## Shows or hides the muzzle flash (its star and its burst of light), for a shooter the local player has no line of sight to.
func set_muzzle_seen(seen : bool) -> void:
	var muzzle : Node2D = torso.get_node_or_null("Muzzle") as Node2D
	if muzzle != null:
		muzzle.visible = seen


## How much of the body is drawn, 0 to 1, and how much the light on it brightens it (`light`: what to multiply its colours by, white for none). Only the sprites change
## (their own self_modulate): the lights under the torso (the flashlight, the muzzle flash) keep shining, so a player you cannot see still shows where their light falls.
func set_body_alpha(alpha : float, light : Color = Color.WHITE) -> void:
	for sprite : CanvasItem in [legs, torso, full]:
		sprite.self_modulate = Color(light.r, light.g, light.b, alpha)
	var shadow : CanvasItem = get_node_or_null("Shadow")
	if shadow != null:
		shadow.self_modulate.a = alpha
	if is_instance_valid(_ghost):
		_ghost.self_modulate = Color(light.r, light.g, light.b, alpha)


## Where the middle of a fallen body lies, in the world (the skin's own position while it has not fallen).
func body_position() -> Vector2:
	return _death.landing_here() if dead else global_position


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
		ghost.self_modulate = torso.self_modulate
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

## A hit: a puff of blood and (unless the hit killed) a flinch away from the shot. source_angle_deg is where the shot came from, as in die(): 0 from the front,
## positive from the right, 180 from behind.
func hit(source_angle_deg := 0.0) -> void:
	var away := Vector2.from_angle(torso.rotation - PI / 2.0 + deg_to_rad(source_angle_deg) + PI) #the way the shot was travelling, in the world
	_hit_reaction.react(away, not dead)


## The player dies: the body falls the way the killing shot pushes it and lies there (see SkinDeath). Dying twice keeps the first fall.
func die(source_angle_deg := 0.0) -> void:
	if dead:
		return
	_hit_reaction.cancel()
	dead = true
	_death.fall(source_angle_deg)


func revive() -> void:
	_hit_reaction.cancel()
	dead = false
	_death.rise()


## Called as the skin goes down: whatever transition or draw the upper body was playing is dropped.
func stop_upper_body_blends() -> void:
	_abort_transitions()
	_cancel_draw()


## Starts an animation on a sprite. Changing from one animation to another (idle to walk, walk to run...) crossfades: a frozen copy of the old pose fades
## out over move_blend_time. A change between two stride cycles (walk, run, sideways, backwards) keeps the stride's phase and does not fade: the sheets
## already match.
func _play(s: AnimatedSprite2D, anim_name: String, flip := false, fade := false) -> void:
	if s.animation != anim_name or not s.is_playing():
		var changing := s.animation != anim_name
		var between_cycles := changing and GAIT_CYCLES.has(String(s.animation)) and GAIT_CYCLES.has(anim_name)
		var phase := 0.0
		if between_cycles:
			var old_count := s.sprite_frames.get_frame_count(s.animation)
			phase = float(posmod(s.frame - _mirror_shift(s.animation, s.flip_h, old_count), old_count)) / maxf(1.0, old_count)
		if changing and fade and not between_cycles and move_blend_time > 0.0 and _ready_done:
			_fade_copy(s, move_blend_time) #copies the old pose, flip included
		s.flip_h = flip
		s.offset = sheet_offset(anim_name, flip)
		_apply_scale(s, anim_name)
		s.play(anim_name)
		var count := s.sprite_frames.get_frame_count(anim_name)
		if phase > 0.0 or _mirror_shift(anim_name, flip, count) > 0:
			s.frame = (clampi(int(phase * count), 0, count - 1) + _mirror_shift(anim_name, flip, count)) % count
	else:
		if flip != s.flip_h and _is_side_sheet(anim_name): #the same sideways sheet on the other side: a mirror lifts the other foot
			s.frame = (s.frame + s.sprite_frames.get_frame_count(anim_name) / 2) % s.sprite_frames.get_frame_count(anim_name)
		if flip != s.flip_h:
			s.offset = sheet_offset(anim_name, flip)
		s.flip_h = flip


## How many frames a sideways sheet (legs or torso) is shifted by when it is mirrored: half the cycle, because a mirror image lifts the other foot (and
## swings the other arm) at any moment, and the sheets are timed to lift the left foot at the same frame.
func _mirror_shift(anim_name: StringName, mirrored: bool, frame_count: int) -> int:
	return frame_count / 2 if mirrored and _is_side_sheet(anim_name) else 0


func _is_side_sheet(anim_name: StringName) -> bool:
	return String(anim_name).begins_with("legs_side_") or String(anim_name).begins_with("torso_side_")


## A sheet may be drawn a little smaller than it was rendered ("scale" in sprites.json), on top of the sprite's own scale in the scene.
func _apply_scale(s: AnimatedSprite2D, anim_name: String) -> void:
	if not _rest_scale.has(s):
		_rest_scale[s] = s.scale
	s.scale = _rest_scale[s] * float(meta[anim_name].get("scale", 1.0))


## Shifts the sprite so the character's position (the hips) sits on the node origin.
## Flipped, the sprite is mirrored about its own centre, not about the node origin, so the offset's x is mirrored too: then the hips stay on the origin.
func sheet_offset(anim_name: String, flipped := false) -> Vector2:
	var o: Array = meta[anim_name]["godot_offset"]
	return Vector2(-o[0] if flipped else o[0], o[1])
