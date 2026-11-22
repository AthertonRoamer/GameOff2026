class_name ArtifactEscape
extends Node

##Watches for the attackers' win: a player carrying the target artifact standing in the designated exit zone (DesignatedExitChooser; any other exit
##does nothing). Lobby only, because only the lobby knows every team, the target and the exit. Inventories change on the same tick on every peer (PickupControl), and the lobby already trusts its
##own view of where players are for pickups and consoles. Whether a secretly attacking guard counts is MatchDirector.attacking_guards_win_by_escaping.

@export var target_chooser : TargetArtifactChooser
@export var match_director : MatchDirector
@export var exit_chooser : DesignatedExitChooser #only its designated exit counts

var facility : FacilityMap
var players : Callable = Callable() #() -> Array of Player

var _watching : bool = false


##Lobby only. Starts checking after every tick. The director ignores the report before the match begins and once it is decided.
func watch() -> void:
	if not _watching:
		_watching = true
		NetworkTime.after_tick_loop.connect(_check)


##Stops checking. Call it when the game starts to end (see NetworkUnloader).
func quiesce() -> void:
	if _watching:
		_watching = false
		NetworkTime.after_tick_loop.disconnect(_check)


func _exit_tree() -> void:
	quiesce()


func is_escaping(player : Player) -> bool:
	var target : Artifact = target_chooser.target
	return player.is_alive() and target != null \
		and match_director.can_win_by_escaping(player.team, player.role != null and player.role.is_intruder()) \
		and player.inventory.slots.has(target) and exit_chooser.designated != "" and facility.exit_at(player.global_position) == exit_chooser.designated


func _check() -> void:
	if match_director.is_decided or not players.is_valid():
		return
	for player : Variant in players.call():
		if is_instance_valid(player) and is_escaping(player):
			match_director.report_artifact_escaped()
			return
