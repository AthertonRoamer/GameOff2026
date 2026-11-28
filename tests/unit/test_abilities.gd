extends Node

# Offline test for the roles' abilities, on the real game scene. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_abilities.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const GUARD : Role = preload("res://game/roles/guard.tres")
const SHADE : Role = preload("res://game/roles/shade.tres")
const GUNNER : Role = preload("res://game/roles/gunner.tres")
const MEDIC : Role = preload("res://game/roles/medic.tres")
const VENTRAT : Role = preload("res://game/roles/ventrat.tres")
const TECHNICIAN : Role = preload("res://game/roles/technician.tres")
const PISTOL : Gun = preload("res://game/items/guns/pistol.tres")

var failures : int = 0
var game : Game
var players : Dictionary = {}


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func make_player(id : int, role : Role, at : Vector2) -> Player:
	var player : Player = game.spawner.player_scene.instantiate()
	player.name = str(id)
	player.role = role
	role.apply(player)
	game.level.actors.add_child(player)
	player.global_position = at
	players[id] = player
	return player


func _ready() -> void:
	game = GAME_SCENE.instantiate()
	add_child(game)
	var abilities : AbilityControl = game.abilities
	abilities.player_lookup = func(id : int) -> Player: return players.get(id)

	#the roles
	check(GUARD.starting_items.size() == 1 and not GUARD.can_revive and not GUARD.can_vent and not GUARD.silent_walk, "the guard is a pistol and nothing else")
	check(game.guard_roles.has(GUARD) and game.guard_roles.has(SHADE) and game.guard_roles.has(GUNNER) and game.guard_roles.has(MEDIC) and game.guard_roles.has(VENTRAT) and game.guard_roles.has(TECHNICIAN), "all six guard roles are in the game")
	check(TECHNICIAN.starting_items.any(func(i : Item) -> bool: return i is PortableGeneratorItem), "the technician carries a portable generator")
	check(MEDIC.medicine_item is Medicine and SHADE.silent_chat and not GUARD.silent_chat, "the medic makes medicine, and the shade chats silently")

	#the shade
	var shade : Player = make_player(10, SHADE, Vector2(-4000, -4000))
	var gun : Gun = shade.inventory.active_item as Gun
	check(gun != null and gun.shot_sound.range_m < PISTOL.shot_sound.range_m / 3.0, "the shade's pistol carries far less than the pistol (%d m against %d m)" % [gun.shot_sound.range_m, PISTOL.shot_sound.range_m])
	check(gun.shot_sound.volume_db < PISTOL.shot_sound.volume_db and gun.shot_sound.pick() != null, "and is quieter, with a sound of its own")
	var heard : Array[SoundDef] = []
	shade.footsteps.stepped.connect(func(def : SoundDef, _at : Vector2) -> void: heard.append(def))
	var legs : AnimatedSprite2D = shade.footsteps.legs
	legs.animation = &"legs_walk"
	legs.frame = 6
	check(heard.is_empty(), "the shade's walk makes no sound")
	await get_tree().create_timer(0.3).timeout
	legs.animation = &"legs_run"
	legs.frame = 0
	check(heard.size() == 1 and heard[0] == SHADE.run_sound and heard[0].range_m < shade.footsteps.run.range_m / 2.0, "a run makes a quiet step")
	var guard : Player = make_player(11, GUARD, Vector2(-4100, -4000))
	var guard_heard : Array[SoundDef] = []
	guard.footsteps.stepped.connect(func(def : SoundDef, _at : Vector2) -> void: guard_heard.append(def))
	guard.footsteps.legs.animation = &"legs_walk"
	guard.footsteps.legs.frame = 6
	check(guard_heard.size() == 1 and guard_heard[0] == guard.footsteps.walk, "while a guard's walk is heard as usual")

	#the gunner
	var gunner : Player = make_player(12, GUNNER, Vector2(-4200, -4000))
	var shotgun : Gun = gunner.inventory.active_item as Gun
	check(shotgun != null and shotgun.pellets > 1 and shotgun.magazine_size > 0, "the gunner has a shotgun")
	check(gunner.inventory.magazine == shotgun.magazine_size and gunner.inventory.reserve_at(0) == GUNNER.starting_spare_rounds and GUNNER.starting_spare_rounds > 0, "loaded, with shells to spare")
	var spread : Array[Vector2] = HitscanManager.pellet_directions(Vector2.RIGHT, shotgun.pellets, shotgun.spread_degrees, 77)
	var same : Array[Vector2] = HitscanManager.pellet_directions(Vector2.RIGHT, shotgun.pellets, shotgun.spread_degrees, 77)
	var widest : float = 0.0
	for dir : Vector2 in spread:
		widest = maxf(widest, absf(dir.angle()))
	check(spread.size() == shotgun.pellets and spread == same, "a shot's pellets are the same for the shooter and the lobby (seeded by the shot)")
	check(widest <= deg_to_rad(shotgun.spread_degrees) + 0.001 and HitscanManager.pellet_directions(Vector2.RIGHT, 1, 5.0, 1).size() == 1, "they stay inside the cone, and one pellet goes straight")
	check(shotgun.shot_sound.range_m > PISTOL.shot_sound.range_m and shotgun.pellets * shotgun.damage > 50.0, "the shotgun is loud and kills at close range")

	#the medic
	var medic : Player = make_player(20, MEDIC, Vector2(-3000, -3000))
	var target : Player = make_player(21, GUARD, Vector2(-2990, -3000))
	var other : Player = make_player(22, GUARD, Vector2(-2980, -3000))
	var revivable : Revivable = target.get_node("Revivable")
	revivable.control = abilities
	check(not revivable.can_interact(medic), "a player on their feet is not offered for reviving")
	target.take_damage(target.health, Vector2.RIGHT)
	await get_tree().process_frame
	check(not target.is_alive() and revivable.can_interact(medic), "a fallen player is, to a medic")
	check(not revivable.can_interact(other) and not revivable.can_interact(target), "but not to anyone else")
	abilities._decide_revive(22, 21)
	check(not target.is_alive(), "a player who is not a medic can't revive")
	medic.global_position = Vector2(-2000, -2000)
	abilities._decide_revive(20, 21)
	check(not target.is_alive(), "a medic out of reach can't")
	medic.global_position = target.skin.body_position() + Vector2(20, 0)
	check(revivable.is_in_reach(medic.global_position), "close to the body is in reach")
	abilities._decide_revive(20, 21)
	check(target.is_alive() and is_equal_approx(target.health, target.starting_health * abilities.revive_health_fraction), "a medic in reach brings them back with part of their health")
	target.take_damage(target.health, Vector2.RIGHT)
	abilities._decide_revive(20, 21)
	check(not target.is_alive(), "the medic needs a moment before reviving again (cooldown)")
	abilities._ready_at.clear()
	target.died_at_msec -= int(abilities.revive_window_seconds * 1000.0) + 1000
	abilities._decide_revive(20, 21)
	check(not target.is_alive() and not revivable.can_interact(medic), "and a player who has been down too long stays down")

	#the ventrat
	check(abilities.vents.size() >= 2, "the map has vents (%d)" % abilities.vents.size())
	var rat : Player = make_player(30, VENTRAT, abilities.vents[0].global_position + Vector2(10, 0))
	var vent : Vent = abilities.vents[0]
	check(vent.can_interact(rat) and vent.is_in_reach(rat.global_position), "a ventrat at a vent can use it")
	check(not vent.can_interact(other), "and nobody else")
	abilities._decide_vent(22, 0, 1)
	check(other._teleport_to == null, "a guard can't travel through it")
	abilities._decide_vent(30, 0, 0)
	check(rat._teleport_to == null, "going nowhere is not a trip")
	abilities._decide_vent(30, 1, 2)
	check(rat._teleport_to == null, "nor is leaving from a vent they are not at")
	abilities._decide_vent(30, 0, 1)
	check(rat._teleport_to == abilities.vents[1].global_position, "a ventrat comes out of the vent they chose")
	rat._teleport_to = null
	abilities._decide_vent(30, 0, 2)
	check(rat._teleport_to == null, "and has to wait before the next trip (cooldown)")

	#the vent screen
	var screen : VentScreen = abilities.vent_screen
	var interactor_screen : Control = vent.interact(rat)
	check(interactor_screen == screen and screen.visible, "using a vent opens the vent map")
	screen.close()
	check(not screen.visible, "and closing it leaves")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(failures)
