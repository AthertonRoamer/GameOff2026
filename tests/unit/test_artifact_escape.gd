extends Node

# Offline test of the attackers' win: carrying the target artifact into an exit zone (ArtifactEscape, MatchDirector.can_win_by_escaping), on the real
# game scene and map. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_artifact_escape.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const PLAYER_SCENE : PackedScene = preload("res://game/player/player.tscn")
const INTRUDER : Role = preload("res://game/roles/infiltrator.tres")
const GUARD : Role = preload("res://game/roles/medic.tres")

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	var game : Game = GAME_SCENE.instantiate()
	add_child(game)
	var director : MatchDirector = game.match_director
	var escape : ArtifactEscape = game.artifact_escape
	var placer : ArtifactPlacer = game.artifact_placer
	var facility : FacilityMap = game.level.facility

	#who wins by getting the artifact out
	check(director.can_win_by_escaping(Team.ATTACKERS, true), "an intruder wins by escaping")
	check(director.can_win_by_escaping(Team.ATTACKERS, false), "a secretly attacking guard does too by default")
	check(not director.can_win_by_escaping(Team.DEFENDERS, false), "a defender never does")
	check(not director.can_win_by_escaping(Team.UNKNOWN, false), "nor does a player whose team isn't known")
	director.attacking_guards_win_by_escaping = false
	check(director.can_win_by_escaping(Team.ATTACKERS, true), "with the option off an intruder still does")
	check(not director.can_win_by_escaping(Team.ATTACKERS, false), "and a secretly attacking guard doesn't")
	director.attacking_guards_win_by_escaping = true

	#the wiring game.gd does
	check(escape.facility == facility and escape.target_chooser == game.target_chooser and escape.match_director == director, "the escape check is wired to the map, the target and the director")

	#a real player in the real map
	var target : Artifact = placer.artifacts[0]
	var other : Artifact = placer.artifacts[1]
	game.target_chooser.target = target
	var player : Player = PLAYER_SCENE.instantiate()
	player.starting_items = [] as Array[Item]
	player.role = INTRUDER
	player.team = Team.ATTACKERS
	game.level.actors.add_child(player)
	var exit_id : String = facility.exits.keys()[0]
	var exit_rect : Rect2i = facility.exits[exit_id][0]
	var in_exit : Vector2 = Vector2(exit_rect.position * FacilityTileSet.TILE) + Vector2(exit_rect.size * FacilityTileSet.TILE) / 2.0
	var other_exit_rect : Rect2i = facility.exits[facility.exits.keys()[1]][0]
	var in_other_exit : Vector2 = Vector2(other_exit_rect.position * FacilityTileSet.TILE) + Vector2(other_exit_rect.size * FacilityTileSet.TILE) / 2.0
	var outside : Vector2 = facility.room_center_px("ring")
	check(escape.exit_chooser == game.exit_chooser, "the escape check is wired to the designated exit")

	#the designated exit: chosen at random from the map's exits, the same for a seed
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	var chosen : Dictionary = {}
	for i in 40:
		rng.seed = i
		chosen[game.exit_chooser.choose(facility.exits.keys(), rng)] = true
	check(chosen.size() == facility.exits.size() and chosen.keys().all(func(id : String) -> bool: return facility.exits.has(id)), "any exit can be the designated one, and it is always a real exit")
	check(game.exit_chooser.choose([], rng) == "", "no exits: no designated exit")

	game.exit_chooser.designated = exit_id
	player.global_position = in_exit
	check(not escape.is_escaping(player), "in an exit with nothing: not escaping")
	player.inventory.put_in_slot(0, other)
	check(not escape.is_escaping(player), "in an exit with another artifact: not escaping")
	player.inventory.put_in_slot(1, target)
	check(escape.is_escaping(player), "an intruder in the designated exit with the target: escaping")
	player.global_position = in_other_exit
	check(not escape.is_escaping(player), "the target in an exit that isn't the designated one: not escaping")
	player.global_position = outside
	check(not escape.is_escaping(player), "the target but not in an exit: not escaping")
	player.global_position = in_exit
	game.exit_chooser.designated = ""
	check(not escape.is_escaping(player), "a peer that doesn't know the designated exit never decides")
	game.exit_chooser.designated = exit_id

	player.role = GUARD
	check(escape.is_escaping(player), "a secretly attacking guard with the target escapes by default")
	director.attacking_guards_win_by_escaping = false
	check(not escape.is_escaping(player), "and doesn't with the option off")
	director.attacking_guards_win_by_escaping = true
	player.team = Team.DEFENDERS
	check(not escape.is_escaping(player), "a defender carrying the target doesn't escape")
	player.team = Team.ATTACKERS
	player.role = INTRUDER
	game.target_chooser.target = null
	check(not escape.is_escaping(player), "a peer that doesn't know the target never decides")
	game.target_chooser.target = target
	player.health = 0.0
	check(not escape.is_escaping(player), "a dead player doesn't escape")
	player.health = player.starting_health

	#the check ends the match, only once it has begun
	escape.players = func() -> Array: return [player]
	escape._check()
	check(not director.is_decided, "nothing is decided before the match begins")
	director.begin({1: Team.ATTACKERS}, [{"id": 1, "name": "A", "role": "Infiltrator", "team": Team.ATTACKERS}], func(_id : int) -> bool: return true)
	escape._check()
	check(director.is_decided, "the target carried into an exit decides the match")
	check(game.end_screen.reason_label.text.begins_with("Attackers win."), "the end screen says the attackers won")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
