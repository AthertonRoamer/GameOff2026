class_name RadarDisplay
extends Node2D

##The radar, for the local player. While they carry one (RadarItem, in any slot), it sends a pulse every pulse_seconds: a ring goes out round them, and every other
##living player within range_px who is moving faster than a sneak shows as a blip where they were, all the way round and through walls, fading over blip_seconds.
##Someone standing still or sneaking does not show. Drawn on a layer of its own over the darkness. Only this peer's picture: nobody is told.

const BLIP_COLOUR : Color = Color("#58f08a")

@export_range(1.0, 30.0, 0.5, "suffix:s") var pulse_seconds : float = 9.0
@export_range(100.0, 3000.0, 10.0, "suffix:px") var range_px : float = 700.0
@export_range(0.5, 8.0, 0.1, "suffix:s") var blip_seconds : float = 2.5
@export_range(0.0, 400.0, 5.0, "suffix:px/s") var min_speed : float = 140.0 ## slower than this is not picked up (a sneak is 125 px/s, a walk 250)

var gadgets : GadgetSystem
var since_pulse : float = 0.0
var blips : PackedVector2Array = PackedVector2Array() #where the last pulse found players (world)
var pulse_from : Vector2 = Vector2.ZERO
var _pulse_age : float = 1.0e6
var _last_seen : Dictionary = {} #player -> where they were last frame
var _speeds : Dictionary = {} #player -> how fast they have been moving lately (px/s, smoothed): worked out from where they are, which every peer knows
var _label : Label


func _ready() -> void:
	var hud : CanvasLayer = CanvasLayer.new() #the readout, on the screen
	hud.layer = 3
	add_child(hud)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_label.position = Vector2(16.0, -128.0)
	_label.add_theme_font_size_override("font_size", 14)
	_label.modulate = BLIP_COLOUR
	_label.visible = false
	hud.add_child(_label)


func is_carried() -> bool:
	return gadgets != null and GadgetSystem.carries(gadgets.me(), RadarItem)


## Who a pulse from here would show: every other living player in range who is moving fast enough.
func scan(from : Player) -> PackedVector2Array:
	var found : PackedVector2Array = PackedVector2Array()
	if gadgets == null or not gadgets.players.is_valid():
		return found
	for player in gadgets.players.call():
		if not is_instance_valid(player) or player == from or not player.is_alive():
			continue
		if player.global_position.distance_to(from.global_position) > range_px or speed_of(player) < min_speed:
			continue
		found.append(player.global_position)
	return found


## How fast a player has been moving lately, px/s.
func speed_of(player : Node) -> float:
	return _speeds.get(player, (player as Player).velocity.length())


func _track(delta : float) -> void:
	if gadgets == null or not gadgets.players.is_valid() or delta <= 0.0:
		return
	for player in gadgets.players.call():
		if not is_instance_valid(player):
			continue
		var at : Vector2 = player.global_position
		var moved : float = at.distance_to(_last_seen.get(player, at)) / delta
		_last_seen[player] = at
		_speeds[player] = lerpf(_speeds.get(player, moved), moved, clampf(delta * 8.0, 0.0, 1.0))
	for key in _speeds.keys():
		if not is_instance_valid(key):
			_speeds.erase(key)
			_last_seen.erase(key)


func pulse(from : Player) -> void:
	since_pulse = 0.0
	_pulse_age = 0.0
	pulse_from = from.global_position
	blips = scan(from)


func _process(delta : float) -> void:
	var carried : bool = is_carried()
	_label.visible = carried
	_pulse_age += delta
	_track(delta)
	if not carried:
		since_pulse = 0.0
		blips = PackedVector2Array()
		queue_redraw()
		return
	since_pulse += delta
	if since_pulse >= pulse_seconds:
		pulse(gadgets.me())
	_label.text = "RADAR   next pulse %ds" % ceili(pulse_seconds - since_pulse)
	queue_redraw()


func _draw() -> void:
	if _pulse_age < blip_seconds:
		var fade : float = 1.0 - _pulse_age / blip_seconds
		var ring : float = minf(_pulse_age / 0.6, 1.0) * range_px
		draw_arc(pulse_from, ring, 0.0, TAU, 96, Color(BLIP_COLOUR, 0.5 * fade), 2.0)
		for at : Vector2 in blips:
			if at.distance_to(pulse_from) <= ring:
				draw_circle(at, 9.0, Color(BLIP_COLOUR, 0.25 * fade))
				draw_circle(at, 4.5, Color(BLIP_COLOUR, 0.9 * fade))
