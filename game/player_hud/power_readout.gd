class_name PowerReadout
extends Control

##The guard's power readout on the HUD: the region the player is standing in, and the power still free there out of what it could have, in points per
##second, with a bar. Red when not even the cheapest thing could be switched on. Only guards see it (every guard, so a secret attacker among them
##is not given away by a missing readout). Set `grid` and `player` (PlayerHud.bind_power / bind_player).

const CHECK_SECONDS : float = 0.25 #how often it looks which region the player is in

var grid : PowerGrid : set = set_grid
var player : Player

var _region : String = "?" #(not a region id: the first check always redraws)
var _since : float = CHECK_SECONDS
var _font : Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	visible = false


func set_grid(value : PowerGrid) -> void:
	if grid != null and grid.changed.is_connected(queue_redraw):
		grid.changed.disconnect(queue_redraw)
	grid = value
	if grid != null:
		grid.changed.connect(queue_redraw)
	queue_redraw()


##Guards see the power (a player with no role, in the playground, counts as one).
static func shows_power_to(who : Node) -> bool:
	if who == null or not is_instance_valid(who):
		return false
	var role : Role = who.get("role")
	return role == null or role.kind == Role.Kind.GUARD


func _process(delta : float) -> void:
	visible = grid != null and shows_power_to(player)
	if not visible:
		return
	_since += delta
	if _since < CHECK_SECONDS:
		return
	_since = 0.0
	var now : String = grid.facility.region_at(grid.facility.to_local(player.global_position))
	if now != _region:
		_region = now
		queue_redraw()


func _draw() -> void:
	if grid == null or _region == "?":
		return
	var map : FacilityMap = grid.facility
	var free : float = grid.available(_region)
	var most : float = grid.capacity(_region)
	var short : bool = free + 0.0001 < grid.settings.cheapest_cost()
	var colour : Color = Palette.ALARM if short else Palette.BACKUP
	var box : Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(box, Color(Palette.SHADOW, 0.8))
	draw_rect(box, Palette.PANEL_LINE, false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(5.0, size.y)), map.region_colour(_region))
	draw_string(_font, Vector2(14.0, 17.0), map.region_name(_region).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 12, Palette.MUTED)
	var text : String = "POWER  %d / %d" % [floori(free), roundi(most)]
	draw_string(_font, Vector2(14.0, 35.0), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 16, colour)
	draw_string(_font, Vector2(size.x - 50.0, 35.0), "pts/s", HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 11, Palette.MUTED)
	var bar : Rect2 = Rect2(Vector2(14.0, size.y - 8.0), Vector2(size.x - 24.0, 4.0))
	draw_rect(bar, Palette.DEEP)
	if most > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(free / most, 0.0, 1.0), bar.size.y)), colour)
