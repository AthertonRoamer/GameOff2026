class_name Role
extends Resource

##A player's kit: what they are (a guard or an intruder), how they move and what they carry. Every peer knows every player's role.
##A role never says which team the player is on: a Medic can be a defender or secretly an attacker. The team is separate and secret, see Team.
##Gameplay that is simulated (movement, damage, items) may depend on the role, never on the team.

enum Kind { GUARD, INTRUDER }

@export var role_name : String = ""
@export var kind : Kind = Kind.GUARD #public: everyone can see whether a player is a guard or an intruder
@export var color : Color = Color.WHITE #identifies the role (debug role rings, the role reveal)
@export var portrait : Texture2D #shown when the role is revealed at the start of a match. None: the reveal shows no picture
@export_multiline var description : String = "" #what the role does, shown under its name when it is revealed
@export var speed : float = 200.0
@export var run_multiplier : float = 1.6
@export var starting_health : float = 50.0
@export var starting_items : Array[Item] = []
@export var starting_spare_rounds : int = 24 ## ammunition carried besides the one in the gun (see Inventory)
@export_group("Abilities")
@export var silent_walk : bool = false ## walking makes no sound
@export var run_sound : SoundDef ## a run's footstep when it is not the usual one (null: the usual). Quieter for a role that runs quietly
@export var can_revive : bool = false ## may bring a fallen player back (see AbilityControl)
@export var can_vent : bool = false ## may travel through the vents (see AbilityControl)
@export var can_work_doors : bool = false ## may open and close a door by hand while standing next to it (E), no console needed; closing still needs its region to have the power (see DoorSwitch)
@export var silent_chat : bool = false ## chat is never said aloud: no voice and no speech bubble over their head (the window still has it)
@export var medicine_item : Item ## ready to make every medicine_seconds; holding Q then puts it in a free slot (see AbilityControl). None: the role makes none
@export_range(5.0, 600.0, 1.0, "suffix:s") var medicine_seconds : float = 60.0 ## until the next dose is ready to make
@export_range(0.1, 10.0, 0.1, "suffix:s") var medicine_make_seconds : float = 2.0 ## how long Q is held to make a dose that is ready
@export_group("Look")
@export var skin : String = "guard" ## the folder in game/player/skin that holds this role's sprite sheets (tools/rig/build_roles.ps1 makes them)
@export var legs_tint : Color = Color.WHITE ## the legs are every role's shared guard legs: a darker uniform (the intruder's) is this multiplied over them


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
	player.starting_spare_rounds = starting_spare_rounds
