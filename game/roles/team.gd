class_name Team
extends RefCounted

##Which side a player wins with. Secret: each peer is only told the teams it may know (see RoleAssigner.teams_visible_to), the rest are UNKNOWN.
##Intruders are always ATTACKERS. Guards are mostly DEFENDERS, but some are secretly ATTACKERS.
##Never let simulated gameplay depend on a team: peers that don't know it would simulate it differently.

enum { UNKNOWN, ATTACKERS, DEFENDERS }


static func name_of(team : int) -> String:
	match team:
		ATTACKERS: return "Attackers"
		DEFENDERS: return "Defenders"
	return "Unknown"
