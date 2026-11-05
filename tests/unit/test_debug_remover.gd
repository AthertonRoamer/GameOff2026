extends Node

# Offline test for DebugRemover against the real game scene. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_debug_remover.tscn
# game.tscn is loaded with no GameManager parent, so it spawns no players and needs no network.

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	#off: the scene's debug settings are left as they were saved
	var game : Game = GAME_SCENE.instantiate()
	add_child(game)
	check(game.debug_respawn_dead_players, "disabled: Game.debug_respawn_dead_players stays on")
	check(game.level.can_toggle_darkness, "disabled: Level.can_toggle_darkness stays on (an instanced scene)")
	check(PixelArt.can_toggle_pixel_art, "disabled: the PixelArt autoload's can_toggle_pixel_art stays on")
	game.free()

	#on: every declared debug setting below the game is turned off, including nodes added later
	game = GAME_SCENE.instantiate()
	var remover : DebugRemover = game.get_node("DebugRemover")
	remover.enabled = true
	check(game.get_child(0) == remover, "DebugRemover is the first child of the game, so it runs before its siblings' _ready")
	add_child(game)
	check(not game.debug_respawn_dead_players, "enabled: Game.debug_respawn_dead_players turned off")
	check(not game.level.can_toggle_darkness, "enabled: Level.can_toggle_darkness turned off")
	check(not PixelArt.can_toggle_pixel_art, "enabled: the PixelArt autoload's can_toggle_pixel_art turned off (autoloads are stripped too)")
	PixelArt.can_toggle_pixel_art = true #put it back for anything after this test
	var late : NightShiftLevel = preload("res://game/level/night_shift_level.tscn").instantiate()
	late.can_toggle_darkness = true
	game.add_child(late)
	check(not late.can_toggle_darkness, "enabled: a node added after _ready is stripped too")
	var outside : NightShiftLevel = preload("res://game/level/night_shift_level.tscn").instantiate()
	outside.can_toggle_darkness = true
	add_child(outside)
	check(outside.can_toggle_darkness, "enabled: a node outside the game is left alone")
	var declared : Array[StringName] = [&"debug_respawn_dead_players"]
	check(DebugRemover.debug_settings_of(game) == declared, "settings are read from the DEBUG_SETTINGS constant")

	print("DebugRemover: %s" % ("ALL OK" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(1 if failures > 0 else 0)
