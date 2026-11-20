extends SceneTree

## Offline check of the skin's legs (see night_shift_character.gd): forward, sideways and backwards sheets, chosen by the angle between the aim and the
## movement, each turned so its stride runs along the movement, handing over at the same stride frame with no fade:
##   godot --headless --path . --script res://tests/unit/test_skin_locomotion.gd

const SCENE : PackedScene = preload("res://game/player/skin/player_skin.tscn")

var failures : int = 0


func check(condition : bool, what : String) -> void:
	print(("  ok   " if condition else "  FAIL ") + what)
	if not condition:
		failures += 1


func make_skin(blend := false) -> NightShiftCharacter:
	var skin : NightShiftCharacter = SCENE.instantiate()
	skin.blend_gaits = blend #the sheet tests want a gait at once; the transition tests turn the transitions on
	root.add_child(skin)
	await process_frame
	return skin


## Keeps calling update_visual for real time (the transitions play at their own speed, not per frame).
func settle_for(skin : NightShiftCharacter, velocity : Vector2, aim : Vector2, running : bool, seconds : float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		skin.update_visual(velocity, aim, false, running)
		await process_frame


func settle(skin : NightShiftCharacter, velocity : Vector2, aim : Vector2, running : bool = false, frames : int = 300) -> void:
	for _i in frames:
		skin.update_visual(velocity, aim, false, running)
		await process_frame


func _initialize() -> void:
	var probe : NightShiftCharacter = await make_skin()
	for sheet : String in ["legs_walk", "legs_run", "legs_side_walk", "legs_side_run", "legs_back", "legs_back_run", "torso_walk", "torso_run",
			"torso_side_walk", "torso_side_run", "torso_back", "torso_back_run", "torso_idle_aim", "death_front", "death_front_right", "death_right", "death_back_right", "death_back"]:
		check(probe.sprite_frames.has_animation(sheet) and probe.meta.has(sheet), "the skin has %s" % sheet)
		if sheet.begins_with("torso_"):
			check(not (probe.meta[sheet].get("shoulders", []) as Array).is_empty(), "%s has shoulder positions for the lamp" % sheet)
	probe.queue_free()

	#the sheet for each direction (aim up the screen)
	var ways : Array = [[Vector2(0, -1), &"legs_walk", false], [Vector2(1, -4), &"legs_walk", false], [Vector2(1, -0.6), &"legs_side_walk", false],
		[Vector2(1, 0), &"legs_side_walk", false], [Vector2(-1, 0), &"legs_side_walk", true], [Vector2(1, 0.5), &"legs_side_walk", false],
		[Vector2(1, 4), &"legs_back", false], [Vector2(-1, 4), &"legs_back", false], [Vector2(0, 1), &"legs_back", false]]
	for way : Array in ways:
		var skin : NightShiftCharacter = await make_skin()
		skin.update_visual((way[0] as Vector2).normalized() * 200.0, Vector2(0, -1), false, false)
		check(skin.legs.animation == way[1] and skin.legs.flip_h == way[2], "moving %s plays %s%s (%s%s)" % [way[0], way[1], " mirrored" if way[2] else "", skin.legs.animation, " mirrored" if skin.legs.flip_h else ""])
		skin.update_visual((way[0] as Vector2).normalized() * 400.0, Vector2(0, -1), false, true)
		var run_sheet : String = "legs_back_run" if way[1] == &"legs_back" else String(way[1]).replace("walk", "run")
		check(skin.legs.animation == StringName(run_sheet), "running there plays %s (%s)" % [run_sheet, skin.legs.animation])
		skin.queue_free()

	#each sheet is turned so its stride runs along the movement
	var skin : NightShiftCharacter = await make_skin()
	await settle(skin, Vector2(300, 0), Vector2(1, 0)) #moves right, aims right: forward
	check(absf(angle_difference(skin.legs.rotation, PI / 2.0)) < 0.05, "forward: the sheet's up is turned onto the movement (%.0f deg, the torso is at 90)" % rad_to_deg(skin.legs.rotation))
	await settle(skin, Vector2(300, 0), Vector2(0, -1)) #moves right, aims up: sideways to the right
	check(skin.legs.animation == &"legs_side_walk" and not skin.legs.flip_h and absf(angle_difference(skin.legs.rotation, 0.0)) < 0.05, "sideways to the right: the step is turned onto the movement, the hips square to the aim (%.0f deg)" % rad_to_deg(skin.legs.rotation))
	await settle(skin, Vector2(-300, 0), Vector2(0, -1)) #moves left, aims up
	check(skin.legs.animation == &"legs_side_walk" and skin.legs.flip_h and absf(angle_difference(skin.legs.rotation, 0.0)) < 0.05, "sideways to the left: the mirrored sheet already steps left, so the hips stay square to the aim (%.0f deg)" % rad_to_deg(skin.legs.rotation))
	await settle(skin, Vector2(0, 300), Vector2(0, -1)) #moves down, aims up: backwards
	check(skin.legs.animation == &"legs_back" and absf(angle_difference(skin.legs.rotation, 0.0)) < 0.05, "backwards: the hips stay facing the aim (%.0f deg)" % rad_to_deg(skin.legs.rotation))
	var hips_worst : float = 0.0
	for angle : float in range(0, 360, 15): #however the player moves, the hips stay within 45 degrees of the aim (a little more while the legs swing round)
		var velocity : Vector2 = Vector2.from_angle(deg_to_rad(angle)) * 300.0
		await settle(skin, velocity, Vector2(0, -1), false, 400)
		hips_worst = maxf(hips_worst, absf(rad_to_deg(angle_difference(skin.legs.rotation, skin.torso.rotation))))
	check(hips_worst <= 55.0, "all round the compass the hips stay near the aim (worst %.0f deg)" % hips_worst)
	skin.queue_free()

	#a change of sheet keeps the stride, mirrors are half a cycle on, and nothing fades
	skin = await make_skin()
	skin.update_visual(Vector2(0, -300), Vector2(0, -1), false, false)
	skin.legs.frame = 5
	var children : int = skin.get_child_count()
	skin.update_visual(Vector2(0, -400), Vector2(0, -1), false, true)
	check(skin.legs.animation == &"legs_run" and skin.legs.frame == 5, "walk to run keeps the stride (frame %d)" % skin.legs.frame)
	skin.update_visual(Vector2(300, 0), Vector2(0, -1), false, false)
	check(skin.legs.animation == &"legs_side_walk" and skin.legs.frame == 5, "forward to sideways keeps the stride (frame %d)" % skin.legs.frame)
	skin.update_visual(Vector2(-300, 0), Vector2(0, -1), false, false)
	check(skin.legs.animation == &"legs_side_walk" and skin.legs.flip_h and skin.legs.frame == 11, "the mirrored sideways sheet is half a cycle on (frame 5 became %d of 12)" % skin.legs.frame)
	skin.update_visual(Vector2(0, 300), Vector2(0, -1), false, false)
	check(skin.legs.animation == &"legs_back" and not skin.legs.flip_h and skin.legs.frame == 5, "on to backwards: the stride is the same again (frame %d)" % skin.legs.frame)
	check(skin.get_child_count() == children, "no fade copies were made between the stride sheets (%d children)" % skin.get_child_count())
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), false, false)
	check(skin.legs.animation == &"legs_idle", "standing still plays the idle (%s)" % skin.legs.animation)
	skin.queue_free()

	#a heading on the line between two directions does not flicker
	skin = await make_skin()
	var seen : Array[StringName] = []
	for degrees in range(40, 61, 2): #40 to 60 degrees off the aim and back again
		var a : float = deg_to_rad(float(degrees))
		skin.update_visual(Vector2(sin(a), -cos(a)) * 300.0, Vector2(0, -1), false, false)
		seen.append(skin.legs.animation)
	for degrees in range(60, 39, -2):
		var a : float = deg_to_rad(float(degrees))
		skin.update_visual(Vector2(sin(a), -cos(a)) * 300.0, Vector2(0, -1), false, false)
		seen.append(skin.legs.animation)
	var changes : int = 0
	for i in range(1, seen.size()):
		if seen[i] != seen[i - 1]:
			changes += 1
	check(changes == 1, "sweeping across 45 degrees and back changes sheet once, not at every crossing (%d changes)" % changes)
	skin.queue_free()

	#the upper body has a sheet for every direction, holstered, at a run and with the gun out
	var uppers : Array = [ #[movement, aiming, running, torso sheet, mirrored]
		[Vector2(0, -1), false, false, &"torso_walk", false], [Vector2(0, -1), true, false, &"torso_idle_aim", false], [Vector2(0, -1), false, true, &"torso_run", false],
		[Vector2(1, 0), false, false, &"torso_side_walk", false], [Vector2(-1, 0), false, false, &"torso_side_walk", true],
		[Vector2(1, 0), false, true, &"torso_side_run", false], [Vector2(-1, 0), false, true, &"torso_side_run", true],
		[Vector2(1, 0), true, false, &"torso_idle_aim", false], [Vector2(-1, 0), true, false, &"torso_idle_aim", false],
		[Vector2(0, 1), false, false, &"torso_back", false], [Vector2(0, 1), true, false, &"torso_idle_aim", false], [Vector2(0, 1), false, true, &"torso_back_run", false]]
	for upper : Array in uppers:
		skin = await make_skin()
		skin.update_visual((upper[0] as Vector2) * (400.0 if upper[2] else 250.0), Vector2(0, -1), upper[1], upper[2])
		check(skin.torso.animation == upper[3] and skin.torso.flip_h == upper[4], "moving %s%s%s plays %s%s (%s%s)" % [upper[0], ", gun out" if upper[1] else "", ", running" if upper[2] else "", upper[3], " mirrored" if upper[4] else "", skin.torso.animation, " mirrored" if skin.torso.flip_h else ""])
		skin.queue_free()
	skin = await make_skin() #arms and legs swing together: the same frame, and the same after a change of direction
	skin.update_visual(Vector2(0, -250), Vector2(0, -1), false, false)
	for _i in 30:
		skin.update_visual(Vector2(0, -250), Vector2(0, -1), false, false)
		await process_frame
	check(skin.torso.frame == skin.legs.frame, "walking forward, the arms and legs are on the same frame (%d, %d)" % [skin.torso.frame, skin.legs.frame])
	skin.update_visual(Vector2(250, 0), Vector2(0, -1), false, false)
	check(skin.torso.animation == &"torso_side_walk" and skin.torso.frame == skin.legs.frame, "changing to sideways, they still match (%d, %d)" % [skin.torso.frame, skin.legs.frame])
	skin.update_visual(Vector2(-250, 0), Vector2(0, -1), false, false)
	check(skin.torso.flip_h and skin.torso.frame == skin.legs.frame, "and mirrored for the left, they still match (%d, %d)" % [skin.torso.frame, skin.legs.frame])
	skin.update_visual(Vector2(0, 250), Vector2(0, -1), false, false)
	var apart : int = absi(posmod(skin.torso.frame - skin.legs.frame + 6, 12) - 6) #(the swing across starts from the nearest quarter of the stride: up to 2 frames off)
	check(skin.torso.animation == &"torso_back" and not skin.torso.flip_h and apart <= 2, "and backwards, even in the middle of the swing, they still match (%d, %d)" % [skin.torso.frame, skin.legs.frame])
	skin.update_visual(Vector2(0, -250), Vector2(0, -1), false, false)
	skin.queue_free()

	#the other upper body behaviour
	skin = await make_skin()
	skin.update_visual(Vector2(0, -300), Vector2(0, -1), false, false)
	check(skin.torso.animation == &"torso_walk", "walking plays the walk arms (%s)" % skin.torso.animation)
	skin.update_visual(Vector2(0, -300), Vector2(0, -1), true, false)
	check(skin.torso.animation == &"torso_idle_aim", "walking with the gun out holds the gun steady, no walking swing (%s)" % skin.torso.animation)
	skin.update_visual(Vector2(0, -400), Vector2(0, -1), true, true)
	check(skin.torso.animation == &"torso_run", "running holsters the gun (%s)" % skin.torso.animation)
	skin.die()
	check(not skin.legs.visible and not skin.torso.visible and skin.full.visible, "a dead player shows the body only")
	check(skin.full.animation == &"death_front" and skin.full.is_playing() and skin.full.frame == 0, "dying with no direction falls as if shot from the front, from its first frame (%s, frame %d)" % [skin.full.animation, skin.full.frame])
	for _i in 400: #14 frames at 14 fps, a second of real time
		await process_frame
	var last : int = skin.full.sprite_frames.get_frame_count(&"death_front") - 1
	check(skin.full.animation == &"death_front" and not skin.full.is_playing() and skin.full.frame == last, "the fall ends on its last frame and stays there (frame %d of %d)" % [skin.full.frame, last])
	skin.update_visual(Vector2(300, 0), Vector2(0, -1), false, false)
	check(skin.full.animation == &"death_front" and skin.full.frame == last and not skin.legs.visible, "a dead player ignores movement")
	skin.revive()
	check(skin.legs.visible and skin.torso.visible and not skin.full.visible, "a revived player shows the legs and torso again")
	skin.queue_free()

	#the fall depends on where the shot came from (0 front, positive right, negative left, 180 behind); the left is the right mirrored, offset included
	var falls : Array = [[0.0, &"death_front", false], [10.0, &"death_front", false], [-10.0, &"death_front", false], [30.0, &"death_front_right", false], [-30.0, &"death_front_right", true],
		[90.0, &"death_right", false], [-90.0, &"death_right", true], [130.0, &"death_back_right", false], [-130.0, &"death_back_right", true], [170.0, &"death_back", false],
		[-170.0, &"death_back", false], [180.0, &"death_back", false]]
	for fall : Array in falls:
		skin = await make_skin()
		skin.die(fall[0])
		var expected_offset : Vector2 = skin.sheet_offset(String(fall[1]))
		if fall[2]:
			expected_offset.x = -expected_offset.x
		check(skin.full.animation == fall[1] and skin.full.flip_h == fall[2] and skin.full.offset.is_equal_approx(expected_offset), "shot from %.0f degrees: %s%s, offset %s" % [fall[0], fall[1], " mirrored" if fall[2] else "", skin.full.offset])
		var end : Array = skin.meta[fall[1]]["end_center"]
		var carried := Vector2(-end[0] if fall[2] else end[0], end[1]).rotated(skin.full.rotation) #the way the body is carried, in the world
		var away := Vector2.from_angle(skin.torso.rotation - PI / 2.0 + deg_to_rad(fall[0]) + PI) #directly away from the shot
		check(absf(carried.angle_to(away)) < 0.01, "shot from %.0f degrees: the body lands away from the shot (%.1f degrees off)" % [fall[0], rad_to_deg(carried.angle_to(away))])
		var shadow : Sprite2D = skin.get_node("Shadow")
		var rest : Vector2 = shadow.position
		if fall[0] == 90.0:
			await create_timer(2.0).timeout #the fall takes 1.5 seconds; the shadow goes along with the body
			check(shadow.visible and shadow.position.distance_to(rest) > 15.0, "a fallen body has a shadow, under the body and not where the player stood (moved %.0f)" % shadow.position.distance_to(rest))
		skin.revive()
		check(not skin.full.flip_h and skin.legs.visible and shadow.visible and shadow.position.is_equal_approx(rest) and skin.full.position == Vector2.ZERO, "reviving clears the mirror and brings back the legs and the shadow where it was")
		skin.queue_free()
	skin = await make_skin()
	skin.die(90.0)
	skin.die(-90.0) #a second death while down must not start the fall over, or turn the body round
	check(skin.full.animation == &"death_right" and not skin.full.flip_h, "dying twice keeps the first fall")
	skin.queue_free()
	#strafing to the other side swings the upper body across with a transition, then carries on mirrored
	for running : bool in [true, false]:
		skin = await make_skin(true)
		var kind := "run" if running else "walk"
		await settle(skin, Vector2(200, 0), Vector2(0, -1), running, 120) #moving right, facing up: a strafe to the right
		check(skin.torso.animation == StringName("torso_side_%s" % kind) and not skin.torso.flip_h, "strafing right (%s)" % kind)
		skin.update_visual(Vector2(-200, 0), Vector2(0, -1), false, running)
		check(String(skin.torso.animation).begins_with("torso_flip_%s_" % kind) and not skin.torso.flip_h, "reversing the strafe plays the transition, drawn the way the old side was (%s)" % skin.torso.animation)
		var shoulders_ok : bool = skin.meta[skin.torso.animation].has("shoulders") and skin.meta[skin.torso.animation]["shoulders"].size() == 6
		check(shoulders_ok, "the transition carries its shoulders for the lamp")
		await settle(skin, Vector2(-200, 0), Vector2(0, -1), running, 60)
		check(skin.torso.animation == StringName("torso_side_%s" % kind) and skin.torso.flip_h, "then the left strafe carries on (%s, flipped %s)" % [skin.torso.animation, skin.torso.flip_h])
		await settle(skin, Vector2(200, 0), Vector2(0, -1), running, 2)
		check(String(skin.torso.animation).begins_with("torso_flip_%s_" % kind) and skin.torso.flip_h, "and back: the mirrored transition")
		await settle(skin, Vector2(200, 0), Vector2(0, -1), running, 60)
		check(skin.torso.animation == StringName("torso_side_%s" % kind) and not skin.torso.flip_h, "back on the right strafe")
		skin.queue_free()
	#transitions between gaits: from idle, from gait to gait, and back to idle; the new gait carries on afterwards, and nothing fades
	skin = await make_skin(true)
	skin.update_visual(Vector2(0, -250), Vector2(0, -1), false, false)
	check(skin.legs.animation == &"legs_tr_idle_walk_0" and skin.torso.animation == &"torso_tr_idle_walk_0", "starting to walk plays the start (%s, %s)" % [skin.legs.animation, skin.torso.animation])
	await settle_for(skin, Vector2(0, -250), Vector2(0, -1), false, 0.8)
	check(skin.legs.animation == &"legs_walk" and skin.torso.animation == &"torso_walk" and skin.torso.frame == skin.legs.frame or absi(skin.torso.frame - skin.legs.frame) <= 1, "then the walk carries on, arms and legs together (%d, %d)" % [skin.torso.frame, skin.legs.frame])
	skin.update_visual(Vector2(0, -400), Vector2(0, -1), false, true)
	check(skin.torso.animation == &"torso_tr_walk_run_0" or skin.torso.animation == &"torso_tr_walk_run_6", "walk to run swings the arms across (%s)" % skin.torso.animation)
	check(skin.legs.animation == &"legs_run", "the legs change at once (the stride is the same)")
	await settle_for(skin, Vector2(0, -400), Vector2(0, -1), true, 0.8)
	check(skin.torso.animation == &"torso_run", "and the run carries on (%s)" % skin.torso.animation)
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), false, false)
	check(String(skin.legs.animation).begins_with("legs_tr_run_idle_") and String(skin.torso.animation).begins_with("torso_tr_run_idle_"), "stopping plays the stop (%s)" % skin.legs.animation)
	await settle_for(skin, Vector2.ZERO, Vector2(0, -1), false, 0.8)
	check(skin.legs.animation == &"legs_idle" and skin.torso.animation == &"torso_idle", "and settles into the idle (%s, %s)" % [skin.legs.animation, skin.torso.animation])
	skin.update_visual(Vector2(-250, 0), Vector2(0, -1), false, false) #a step to the left from rest: the right step's start, flipped
	check(skin.torso.animation == &"torso_tr_idle_side_walk_0" and skin.torso.flip_h, "starting a step to the left plays the right step's start, flipped (%s)" % skin.torso.animation)
	await settle_for(skin, Vector2(-250, 0), Vector2(0, -1), false, 0.8)
	check(skin.torso.animation == &"torso_side_walk" and skin.torso.flip_h and skin.legs.flip_h, "and the left step carries on")
	skin.update_visual(Vector2(0, -250), Vector2(0, -1), false, false) #from the left step to forward
	check(String(skin.torso.animation).begins_with("torso_tr_side_walk_walk_") and skin.torso.flip_h, "to forward from the left step, the transition is drawn the way the step was (%s)" % skin.torso.animation)
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), false, false) #and stopping in the middle of it cuts it short
	check(String(skin.torso.animation).begins_with("torso_tr_") and not String(skin.torso.animation).begins_with("torso_tr_side_walk_walk_"), "stopping part way through the swing gives way to the stop (%s)" % skin.torso.animation)
	skin.queue_free()
	#drawing and holstering the gun, and picking another item with the gun out
	skin = await make_skin(true)
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), false, false, false, 0)
	check(skin.torso.animation == &"torso_idle", "holstered at the start")
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 0)
	check(skin.torso.animation == &"torso_draw" and skin.torso.is_playing() and skin.torso.frame == 0, "drawing plays the draw (%s)" % skin.torso.animation)
	await create_timer(0.1).timeout
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 0)
	check(skin.torso.animation == &"torso_draw" and skin.torso.frame > 0, "and it keeps playing while asked for the aim (frame %d)" % skin.torso.frame)
	await create_timer(0.6).timeout
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 0)
	await create_timer(0.1).timeout
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 0)
	check(skin.torso.animation == &"torso_idle_aim", "then the gun is up (%s)" % skin.torso.animation)
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 1) #another item picked with the gun out
	check(skin.torso.animation == &"torso_draw" and skin.torso.frame == skin.torso.sprite_frames.get_frame_count(&"torso_draw") - 1, "picking another item puts the gun away first (frame %d)" % skin.torso.frame)
	await create_timer(0.1).timeout
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 1)
	var low_frame : int = skin.torso.frame
	check(low_frame < skin.torso.sprite_frames.get_frame_count(&"torso_draw") - 1, "backwards (frame %d)" % low_frame)
	await create_timer(1.2).timeout
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 1)
	await create_timer(0.1).timeout
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 1)
	check(skin.torso.animation == &"torso_idle_aim", "and the next comes out (%s)" % skin.torso.animation)
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), false, false, false, 1) #H: holster
	check(skin.torso.animation == &"torso_draw" and skin.torso.frame == skin.torso.sprite_frames.get_frame_count(&"torso_draw") - 1, "holstering plays the draw backwards from the aim (frame %d)" % skin.torso.frame)
	await create_timer(0.8).timeout
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), false, false, false, 1)
	await create_timer(0.1).timeout
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), false, false, false, 1)
	check(skin.torso.animation == &"torso_idle", "and the arms hang again (%s)" % skin.torso.animation)
	skin.update_visual(Vector2.ZERO, Vector2(0, -1), true, false, false, 1)
	skin.update_visual(Vector2(0, -400), Vector2(0, -1), true, true, false, 1) #running puts it away with no draw animation
	check(skin.torso.animation != &"torso_draw", "a run puts the gun away with no animation: the run starts at once (%s)" % skin.torso.animation)
	skin.queue_free()
	#a hit: a flinch along the way the shot was travelling and back, with a puff of blood
	skin = await make_skin()
	skin.update_visual(Vector2.ZERO, Vector2.RIGHT, false, false)
	var rest : Vector2 = skin.position
	var children_before : int = skin.get_child_count()
	skin.hit(180.0) #shot from behind a player facing right: travelling right
	await create_timer(skin.get_node("HitReaction").flinch_time * 0.35).timeout
	check(skin.position.x - rest.x > 1.0 and absf(skin.position.y - rest.y) < 1.0, "a hit from behind pushes the skin forward, away from the shot (%s)" % (skin.position - rest))
	check(skin.get_child_count() == children_before + 1, "a hit throws a puff of blood")
	await create_timer(skin.get_node("HitReaction").flinch_time + 0.2).timeout
	check(skin.position.is_equal_approx(rest) and skin.modulate == Color.WHITE, "the flinch ends back at rest")
	await create_timer(0.6).timeout
	check(skin.get_child_count() == children_before, "the puff removes itself")
	skin.die(0.0)
	skin.hit(0.0)
	check(skin.position.is_equal_approx(rest), "a hit that kills does not flinch the body")
	skin.queue_free()
	#a wall where the body would end: the fall is pulled back so the body ends in front of it
	var body := CharacterBody2D.new()
	root.add_child(body)
	var wall := StaticBody2D.new()
	var box := CollisionShape2D.new()
	box.shape = RectangleShape2D.new()
	box.shape.size = Vector2(10, 400)
	wall.add_child(box)
	wall.position = Vector2(20, 0)
	root.add_child(wall)
	skin = SCENE.instantiate()
	body.add_child(skin)
	await physics_frame
	await physics_frame
	skin.update_visual(Vector2.ZERO, Vector2.RIGHT, false, false) #faces the wall
	skin.die(180.0)
	await create_timer(2.0).timeout
	check(skin.full.position.length() > 1.0, "a fall into a wall is pulled back (by %.1f)" % skin.full.position.length())
	skin.revive()
	check(skin.full.position == Vector2.ZERO, "and put back on revive")
	body.queue_free()
	wall.queue_free()
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
