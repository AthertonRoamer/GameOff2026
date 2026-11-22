class_name RoleRevealPhase
extends MatchPhase

##Shows each player who they are this match: their role's name, portrait and description, which side they are really on, and what that side has
##to do. Only this peer's own player is shown, so a secret team stays secret. Display only: it lasts its full duration.

const ATTACKER_COLOR : Color = Palette.WARM
const DEFENDER_COLOR : Color = Palette.OK

@onready var screen : CanvasLayer = $Screen
@onready var portrait_rect : TextureRect = $Screen/Center/Box/Portrait
@onready var role_label : Label = $Screen/Center/Box/RoleName
@onready var description_label : Label = $Screen/Center/Box/Description
@onready var team_label : Label = $Screen/Center/Box/Team
@onready var objective_label : Label = $Screen/Center/Box/Objective
@onready var countdown_label : Label = $Screen/Center/Box/Countdown


func _ready() -> void:
	screen.visible = false
	set_process(false)


func enter() -> void:
	var player : Player = game.spawner.local_player if game != null and game.spawner != null else null
	if not is_instance_valid(player): #a lobby process plays nobody
		return
	show_player(player.role, player.team, game.target_chooser.target)
	screen.visible = true
	set_process(true)


func exit() -> void:
	screen.visible = false
	set_process(false)


##Fills the screen for this role and team (public for the tests).
func show_player(role : Role, team : int, target : Artifact = null) -> void:
	role_label.text = role.role_name.to_upper() if role != null else "NO ROLE"
	role_label.add_theme_color_override("font_color", role.color if role != null else Palette.TEXT)
	portrait_rect.texture = role.portrait if role != null else null
	portrait_rect.visible = portrait_rect.texture != null
	description_label.text = role.description if role != null else ""
	description_label.visible = description_label.text != ""
	var is_intruder : bool = role != null and role.is_intruder()
	team_label.text = describe_team(team, is_intruder)
	team_label.add_theme_color_override("font_color", ATTACKER_COLOR if team == Team.ATTACKERS else DEFENDER_COLOR)
	objective_label.text = describe_objective(team, target)


static func describe_team(team : int, is_intruder : bool) -> String:
	if team == Team.ATTACKERS:
		return "You are an intruder." if is_intruder else "You are secretly working with the intruders."
	return "You are a guard."


static func describe_objective(team : int, target : Artifact = null) -> String:
	if team == Team.ATTACKERS:
		return "Find the %s and carry it out through the exit marked on your map." % (target.item_name if target != null else "target artifact")
	return "Stop the intruders until the shift ends."


func _process(_delta : float) -> void:
	countdown_label.text = "Starting in %d" % ceili(seconds_left())
