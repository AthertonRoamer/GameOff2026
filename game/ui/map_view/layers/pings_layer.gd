class_name PingsLayer
extends MapLayer

##The pings (MapIntel.pings): a marker in the colour of the channel it was sent on (green guards, red intruders), with its label, or the sender's name if it has none.
##With `clamp_to_view` (the minimap) a ping outside the map's window sits on its edge, so it still shows which way it is.

const COLOURS : Array[Color] = [Color("#3ddc6a"), Color("#ff3b3b")] #by ChatRules.Channel, as the chat's tabs

@export var size_px : float = 7.0 ## the marker's radius on screen
@export var font_size : int = 12
@export var clamp_to_view : bool = false

var pings : Array[Dictionary] = []


static func colour_of(channel : int) -> Color:
	return COLOURS[clampi(channel, 0, COLOURS.size() - 1)]


static func caption(ping : Dictionary) -> String:
	return String(ping["label"]) if String(ping["label"]) != "" else String(ping["sender"])


func _process(_delta : float) -> void:
	if is_visible_in_tree():
		queue_redraw() #(they pulse and expire)


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null or view == null:
		return
	for ping : Dictionary in pings:
		var at : Vector2 = map.to_local(ping["at"])
		var inside : bool = true
		if clamp_to_view:
			var margin : Vector2 = Vector2.ONE * (size_px + 3.0)
			var low : Vector2 = view.screen_to_world(margin)
			var high : Vector2 = view.screen_to_world(view.size - margin)
			var held : Vector2 = at.clamp(low, high)
			inside = held == at
			at = held
		var colour : Color = colour_of(ping["channel"])
		var pulse : float = fposmod((Time.get_ticks_msec() - int(ping["born"])) / 900.0, 1.0)
		draw_arc(at, px(size_px * (1.0 + pulse * 1.6)), 0.0, TAU, 24, Color(colour, 1.0 - pulse), px(2.0))
		draw_circle(at, px(size_px * 0.75), Palette.VOID)
		draw_circle(at, px(size_px * 0.55), colour)
		if inside:
			var text_at : Vector2 = at - Vector2(0.0, px(size_px + 9.0))
			draw_label(text_at + Vector2.ONE * px(1.0), caption(ping), font_size, Palette.VOID, 200.0)
			draw_label(text_at, caption(ping), font_size, colour, 200.0)


func icon_label(world : Vector2) -> String:
	var map : FacilityMap = facility()
	if map == null or clamp_to_view: #(a ping held on the minimap's edge is not where it is drawn)
		return ""
	for i in range(pings.size() - 1, -1, -1):
		if map.to_local(pings[i]["at"]).distance_to(world) <= px(size_px + 3.0):
			return "Ping: %s" % caption(pings[i])
	return ""
