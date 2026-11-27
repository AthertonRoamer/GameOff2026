class_name RoleRevealPhase
extends MatchPhase

##Shows each player who they are this match: their role's name, portrait and description, which side they are really on, and what that side has
##to do. Beside it, who's who: every player's role, with the intruder set apart. Roles are public; teams are not, so a secretly attacking guard is listed as
##an ordinary guard and a secret team stays secret. Display only: it lasts its full duration.

const ATTACKER_COLOR : Color = Palette.WARM
const DEFENDER_COLOR : Color = Palette.OK

@onready var screen : CanvasLayer = $Screen
@onready var portrait_rect : TextureRect = $Screen/Center/Box/Portrait
@onready var role_label : Label = $Screen/Center/Box/RoleName
@onready var description_label : Label = $Screen/Center/Box/Description
@onready var team_label : Label = $Screen/Center/Box/Team
@onready var objective_label : Label = $Screen/Center/Box/Objective
@onready var countdown_label : Label = $Screen/Center/Box/Countdown
@onready var roster_box : VBoxContainer = $Screen/Roster/Rows


func _ready() -> void:
	screen.visible = false
	set_process(false)


func enter() -> void:
	var player : Player = game.spawner.local_player if game != null and game.spawner != null else null
	if not is_instance_valid(player): #a lobby process plays nobody
		return
	show_player(player.role, player.team, game.target_chooser.target)
	show_roster(game.public_roster(), multiplayer.get_unique_id())
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


## Who's who: the intruder first, then the guards with their roles. Takes names and roles only (Game.public_roster): no teams (public for the tests).
func show_roster(roster : Array[Dictionary], own_id : int = 0) -> void:
	for old : Node in roster_box.get_children():
		roster_box.remove_child(old)
		old.queue_free()
	for intruders : bool in [true, false]:
		var group : Array = roster.filter(func(entry : Dictionary) -> bool: return (entry["role"] as Role).is_intruder() == intruders)
		if group.is_empty():
			continue
		_add_roster_line(("INTRUDERS" if group.size() > 1 else "INTRUDER") if intruders else "GUARDS", ATTACKER_COLOR if intruders else DEFENDER_COLOR, 18)
		for entry : Dictionary in group:
			var role : Role = entry["role"]
			var you : String = " (you)" if entry["id"] == own_id else ""
			_add_roster_line("%s%s  -  %s" % [entry["name"], you, role.role_name], role.color, 15)


func _add_roster_line(text : String, colour : Color, font_size : int) -> void:
	var line : Label = Label.new()
	line.text = text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_color_override("font_color", colour)
	line.add_theme_font_size_override("font_size", font_size)
	roster_box.add_child(line)


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
