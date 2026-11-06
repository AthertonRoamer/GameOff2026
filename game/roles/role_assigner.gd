class_name RoleAssigner
extends RefCounted

##Decides every player's role and team at the start of a match, and which of those teams each peer is allowed to know.
##Pure logic, no networking: Game runs it on the lobby and sends each peer its share.
##
##An assignment is a Dictionary: {"roles": {member_id: role_index}, "teams": {member_id: Team}}. role_index points into all_roles()
##(guard_roles then intruder_roles), which is the same on every peer, so it can be sent instead of the Role. -1 means no role.

var guard_roles : Array[Role] = []
var intruder_roles : Array[Role] = []
var intruder_count : int = 1
var attacking_guard_count : int = 1 #how many guards are secretly attackers. At least one guard always defends
var intruders_know_attackers : bool = true #intruders are told which guards are secretly on their side
var attacking_guards_know_each_other : bool = false #secretly attacking guards are told about each other
var everyone_knows_all_teams : bool = false #debug: every peer is told every team


func all_roles() -> Array[Role]:
	return guard_roles + intruder_roles


func role_at(index : int) -> Role:
	var roles : Array[Role] = all_roles()
	return roles[index] if index >= 0 and index < roles.size() else null


func assign(member_ids : Array[int], rng : RandomNumberGenerator) -> Dictionary:
	var roles : Dictionary = {}
	var teams : Dictionary = {}
	var shuffled : Array[int] = member_ids.duplicate()
	_shuffle(shuffled, rng)

	var intruders : int = clampi(intruder_count, 0, maxi(shuffled.size() - 1, 1)) #leave at least one guard, unless playing alone
	if intruder_roles.is_empty() and intruders > 0:
		push_warning("RoleAssigner has no intruder roles, everyone will be a guard")
		intruders = 0
	var intruder_ids : Array[int] = shuffled.slice(0, intruders)
	var guard_ids : Array[int] = shuffled.slice(intruders)

	var intruder_picks : Array[int] = _pick_unique(intruder_roles.size(), intruder_ids.size(), rng, "intruder")
	for i in intruder_ids.size():
		roles[intruder_ids[i]] = guard_roles.size() + intruder_picks[i]
		teams[intruder_ids[i]] = Team.ATTACKERS

	if guard_roles.is_empty() and not guard_ids.is_empty():
		push_warning("RoleAssigner has no guard roles, guards will have no role")
	var guard_picks : Array[int] = _pick_unique(guard_roles.size(), guard_ids.size(), rng, "guard")
	var attackers : int = clampi(attacking_guard_count, 0, maxi(guard_ids.size() - 1, 0))
	for i in guard_ids.size(): #guard_ids is already shuffled, so the first few being attackers is random
		roles[guard_ids[i]] = guard_picks[i] if guard_picks[i] >= 0 else -1
		teams[guard_ids[i]] = Team.ATTACKERS if i < attackers else Team.DEFENDERS
	return {"roles": roles, "teams": teams}


##The teams of an assignment that one member may know. Everyone else is left out (UNKNOWN to that peer).
func teams_visible_to(member_id : int, assignment : Dictionary) -> Dictionary:
	var teams : Dictionary = assignment["teams"]
	if everyone_knows_all_teams:
		return teams.duplicate()
	var visible : Dictionary = {}
	var my_team : int = teams.get(member_id, Team.UNKNOWN)
	var i_am_intruder : bool = _is_intruder(assignment, member_id)
	for id : int in teams:
		var knows : bool = id == member_id or _is_intruder(assignment, id) #an intruder's team follows from its public role
		if not knows and my_team == Team.ATTACKERS and teams[id] == Team.ATTACKERS:
			knows = intruders_know_attackers if i_am_intruder else attacking_guards_know_each_other
		if knows:
			visible[id] = teams[id]
	return visible


func _is_intruder(assignment : Dictionary, member_id : int) -> bool:
	var role : Role = role_at(assignment["roles"].get(member_id, -1))
	return role != null and role.is_intruder()


##count indices into a pool of pool_size, all different while the pool lasts, then repeating (with a warning). -1s if the pool is empty.
func _pick_unique(pool_size : int, count : int, rng : RandomNumberGenerator, what : String) -> Array[int]:
	var picks : Array[int] = []
	if pool_size == 0:
		picks.resize(count)
		picks.fill(-1)
		return picks
	if count > pool_size:
		push_warning("RoleAssigner: %d %ss but only %d %s roles, some roles repeat" % [count, what, pool_size, what])
	var pool : Array[int] = []
	for i in count:
		if pool.is_empty():
			pool.assign(range(pool_size))
			_shuffle(pool, rng)
		picks.append(pool.pop_back())
	return picks


func _shuffle(array : Array[int], rng : RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j : int = rng.randi_range(0, i)
		var t : int = array[i]
		array[i] = array[j]
		array[j] = t
