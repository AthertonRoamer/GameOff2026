class_name PingOverlay
extends Control

##The pings (MapIntel.pings) in the world, drawn on the HUD over where they are, so darkness and walls do not hide them. One off the screen sits on its edge,
##with the way to it and how far it is.

@export var edge_margin : float = 36.0 ## how far in from the screen's edge an off screen ping is held
@export var font_size : int = 15

var intel : MapIntel
var viewer : Callable = Callable() ## () -> this peer's own Player, or null


func _process(_delta : float) -> void:
	queue_redraw()


func _draw() -> void:
	if intel == null:
		return
	var to_screen : Transform2D = get_viewport().get_canvas_transform()
	var inner : Rect2 = Rect2(Vector2.ZERO, size).grow(-edge_margin)
	var font : Font = get_theme_default_font()
	var me : Variant = viewer.call() if viewer.is_valid() else null
	for ping : Dictionary in intel.pings:
		var true_at : Vector2 = to_screen * (ping["at"] as Vector2)
		var at : Vector2 = true_at.clamp(inner.position, inner.end)
		var colour : Color = PingsLayer.colour_of(ping["channel"])
		var pulse : float = fposmod((Time.get_ticks_msec() - int(ping["born"])) / 900.0, 1.0)
		draw_arc(at, 9.0 + pulse * 16.0, 0.0, TAU, 28, Color(colour, 1.0 - pulse), 2.0)
		var diamond : PackedVector2Array = PackedVector2Array([at + Vector2(0, -9), at + Vector2(7, 0), at + Vector2(0, 9), at + Vector2(-7, 0)])
		draw_colored_polygon(diamond, colour)
		draw_polyline(diamond + PackedVector2Array([diamond[0]]), Palette.VOID, 2.0)
		var caption : String = PingsLayer.caption(ping)
		if at != true_at: #off screen: an arrow the way it is
			var way : Vector2 = (true_at - at).normalized()
			draw_colored_polygon(PackedVector2Array([at + way * 24.0, at + way * 13.0 + way.orthogonal() * 7.0, at + way * 13.0 - way.orthogonal() * 7.0]), colour)
		if is_instance_valid(me):
			caption += "  %d m" % roundi((me as Node2D).global_position.distance_to(ping["at"]) / Acoustics.PX_PER_METRE)
		var text_size : Vector2 = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_at : Vector2 = Vector2(clampf(at.x - text_size.x / 2.0, 6.0, maxf(size.x - text_size.x - 6.0, 6.0)), at.y - 18.0 if at.y > edge_margin + 24.0 else at.y + 34.0)
		draw_string_outline(font, text_at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Palette.VOID)
		draw_string(font, text_at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
