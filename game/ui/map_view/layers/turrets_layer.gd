class_name TurretsLayer
extends MapLayer

##The turrets. On most maps (the minimap, the full map) every turret looks the same whatever it is doing: a small wedge pointing where it watches. Whether one
##is switched on is the door console's to know. There (`interactive`), each is coloured by its state (grey off, amber warming up, green on, red cross shot down,
##blinking while a change is on its way), hovering one shows the cone it watches, and clicking it asks `control` to switch it (the lobby decides and checks the
##power, then every peer switches it on the same tick, like a light). Finds the TurretSystem by its group when nobody sets `system`.

signal turret_toggled(index : int) #a click asked for this turret to switch

const ON_COLOUR : Color = Palette.OK
const OFF_COLOUR : Color = Palette.MUTED
const WARMING_COLOUR : Color = Palette.BACKUP
const DESTROYED_COLOUR : Color = Palette.ALARM
const PLAIN_COLOUR : Color = Palette.ACCENT_BLUE #every turret on a map that does not show their state

@export var interactive : bool = false
@export var size_px : float = 12.0 ## a turret's icon on screen

var control : FacilityControl
var system : TurretSystem
var _hover : int = -1


func _turret_system() -> TurretSystem:
	if system == null and is_inside_tree():
		system = get_tree().get_first_node_in_group(TurretSystem.GROUP) as TurretSystem
	return system


func _control() -> FacilityControl:
	if control != null:
		return control
	return _turret_system().control if _turret_system() != null else null


##Asks for a turret to switch, the way a click does. Returns false for no turret, no control, or one already switching.
func toggle_turret(index : int) -> bool:
	var c : FacilityControl = _control()
	if c == null or index < 0 or index >= c.turret_count() or c.is_turret_pending(index):
		return false
	c.request_turret(index, not c.is_turret_on(index))
	turret_toggled.emit(index)
	queue_redraw()
	return true


##The turret whose icon is at a world position (map space), or -1.
func turret_at(world : Vector2) -> int:
	var map : FacilityMap = facility()
	var s : TurretSystem = _turret_system()
	if map == null or s == null:
		return -1
	var best : int = -1
	var best_distance : float = px(size_px / 2.0 + 5.0)
	for turret in s.turrets:
		if not is_instance_valid(turret):
			continue
		var distance : float = map.to_local(turret.global_position).distance_to(world)
		if distance <= best_distance:
			best = turret.index
			best_distance = distance
	return best


func map_hover(world : Vector2) -> void:
	var now : int = turret_at(world) if interactive else -1
	if now != _hover:
		_hover = now
		queue_redraw()


func map_click(world : Vector2) -> bool:
	if not interactive:
		return false
	var index : int = turret_at(world)
	if index < 0:
		return false
	toggle_turret(index)
	return true


func _process(_delta : float) -> void:
	if interactive and is_visible_in_tree():
		queue_redraw() #(a switching turret blinks)


func _draw() -> void:
	var map : FacilityMap = facility()
	var s : TurretSystem = _turret_system()
	if map == null or s == null:
		return
	var c : FacilityControl = _control()
	for turret in s.turrets:
		if not is_instance_valid(turret):
			continue
		var at : Vector2 = map.to_local(turret.global_position)
		var facing : float = turret.facing() - map.global_rotation
		var colour : Color = PLAIN_COLOUR
		if interactive:
			colour = state_colour(turret, c)
			if c != null and c.is_turret_pending(turret.index):
				colour.a = 0.45 + 0.45 * sin(Time.get_ticks_msec() / 60.0)
			if turret.index == _hover: #the cone it watches
				var settings : TurretSettings = turret.the_settings()
				var half : float = settings.fov_radians() / 2.0
				var cone : PackedVector2Array = PackedVector2Array([at])
				for i in 17:
					cone.append(at + Vector2.from_angle(facing - half + 2.0 * half * i / 16.0) * settings.range_px)
				draw_colored_polygon(cone, Color(colour, 0.12))
				draw_polyline(cone + PackedVector2Array([at]), Color(colour, 0.5), px(1.0), true)
				var no_power : bool = c != null and not c.is_turret_on(turret.index) and not turret.is_destroyed() and c.power != null \
					and not c.power.can_afford(c.turret_region(turret.index), c.power.turret_cost())
				if no_power:
					draw_label(at + Vector2(0.0, px(18.0)), "NO POWER FOR A TURRET", 11, Palette.ALARM, 160.0)
		_draw_icon(at, facing, colour, interactive and turret.is_destroyed())


##What colour a turret is on the door console: grey off, amber warming up, green on, red shot down.
static func state_colour(turret : Turret, c : FacilityControl) -> Color:
	if turret.is_destroyed():
		return DESTROYED_COLOUR
	if c == null or not c.is_turret_on(turret.index):
		return OFF_COLOUR
	return WARMING_COLOUR if turret.phase == Turret.Phase.WARMING or turret.phase == Turret.Phase.OFF else ON_COLOUR


## A wedge pointing where it watches, on a dark disc. Shot down (on the console only): a cross over it.
func _draw_icon(at : Vector2, facing : float, colour : Color, crossed : bool) -> void:
	var r : float = px(size_px) / 2.0
	draw_circle(at, r + px(1.5), Palette.VOID)
	draw_circle(at, r, Color(colour, 0.25 * colour.a))
	var tip : Vector2 = at + Vector2.from_angle(facing) * r * 1.5
	var left : Vector2 = at + Vector2.from_angle(facing + 2.4) * r * 0.85
	var right : Vector2 = at + Vector2.from_angle(facing - 2.4) * r * 0.85
	draw_colored_polygon(PackedVector2Array([tip, left, right]), colour)
	draw_circle(at, r * 0.35, Palette.VOID)
	if crossed:
		draw_line(at + Vector2(-r, -r), at + Vector2(r, r), Palette.FLASH, px(2.0))
		draw_line(at + Vector2(-r, r), at + Vector2(r, -r), Palette.FLASH, px(2.0))


func icon_label(world : Vector2) -> String:
	var index : int = turret_at(world)
	if index < 0:
		return ""
	if not interactive:
		return "Turret"
	var turret : Turret = _turret_system().turrets[index]
	var c : FacilityControl = _control()
	var state : String = "off"
	if turret.is_destroyed():
		state = "shot down"
	elif c != null and c.is_turret_pending(index):
		state = "switching"
	elif c != null and c.is_turret_on(index):
		state = "warming up" if turret.phase == Turret.Phase.WARMING or turret.phase == Turret.Phase.OFF else "on"
	var region : String = turret.region
	var where : String = "no region" if region == "" else (facility().region_name(region) if facility() != null else region)
	return "Turret: %s (%s) - click to switch" % [state, where] if not turret.is_destroyed() else "Turret: shot down (%s) - repair it by hand" % where
