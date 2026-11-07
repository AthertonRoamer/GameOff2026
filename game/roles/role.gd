class_name Role
extends Resource

##A player's kit: what they are (a guard or an intruder), how they move and what they carry. Every peer knows every player's role.
##A role never says which team the player is on: a Medic can be a defender or secretly an attacker. The team is separate and secret, see Team.
##Gameplay that is simulated (movement, damage, items) may depend on the role, never on the team.

enum Kind { GUARD, INTRUDER }

@export var role_name : String = ""
@export var kind : Kind = Kind.GUARD #public: everyone can see whether a player is a guard or an intruder
@export var color : Color = Color.WHITE #identifies the role (debug role rings for now)
@export var speed : float = 200.0
@export var run_multiplier : float = 1.6
@export var starting_health : float = 100.0
@export var starting_items : Array[Item] = []


func is_intruder() -> bool:
	return kind == Kind.INTRUDER


##Copies this role's stats onto a player. Call it before the player enters the tree: Player._ready derives its acceleration and friction from
##the speed, and Inventory._ready takes the starting items.
func apply(player : Player) -> void:
	player.speed = speed
	player.run_multiplier = run_multiplier
	player.starting_health = starting_health
	player.health = starting_health
	player.starting_items = starting_items.duplicate()
