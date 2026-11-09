class_name EndScreen
extends CanvasLayer

##Shows how the match ended: victory or defeat for this player, why, and who was really on which side. Teams are secret until this screen.

const WIN_COLOR : Color = Color(0.9490196, 0.70980394, 0.26666668)
const LOSE_COLOR : Color = Color(0.85, 0.25, 0.22)
const DEFENDER_COLOR : Color = Color(0.55, 0.85, 0.6)
const ATTACKER_COLOR : Color = Color(0.9, 0.45, 0.4)

@onready var title_label : Label = $Center/Box/Title
@onready var reason_label : Label = $Center/Box/Reason
@onready var roster_box : VBoxContainer = $Center/Box/Roster
@onready var countdown_label : Label = $Center/Box/Countdown

var _seconds_left : float = 0.0


func _ready() -> void:
	set_process(false)


func show_result(reason : int, roster : Array, local_id : int, seconds : float) -> void:
	var winner : int = MatchDirector.winner_of(reason)
	var own_team : int = Team.UNKNOWN
	for entry : Dictionary in roster:
		if entry["id"] == local_id:
			own_team = entry["team"]
		roster_box.add_child(_make_roster_line(entry))
	if own_team == Team.UNKNOWN: #not playing: a lobby process with no player
		title_label.text = "%s win" % Team.name_of(winner)
		title_label.add_theme_color_override("font_color", WIN_COLOR)
	else:
		title_label.text = "Victory" if own_team == winner else "Defeat"
		title_label.add_theme_color_override("font_color", WIN_COLOR if own_team == winner else LOSE_COLOR)
	reason_label.text = "%s win. %s" % [Team.name_of(winner), MatchDirector.describe(reason)]
	_seconds_left = seconds
	_show_countdown()
	visible = true
	set_process(true)


func _process(delta : float) -> void:
	_seconds_left = maxf(_seconds_left - delta, 0.0)
	_show_countdown()


func _show_countdown() -> void:
	countdown_label.text = "Returning to lobby in %d" % ceili(_seconds_left)


func _make_roster_line(entry : Dictionary) -> Label:
	var line : Label = Label.new()
	line.text = "%s  -  %s  -  %s" % [entry["name"], entry["role"], Team.name_of(entry["team"])]
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_color_override("font_color", ATTACKER_COLOR if entry["team"] == Team.ATTACKERS else DEFENDER_COLOR)
	line.add_theme_color_override("font_outline_color", Color(0.023529412, 0.03137255, 0.047058824))
	line.add_theme_constant_override("outline_size", 6)
	line.add_theme_font_size_override("font_size", 18)
	return line
