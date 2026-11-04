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

var meta: Dictionary = {}
var dead := false


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
	_play(legs, "legs_idle")
	_play(torso, "torso_idle")


## move_vel: current velocity. aim_dir: direction the player is aiming.
## aiming: aim button held (gun out). running: sprint held (forces holster).
func update_visual(move_vel: Vector2, aim_dir: Vector2, aiming: bool, running: bool, interacting := false) -> void:
	if dead:
		return
	var moving := move_vel.length() > 5.0
	if running:
		aiming = false  # running always holsters

	var legs_anim := "legs_idle"
	if moving:
		legs_anim = "legs_run" if running else "legs_walk"

	var torso_anim := "torso_idle"
	if interacting:
		torso_anim = "torso_interact"
	elif aiming:
		torso_anim = "torso_walk_aim" if moving else "torso_idle_aim"
	elif moving:
		torso_anim = "torso_run" if running else "torso_walk"

	# sprites are drawn facing up, so add 90 degrees to a direction's angle
	if aiming and aim_dir != Vector2.ZERO:
		torso.rotation = aim_dir.angle() + PI / 2
	elif moving:
		torso.rotation = move_vel.angle() + PI / 2

	if moving:
		var backwards := aiming and move_vel.dot(Vector2.from_angle(torso.rotation - PI / 2)) < 0.0
		var leg_dir := -move_vel if backwards else move_vel
		legs.rotation = leg_dir.angle() + PI / 2
		legs.speed_scale = -1.0 if backwards else 1.0  # backpedal = walk cycle in reverse
	else:
		legs.rotation = torso.rotation
		legs.speed_scale = 1.0

	_play(legs, legs_anim)
	_play(torso, torso_anim)


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


func _play(s: AnimatedSprite2D, anim_name: String) -> void:
	if s.animation != anim_name or not s.is_playing():
		s.offset = _offset(anim_name)
		s.play(anim_name)


## Shifts the sprite so the character's position (the hips) sits on the node origin.
func _offset(anim_name: String) -> Vector2:
	var o: Array = meta[anim_name]["godot_offset"]
	return Vector2(o[0], o[1])
