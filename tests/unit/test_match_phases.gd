extends Node

# Offline test of the phases before play (MatchPhases, MatchPhase, RoleRevealPhase) and of Game starting play only once they are over.
# Ticks are fed by hand (_on_tick), the way test_pickups feeds PickupControl. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_match_phases.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const INTRUDER : Role = preload("res://game/roles/infiltrator.tres")
const GUARD : Role = preload("res://game/roles/medic.tres")

var failures : int = 0


class FakePhase extends MatchPhase:
	var events : Array = [] #shared between the phases of one test: "enter <name> @tick" and "exit <name> @tick"
	var done : bool = false
	var saw_cover : bool = false #the loading cover was still up when this phase entered

	func enter() -> void:
		events.append("enter %s @%d" % [name, started_tick])
		saw_cover = game != null and game.phases.cover != null and game.phases.cover.visible

	func exit() -> void:
		events.append("exit %s" % name)

	func lobby_is_done(_tick : int) -> bool:
		return done


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func make_runner(names : Array, events : Array) -> MatchPhases:
	var runner : MatchPhases = MatchPhases.new()
	for phase_name : String in names:
		var phase : FakePhase = FakePhase.new()
		phase.name = phase_name
		phase.duration_seconds = 1.0
		phase.events = events
		runner.add_child(phase)
	add_child(runner)
	return runner


func _ready() -> void:
	var finished_at : Array = []
	var events : Array = []

	#phases run in tree order; each ends when its time is up or when the lobby says it is done, a few ticks later, on every peer at once
	var runner : MatchPhases = make_runner(["First", "Second"], events)
	runner.finished.connect(func(tick : int) -> void: finished_at.append(tick))
	var first : FakePhase = runner.get_child(0)
	var second : FakePhase = runner.get_child(1)
	var delay : int = runner.apply_delay_ticks
	runner.run(100)
	check(events == ["enter First @100"], "the first phase starts on the start tick")
	check(runner.current_phase() == first and runner.is_running(), "it is the current phase")
	var first_ends : int = 100 + first.duration_ticks() + delay
	for tick in range(101, first_ends):
		runner._on_tick(0.0, tick)
	check(events.size() == 1, "it lasts its whole duration, plus the delay the lobby gives everyone to hear of its end")
	check(runner._end_ticks.get(0, -1) == first_ends, "the lobby scheduled its end when its time was up")
	runner._on_tick(0.0, first_ends)
	check(events == ["enter First @100", "exit First", "enter Second @%d" % first_ends], "on that tick the first phase exits and the second enters")
	second.done = true
	runner._on_tick(0.0, first_ends + 1)
	check(runner._end_ticks.get(1, -1) == first_ends + 1 + delay, "a phase the lobby says is done ends early (still with the delay)")
	for tick in range(first_ends + 2, first_ends + 1 + delay):
		runner._on_tick(0.0, tick)
	check(finished_at.is_empty(), "nothing finishes before that tick")
	runner._on_tick(0.0, first_ends + 1 + delay)
	check(events.back() == "exit Second" and finished_at == [first_ends + 1 + delay], "the last phase ending finishes the run, on that tick")
	check(runner.current_phase() == null and not runner.is_running(), "nothing is running afterwards")
	runner._on_tick(0.0, first_ends + 100)
	check(finished_at.size() == 1, "finished fires once")
	runner.free()

	#a peer that hears late catches up, through more than one phase in one tick
	events = []
	finished_at = []
	runner = make_runner(["A", "B"], events)
	runner.finished.connect(func(tick : int) -> void: finished_at.append(tick))
	runner.run(10)
	runner._schedule_end_remote(0, 12)
	runner._schedule_end_remote(1, 13)
	runner._on_tick(0.0, 20)
	check(events == ["enter A @10", "exit A", "enter B @20", "exit B"] and finished_at == [20], "late news of two ends: both phases run their exit and enter, and play begins")
	runner.free()

	#no phases: play begins on the start tick
	finished_at = []
	runner = make_runner([], [])
	runner.finished.connect(func(tick : int) -> void: finished_at.append(tick))
	runner.run(55)
	check(finished_at == [55], "with no phases it finishes straight away, on the start tick")
	runner.free()

	#the real game: the role reveal is the first phase, and play (players, HUD, clock, win checks) waits for the phases
	var game : Game = GAME_SCENE.instantiate()
	add_child(game)
	var reveal : RoleRevealPhase = game.phases.get_children().filter(func(n : Node) -> bool: return n is MatchPhase).front() as RoleRevealPhase
	check(reveal != null, "the game's first phase is the role reveal")
	check(not reveal.screen.visible, "its screen starts hidden (and is saved hidden, so it does not cover game.tscn in the editor)")
	check(not game.player_hud.visible, "the HUD is hidden until play begins")
	check(not game.started, "play has not begun")
	check(game.phases.cover != null and game.phases.cover.visible, "a cover hides the world from loading until the first phase")
	var probe : FakePhase = FakePhase.new() #first in line, to see the cover still up while it enters
	probe.duration_seconds = 0.1
	game.phases.add_child(probe)
	game.phases.move_child(probe, 0)
	game.phases.run(1000)
	check(probe.saw_cover and not game.phases.cover.visible, "the cover stays up while the first phase enters, then goes (no frame of the world in between)")
	check(not game.player_hud.visible and not game.started, "the HUD stays hidden during the phases")
	check(not game.match_director._running, "nothing can be won or lost during the phases")
	var all_phases : Array = game.phases.get_children().filter(func(n : Node) -> bool: return n is MatchPhase)
	var expected : int = 1000
	for phase : MatchPhase in all_phases: #nobody is playing here, so no phase ends early
		expected += phase.duration_ticks() + game.phases.apply_delay_ticks
	var tick : int = 1000
	while game.phases.is_running() and tick < expected + 100:
		tick += 1
		game.phases._on_tick(0.0, tick)
	check(game.started and game.player_hud.visible, "when the phases end play begins and the HUD shows")
	check(game.game_clock._start_tick == tick, "the shift clock counts from the end of the phases, not the start of the match (%d)" % tick)
	check(tick == expected, "each phase lasts its duration (%d phases)" % all_phases.size())
	check(all_phases.size() >= 3 and all_phases[2] is SpawnSelectPhase, "after the role reveal, players choose where to start")

	#what the role reveal says
	reveal.show_player(INTRUDER, Team.ATTACKERS, game.artifact_placer.artifacts[0])
	check(reveal.role_label.text == "INFILTRATOR", "it names the role")
	check(reveal.team_label.text == "You are an intruder.", "an intruder is told so")
	check(reveal.objective_label.text.contains(game.artifact_placer.artifacts[0].item_name), "an attacker is told which artifact to steal")
	var bare : Role = Role.new() #made here, not a real role, whose portrait and description may be filled in at any time
	bare.role_name = "Bare"
	reveal.show_player(bare, Team.DEFENDERS)
	check(not reveal.portrait_rect.visible and not reveal.description_label.visible, "a role with no portrait or description shows neither")
	reveal.show_player(GUARD, Team.ATTACKERS)
	check(reveal.team_label.text == "You are secretly working with the intruders.", "a secretly attacking guard is told their real side")
	reveal.show_player(GUARD, Team.DEFENDERS)
	check(reveal.team_label.text == "You are a guard." and reveal.objective_label.text == "Stop the intruders until the shift ends.", "a defender is told to hold out")
	var role : Role = GUARD.duplicate()
	role.portrait = INTRUDER.starting_items[0].icon if INTRUDER.starting_items[0].icon != null else PlaceholderTexture2D.new()
	role.description = "Heals people."
	reveal.show_player(role, Team.DEFENDERS)
	check(reveal.portrait_rect.visible and reveal.description_label.visible and reveal.description_label.text == "Heals people.", "a portrait and a description are shown when the role has them")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
