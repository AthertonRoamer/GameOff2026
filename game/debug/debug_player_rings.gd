class_name DebugPlayerRings
extends CanvasLayer

##Debug view: draws a ring in each player's role colour, and a green (defender) or red (attacker) ring around each player whose team this peer knows.
##Its own canvas layer that follows the camera (like the level's ProjectileLayer), so the level's darkness doesn't dim the rings.
##Game creates it only while one of its ring debug settings is on.

const ROLE_RADIUS : float = 20.0 #the body is 12 px, the role ring sits just outside it
const TEAM_RADIUS : float = 26.0 #outside the role ring, so both show at once
const WIDTH : float = 2.0
const ATTACKER_COLOR : Color = Color(1.0, 0.15, 0.15)
const DEFENDER_COLOR : Color = Color(0.2, 1.0, 0.3)

var players : Callable #() -> Array of Player
var show_roles : bool = false
var show_teams : bool = false

var _drawer : Node2D = Node2D.new()


func _ready() -> void:
	follow_viewport_enabled = true
	add_child(_drawer)
	_drawer.draw.connect(_draw_rings)


func _process(_delta : float) -> void:
	_drawer.queue_redraw()


func _draw_rings() -> void:
	if not players.is_valid():
		return
	for player : Player in players.call():
		if not is_instance_valid(player) or not player.visible or not player.is_alive():
			continue
		var at : Vector2 = player.global_position
		if show_roles and player.role != null:
			_drawer.draw_arc(at, ROLE_RADIUS, 0.0, TAU, 48, player.role.color, WIDTH)
		if show_teams and player.team != Team.UNKNOWN:
			_drawer.draw_arc(at, TEAM_RADIUS, 0.0, TAU, 48, ATTACKER_COLOR if player.team == Team.ATTACKERS else DEFENDER_COLOR, WIDTH)
