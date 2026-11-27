@tool
class_name Generator
extends StaticBody2D

##A backup generator, seen from above. Put generator.tscn under the map's Props node, standing in a room. When it runs it gives power points per second
##(see PowerGrid), either to the region of the room it stands in (scope REGION) or to the whole map's shared pool (WHOLE_MAP).
##
##A guard starts it by holding E on it (a progress bar fills); it is off at the start of a match unless `starts_running` is ticked. It is solid: it
##blocks players and shots, and a shot that ends on it damages it (it is in HitscanManager.SHOOTABLE_GROUP). Shot down to nothing it stops, and a guard
##can repair it by holding E longer, which brings it back running at full health.
##It only draws and asks: what state it is in is decided by the lobby (PowerGrid), which tells every peer.
##Numbers left at -1 come from the level's PowerSettings (power_settings.tres), so most generators need no settings of their own.

enum Scope { REGION, WHOLE_MAP }
enum State { OFF, RUNNING, DESTROYED }

const SIZE : Vector2 = Vector2(52.0, 34.0) #the cabinet, in world pixels (44 per metre)
const LAMP_OFF : Color = Color("#2a313d")
const ART : Texture2D = preload("res://game/power/art/generator.png") #drawn by tools/art/make_generator.py
const ART_BROKEN : Texture2D = preload("res://game/power/art/generator_broken.png")
const LAMP_AT : Vector2 = Vector2(20.0, -10.0) #where the art has its lamp socket, gauge, fan and a clear corner, in world pixels from the middle
const GAUGE_AT : Vector2 = Vector2(11.5, 7.5)
const FAN_AT : Vector2 = Vector2(-0.25, 0.0)
const MARK_AT : Vector2 = Vector2(20.5, 10.0)

@export var scope : Scope = Scope.REGION : set = _set_scope ## REGION: powers the region of the room it stands in. WHOLE_MAP: powers the shared pool every region draws on
@export var starts_running : bool = false : set = _set_starts_running ## running when the match starts, without anyone holding E on it
@export_range(-1.0, 500.0, 1.0, "or_greater") var output_override : float = -1.0 ## points per second; -1 uses PowerSettings
@export_range(-1.0, 2000.0, 1.0, "or_greater") var health_override : float = -1.0 ## damage it takes to go down; -1 uses PowerSettings
@export_range(-1.0, 60.0, 0.1) var start_seconds_override : float = -1.0 ## how long E is held to start it; -1 uses PowerSettings
@export_range(-1.0, 60.0, 0.1) var repair_seconds_override : float = -1.0 ## how long E is held to repair it; -1 uses PowerSettings
@export_range(0.0, 60.0, 0.1, "suffix:s") var stop_seconds : float = 2.0 ## how long E is held to turn a running one off
@export var reach_m : float = 1.3 ## how close a player has to be to work it, from its middle
@export_range(0.0, 3.0, 0.05, "suffix:m") var height : float = 1.2 ## how tall it is: its shadow falls on lower things in a flashlight beam (see LightLayers), never in a ceiling light

var grid : PowerGrid #set by the grid when it finds the generator
var index : int = -1 #its place among the grid's generators (the same on every peer: the scene is the same)
var region : String = "" #the region of the room it stands in, set by the grid
var state : State = State.OFF : set = _set_state
var health : float = 0.0 : set = _set_health

var _time : float = 0.0

@onready var _light : PointLight2D = get_node_or_null("Light")


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	collision_layer = FacilityTileSet.WORLD_LAYER | FacilityTileSet.PROP_LAYER #solid like a wall: stops players and shots; and furniture: shadows in flashlight beams (its Occluder), none in room lights
	collision_mask = 0
	var tier : LightLayers.Tier = LightLayers.tier_of(height)
	light_mask = LightLayers.receiver_layer(tier) #lit by the flashlight beam for its height, like furniture
	($Occluder as LightOccluder2D).occluder_light_mask = LightLayers.caster_layer(tier) #shades lower things only, in flashlights
	if Engine.is_editor_hint():
		return
	add_to_group(PlayerInteractor.GROUP)
	add_to_group(HitscanManager.SHOOTABLE_GROUP)
	_apply_light()


func _process(delta : float) -> void:
	_time += delta
	if not Engine.is_editor_hint() and _light != null and state == State.RUNNING:
		_light.energy = 0.55 + 0.08 * sin(_time * 9.0) #the hum of a running engine
	queue_redraw()


# ------------------------------------------------------------------ the numbers (from the settings unless overridden)
func output() -> float:
	if output_override >= 0.0:
		return output_override
	if _settings() == null:
		return 0.0
	return _settings().whole_map_generator_output if scope == Scope.WHOLE_MAP else _settings().region_generator_output


func max_health() -> float:
	return health_override if health_override > 0.0 else (_settings().generator_health if _settings() != null else 100.0)


func start_seconds() -> float:
	return start_seconds_override if start_seconds_override >= 0.0 else (_settings().start_seconds if _settings() != null else 4.0)


func repair_seconds() -> float:
	return repair_seconds_override if repair_seconds_override >= 0.0 else (_settings().repair_seconds if _settings() != null else 8.0)


func is_running() -> bool:
	return state == State.RUNNING


##What it gives now: its output while running, nothing otherwise.
func supply() -> float:
	return output() if state == State.RUNNING else 0.0


# ------------------------------------------------------------------ interactable (see PlayerInteractor)
func get_prompt() -> String:
	if state == State.RUNNING:
		return "Hold E   turn off the generator"
	var what : String = "repair the generator" if state == State.DESTROYED else "start the generator"
	return "Hold E   %s (%s)" % [what, "whole facility" if scope == Scope.WHOLE_MAP else (grid.facility.region_name(region) if grid != null else region)]


func is_in_reach(world_position : Vector2) -> bool:
	if global_position.distance_to(world_position) > reach_m * 44.0 + SIZE.x / 2.0:
		return false
	if not is_inside_tree():
		return true
	var query : PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(world_position, global_position, FacilityTileSet.WORLD_LAYER | FacilityTileSet.DOOR_LAYER)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


##Anyone can switch a running generator off by hand. Only guards start or repair one (a player with no role, in the playground, counts as one).
func can_interact(player : Node) -> bool:
	if grid == null:
		return false
	if state == State.RUNNING:
		return true
	var role : Role = player.get("role")
	return role == null or role.kind == Role.Kind.GUARD


func hold_seconds(_player : Node) -> float:
	if state == State.RUNNING:
		return stop_seconds
	return repair_seconds() if state == State.DESTROYED else start_seconds()


func hold_started(_player : Node) -> void:
	if grid != null:
		grid.request_hold(self, true)


func hold_cancelled(_player : Node) -> void:
	if grid != null:
		grid.request_hold(self, false)


##The hold finished: ask the lobby to start it (it checks the hold took long enough).
func interact(_player : Node) -> Control:
	if grid != null:
		grid.request_finish(self)
	return null


##A shot ended on it. Lobby only (HitscanManager and ProjectileManager only report hits there); the grid tells every peer.
func take_damage(damage : float, _direction : Vector2 = Vector2.ZERO) -> void:
	if grid != null:
		grid.damage_generator(self, damage)


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var running : bool = state == State.RUNNING or (Engine.is_editor_hint() and starts_running)
	var art : Texture2D = ART_BROKEN if state == State.DESTROYED else ART
	var art_size : Vector2 = art.get_size() * FacilityTileSet.ART_SCALE
	draw_texture_rect(art, Rect2(-art_size / 2.0, art_size), false) #(its soft shadow is in the picture)
	if running: #the fan turns
		for i in 3:
			var blade : Vector2 = Vector2.from_angle(_time * 14.0 + i * TAU / 3.0)
			draw_line(FAN_AT + blade * 2.2, FAN_AT + blade * 6.2, Color(0.75, 0.8, 0.88, 0.55), 1.3, true)
	var swing : float = 150.0 #the gauge's needle, in degrees: at rest, up when running, twitching when broken
	if running:
		swing = 315.0 + 7.0 * sin(_time * 11.0)
	elif state == State.DESTROYED:
		swing = 165.0 + 12.0 * maxf(sin(_time * 3.0), 0.0)
	draw_line(GAUGE_AT, GAUGE_AT + Vector2.from_angle(deg_to_rad(swing)) * 2.6, Palette.ALARM, 0.7, true)
	var lamp : Color = LAMP_OFF
	if running:
		lamp = Palette.BACKUP.lerp(Palette.FLASH, 0.25 + 0.25 * sin(_time * 9.0))
	elif state == State.DESTROYED:
		lamp = Palette.ALARM if fmod(_time, 0.8) < 0.4 else Palette.ALARM.darkened(0.6)
	if lamp != LAMP_OFF:
		draw_circle(LAMP_AT, 3.2, Color(lamp, 0.28))
	draw_circle(LAMP_AT, 1.6, lamp)
	var mark : Color = Palette.ITEM #the scope, on the cabinet: a ring for the whole map, a dot for a region
	if scope == Scope.WHOLE_MAP:
		draw_arc(MARK_AT, 2.8, 0.0, TAU, 16, mark, 1.3, true)
	else:
		draw_circle(MARK_AT, 1.1, Palette.VOID) #(small and dark, so it is not taken for a second lamp)
	if not Engine.is_editor_hint() and state != State.OFF and health < max_health(): #damage: a bar over it
		var bar : Rect2 = Rect2(-SIZE / 2.0 + Vector2(0.0, -9.0), Vector2(SIZE.x, 4.0))
		draw_rect(bar, Palette.VOID)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(health / max_health(), 0.0, 1.0), bar.size.y)), Palette.ALARM if health < max_health() * 0.35 else Palette.BACKUP)
	if Engine.is_editor_hint():
		var text : String = ("MAP" if scope == Scope.WHOLE_MAP else "REGION") + (" - ON" if starts_running else "")
		draw_string(ThemeDB.fallback_font, Vector2(-SIZE.x / 2.0, SIZE.y / 2.0 + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.BACKUP if starts_running else Palette.MUTED)


func _get_configuration_warnings() -> PackedStringArray:
	var map : FacilityMap = _map()
	if map == null:
		return PackedStringArray()
	var at : Vector2 = map.to_local(global_position)
	if map.room_at(at) == "":
		return PackedStringArray(["This generator is not on any room's floor. Drag it into a room."])
	if scope == Scope.REGION and map.region_at(at) == "":
		return PackedStringArray(["This region generator stands in a room that is in no region, so it powers nothing. Put the room in a region, or set scope to Whole map."])
	return PackedStringArray()


func _set_state(value : State) -> void:
	state = value
	_apply_light()
	queue_redraw()


func _set_health(value : float) -> void:
	health = value
	queue_redraw()


func _set_scope(value : Scope) -> void:
	scope = value
	queue_redraw()
	update_configuration_warnings()


func _set_starts_running(value : bool) -> void:
	starts_running = value
	queue_redraw()


func _apply_light() -> void:
	if _light == null or Engine.is_editor_hint():
		return
	_light.visible = state != State.OFF
	_light.color = Palette.ALARM if state == State.DESTROYED else Palette.BACKUP
	_light.energy = 0.3 if state == State.DESTROYED else 0.55


func _settings() -> PowerSettings:
	if grid != null and grid.settings != null:
		return grid.settings
	return PowerGrid.DEFAULT_SETTINGS


func _map() -> FacilityMap:
	var node : Node = get_parent()
	while node != null and not node is FacilityMap:
		node = node.get_parent()
	return node as FacilityMap


func _notification(what : int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()
	elif what == NOTIFICATION_ENTER_TREE and Engine.is_editor_hint():
		set_notify_transform(true)
