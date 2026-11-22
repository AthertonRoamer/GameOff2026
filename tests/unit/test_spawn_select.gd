extends Node

# Offline test of choosing where to start: spawn rooms (GuardSpawn / IntruderSpawn markers), who sees whose pick (RoleAssigner.sees_spawn_of), and
# the spawn selection phase on the real game scene (the lobby checking picks, ending 5 s after everyone has picked, and placing the players).
# Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_spawn_select.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const PLAYER_SCENE : PackedScene = preload("res://game/player/player.tscn")

const DEFENDER : int = 1 #also this peer's own id offline, so the phase shows its picks as "YOU"
const IMPOSTER : int = 2
const INTRUDER : int = 3

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
	var facility : FacilityMap = game.level.facility
	var assigner : RoleAssigner = game.role_assigner

	#spawn rooms come from the markers' positions
	var guard_rooms : Array[String] = facility.spawn_rooms(SpawnRoomMarker.Kind.GUARD)
	var intruder_rooms : Array[String] = facility.spawn_rooms(SpawnRoomMarker.Kind.INTRUDER)
	check(guard_rooms.size() >= 2 and intruder_rooms.has("pad_north"), "the map has guard and intruder spawn rooms (%s / %s)" % [guard_rooms, intruder_rooms])
	check(not guard_rooms.any(func(r : String) -> bool: return intruder_rooms.has(r)), "no room is both")
	check(facility.room_at(facility.spawn_point(guard_rooms[0], SpawnRoomMarker.Kind.GUARD)) == guard_rooms[0], "a room's spawn point is in that room")
	var marker : SpawnRoomMarker = facility.spawn_markers()[0]
	var home : Vector2 = marker.position
	marker.position = facility.room_center_px("archive")
	facility.build()
	check(facility.spawn_rooms(marker.kind).has("archive"), "moving a marker onto another room makes that room the spawn room")
	marker.position = home
	facility.build()
	check(SpawnRoomMarker.kind_for(game.intruder_roles[0]) == SpawnRoomMarker.Kind.INTRUDER and SpawnRoomMarker.kind_for(game.guard_roles[0]) == SpawnRoomMarker.Kind.GUARD, "intruders start in intruder rooms, guards (secretly attacking ones too) in guard rooms")

	#who sees whose pick
	var guard_index : int = 0
	var intruder_index : int = assigner.guard_roles.size()
	var assignment : Dictionary = {
		"roles": {DEFENDER: guard_index, IMPOSTER: guard_index + 1, INTRUDER: intruder_index},
		"teams": {DEFENDER: Team.DEFENDERS, IMPOSTER: Team.ATTACKERS, INTRUDER: Team.ATTACKERS},
	}
	assigner.intruders_know_attackers = true
	assigner.everyone_knows_all_teams = false #(game.tscn may have the debug team rings on, which tell everyone every team)
	check(assigner.sees_spawn_of(DEFENDER, IMPOSTER, assignment), "a defender sees a secretly attacking guard's pick (they look like any guard)")
	check(not assigner.sees_spawn_of(DEFENDER, INTRUDER, assignment), "a defender doesn't see the intruder's")
	check(assigner.sees_spawn_of(IMPOSTER, DEFENDER, assignment) and assigner.sees_spawn_of(IMPOSTER, INTRUDER, assignment), "the secretly attacking guard sees the guards' and the intruder's")
	check(assigner.sees_spawn_of(INTRUDER, IMPOSTER, assignment) and not assigner.sees_spawn_of(INTRUDER, DEFENDER, assignment), "the intruder sees the attacking guard's, not the defender's")
	check(assigner.sees_spawn_of(INTRUDER, INTRUDER, assignment), "everyone sees their own")
	assigner.intruders_know_attackers = false
	check(not assigner.sees_spawn_of(INTRUDER, IMPOSTER, assignment), "an intruder who isn't told who the attacking guard is doesn't see their pick either")
	check(assigner.sees_spawn_of(IMPOSTER, INTRUDER, assignment), "the attacking guard still sees the intruder's (an intruder's side is public)")
	assigner.intruders_know_attackers = true

	var guard_room : String = guard_rooms[0] #(spawn markers move as the map is edited, so no room names are fixed here)
	var other_room : String = guard_rooms[1]
	#the phase, on the real game, with three real players
	game.assignment = assignment
	for id : int in [DEFENDER, IMPOSTER, INTRUDER]:
		var player : Player = PLAYER_SCENE.instantiate()
		player.starting_items = [] as Array[Item]
		player.role = assigner.role_at(assignment["roles"][id])
		player.team = assignment["teams"][id]
		player.player_name = "P%d" % id
		player.position = facility.room_center_px("ring")
		game.level.actors.add_child(player)
		game.spawner.players[id] = player
	var phase : SpawnSelectPhase = game.phases.get_children().filter(func(n : Node) -> bool: return n is SpawnSelectPhase).front()
	check(phase != null and is_equal_approx(phase.duration_seconds, 30.0) and is_equal_approx(phase.linger_seconds, 5.0), "the spawn phase lasts up to 30 s, and 5 s once everyone has picked")
	check(not phase.screen.visible, "its screen starts hidden (saved hidden, so it does not cover game.tscn in the editor)")
	phase.game = game
	phase.started_tick = 1000
	phase.enter()
	check(not phase.decide_pick(INTRUDER, guard_room), "an intruder can't pick a guard room")
	check(not phase.decide_pick(DEFENDER, "pad_north"), "a guard can't pick an intruder room")
	check(not phase.decide_pick(99, guard_room), "someone not in the match can't pick")
	check(phase.decide_pick(DEFENDER, guard_room) and phase.decide_pick(INTRUDER, "pad_north"), "a room of the right kind is accepted")
	check(not phase.lobby_is_done(1100), "not done while someone hasn't picked")
	check(phase.decide_pick(IMPOSTER, other_room), "the attacking guard picks a guard room")
	check(phase.picks_visible_to(DEFENDER) == {DEFENDER: guard_room, IMPOSTER: other_room}, "the defender is sent the guards' picks")
	check(phase.picks_visible_to(IMPOSTER) == {DEFENDER: guard_room, IMPOSTER: other_room, INTRUDER: "pad_north"}, "the attacking guard is sent everyone's")
	check(phase.picks_visible_to(INTRUDER) == {IMPOSTER: other_room, INTRUDER: "pad_north"}, "the intruder is sent the attackers'")
	check(phase.spawn_layer.own_pick == guard_room, "this peer's own pick is shown on its map")
	#the map shows both kinds of spawn room (guard blue, intruder red), but only your own kind can be clicked
	check(SpawnRoomMarker.colour_of(SpawnRoomMarker.Kind.GUARD).b > SpawnRoomMarker.colour_of(SpawnRoomMarker.Kind.GUARD).r and SpawnRoomMarker.colour_of(SpawnRoomMarker.Kind.INTRUDER).r > SpawnRoomMarker.colour_of(SpawnRoomMarker.Kind.INTRUDER).b, "guard spawns are blue, intruder spawns red")
	phase.map.facility = facility
	phase.spawn_layer.spawn_kind = SpawnRoomMarker.Kind.GUARD
	check(phase.spawn_layer.show_other_kind, "the other side's spawn rooms are shown too")
	check(not phase.spawn_layer.map_click(facility.room_center_px("pad_north")), "an intruder room on a guard's map can't be clicked")
	check(phase.spawn_layer.map_click(facility.room_center_px(guard_room)), "a guard room on a guard's map can")
	check(SpawnSelectPhase._legend(SpawnRoomMarker.Kind.GUARD, false).contains("GUARD SPAWN") and SpawnSelectPhase._legend(SpawnRoomMarker.Kind.GUARD, false).contains("INTRUDER SPAWN"), "the legend names both kinds")
	var linger : int = ceili(phase.linger_seconds * NetworkTime.tickrate)
	check(not phase.lobby_is_done(1200), "everyone has picked: it lingers so the picks can be seen")
	check(not phase.lobby_is_done(1200 + linger - 1), "still lingering just before 5 s")
	check(phase.lobby_is_done(1200 + linger), "done 5 s after the last pick")
	check(phase.decide_pick(IMPOSTER, guard_room) and phase.picks()[IMPOSTER] == guard_room, "a pick can be changed until the end")

	#when it ends the lobby places everyone: a missing pick gets a random room of the right kind, players in the same room stand apart
	phase.enter() #a fresh run: nobody has picked
	phase.decide_pick(DEFENDER, other_room)
	phase.decide_pick(IMPOSTER, other_room)
	phase.exit()
	check(not phase.screen.visible, "its screen is hidden when it ends")
	var picks : Dictionary = phase.picks()
	check(picks.get(INTRUDER, "") in intruder_rooms, "the intruder, who didn't pick, gets a random intruder room (%s)" % picks.get(INTRUDER, ""))
	var moved : Dictionary = {}
	for id : int in [DEFENDER, IMPOSTER, INTRUDER]:
		moved[id] = game.spawner.players[id]._teleport_to
	check(moved.values().all(func(at : Variant) -> bool: return at is Vector2), "every player is moved (through teleport, so the move syncs)")
	check(facility.room_at(moved[DEFENDER]) == other_room and facility.room_at(moved[IMPOSTER]) == other_room, "the guards are placed in the room they picked")
	check(facility.room_at(moved[INTRUDER]) == picks[INTRUDER], "the intruder is placed in theirs")
	check(moved[DEFENDER].distance_to(moved[IMPOSTER]) >= phase.spread_px - 0.1, "two players in one room stand apart")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
