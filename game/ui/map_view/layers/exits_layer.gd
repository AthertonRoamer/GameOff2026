class_name ExitsLayer
extends MapLayer

##The exit zones. Each is outlined faintly; the `highlighted` one (the designated exit, for a player allowed to know it) is filled and labelled,
##or with `outline_only`, outlined in green and labelled.

const COLOUR : Color = Palette.OK

@export var show_all : bool = true #off: only the highlighted exit is drawn
@export var outline_only : bool = false #the highlighted exit is outlined, not filled

var highlighted : String = "" : set = set_highlighted


func set_highlighted(value : String) -> void:
	highlighted = value
	queue_redraw()


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null:
		return
	for id : String in map.exits:
		var is_designated : bool = id == highlighted
		if not is_designated and not show_all:
			continue
		var bounds : Rect2
		var first : bool = true
		for cells : Rect2i in map.exits[id]:
			var rect : Rect2 = Rect2(Vector2(cells.position * FacilityTileSet.TILE), Vector2(cells.size * FacilityTileSet.TILE))
			bounds = rect if first else bounds.merge(rect)
			first = false
			if is_designated:
				if not outline_only:
					var pulse : float = 0.35 + 0.15 * sin(Time.get_ticks_msec() / 250.0)
					draw_rect(rect, Color(COLOUR, pulse))
				draw_rect(rect, COLOUR, false, px(2.5))
			else:
				draw_rect(rect, Color(Palette.METAL, 0.6), false, px(1.0))
		if is_designated and not first:
			draw_label(bounds.get_center() + Vector2(0.0, -bounds.size.y / 2.0 - px(10.0)), "EXIT", 12, COLOUR)
