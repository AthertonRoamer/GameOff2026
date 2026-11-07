extends Node

# Offline test for RoleAssigner. Run as a scene so the project's classes and autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_role_assigner.tscn

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func make_role(role_name : String, kind : Role.Kind) -> Role:
	var role : Role = Role.new()
	role.role_name = role_name
	role.kind = kind
	return role


func make_assigner() -> RoleAssigner:
	var assigner : RoleAssigner = RoleAssigner.new()
	for n in ["Medic", "Gunman", "Engineer", "Scout"]:
		assigner.guard_roles.append(make_role(n, Role.Kind.GUARD))
	for n in ["Infiltrator", "Hacker"]:
		assigner.intruder_roles.append(make_role(n, Role.Kind.INTRUDER))
	return assigner


func ids(count : int) -> Array[int]:
	var result : Array[int] = []
	for i in count:
		result.append(100 + i)
	return result


func count_where(assignment : Dictionary, assigner : RoleAssigner, intruder : bool, team : int) -> int:
	var n : int = 0
	for id : int in assignment["roles"]:
		var role : Role = assigner.role_at(assignment["roles"][id])
		if role != null and role.is_intruder() == intruder and assignment["teams"][id] == team:
			n += 1
	return n


func _ready() -> void:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()

	print("assignment shape over many seeds and sizes")
	var all_ok : bool = true
	var unique_ok : bool = true
	var defender_ok : bool = true
	for players in range(2, 8):
		for seed_value in 20:
			rng.seed = seed_value
			var assigner : RoleAssigner = make_assigner()
			assigner.intruder_count = 2 if players >= 6 else 1
			assigner.attacking_guard_count = 1
			var a : Dictionary = assigner.assign(ids(players), rng)
			var intruders : int = count_where(a, assigner, true, Team.ATTACKERS)
			var bad_intruders : int = count_where(a, assigner, true, Team.DEFENDERS)
			var guard_attackers : int = count_where(a, assigner, false, Team.ATTACKERS)
			var defenders : int = count_where(a, assigner, false, Team.DEFENDERS)
			var guards : int = players - assigner.intruder_count
			if a["roles"].size() != players or intruders != assigner.intruder_count or bad_intruders != 0 or guard_attackers != mini(1, guards - 1):
				all_ok = false
				print("    players=%d seed=%d: %s" % [players, seed_value, a])
			if defenders < 1:
				defender_ok = false
			var seen : Dictionary = {}
			for id : int in a["roles"]:
				var role_index : int = a["roles"][id]
				if seen.has(role_index) and guards <= 4:
					unique_ok = false
				seen[role_index] = true
	check(all_ok, "everyone gets a role, intruders are all attackers, one guard secretly attacks")
	check(unique_ok, "roles are unique while there are enough of them")
	check(defender_ok, "at least one guard always defends")

	var assigner : RoleAssigner = make_assigner()
	assigner.attacking_guard_count = 10
	rng.seed = 1
	var many : Dictionary = assigner.assign(ids(5), rng)
	check(count_where(many, assigner, false, Team.DEFENDERS) == 1, "too many attacking guards asked for still leaves one defender")

	print("more guards than guard roles")
	assigner = make_assigner()
	rng.seed = 2
	var crowded : Dictionary = assigner.assign(ids(8), rng)
	var none_missing : bool = true
	for id : int in crowded["roles"]:
		if assigner.role_at(crowded["roles"][id]) == null:
			none_missing = false
	check(none_missing, "every player still gets a role (some repeat)")

	print("who knows which teams")
	assigner = make_assigner()
	assigner.attacking_guard_count = 2
	rng.seed = 3
	var a : Dictionary = assigner.assign(ids(5), rng)
	var intruder : int = -1
	var traitors : Array[int] = []
	var defender : int = -1
	for id : int in a["roles"]:
		if assigner.role_at(a["roles"][id]).is_intruder():
			intruder = id
		elif a["teams"][id] == Team.ATTACKERS:
			traitors.append(id)
		else:
			defender = id
	check(intruder != -1 and traitors.size() == 2 and defender != -1, "the test assignment has an intruder, two traitors and a defender")

	assigner.intruders_know_attackers = true
	assigner.attacking_guards_know_each_other = false
	var seen_by_intruder : Dictionary = assigner.teams_visible_to(intruder, a)
	check(seen_by_intruder.has(traitors[0]) and seen_by_intruder.has(traitors[1]) and not seen_by_intruder.has(defender), "intruder knows the traitors but no defender")
	var seen_by_traitor : Dictionary = assigner.teams_visible_to(traitors[0], a)
	check(seen_by_traitor.has(traitors[0]) and not seen_by_traitor.has(traitors[1]) and seen_by_traitor.has(intruder), "traitor knows itself and the intruder, not the other traitor")
	var seen_by_defender : Dictionary = assigner.teams_visible_to(defender, a)
	check(seen_by_defender.keys().size() == 2 and seen_by_defender[defender] == Team.DEFENDERS and seen_by_defender.has(intruder), "defender knows only itself and the intruder")

	assigner.intruders_know_attackers = false
	check(not assigner.teams_visible_to(intruder, a).has(traitors[0]), "intruder doesn't know traitors when intruders_know_attackers is off")
	assigner.attacking_guards_know_each_other = true
	check(assigner.teams_visible_to(traitors[0], a).has(traitors[1]), "traitors know each other when attacking_guards_know_each_other is on")
	check(not assigner.teams_visible_to(defender, a).has(traitors[0]), "defenders still don't know traitors")
	assigner.everyone_knows_all_teams = true
	check(assigner.teams_visible_to(defender, a).size() == 5, "debug: everyone knows every team")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
