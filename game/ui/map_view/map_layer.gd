class_name MapLayer
extends Node2D

##One thing drawn on a FacilityMapView: rooms, doors, spawn rooms, exits, a player's dot... Put layers under the FacilityMapView in a screen's
##scene, in drawing order. A layer draws in world pixels in its own _draw() (the view scrolls and zooms them all), and uses px() for anything that
##should stay the same size on screen at any zoom (line widths, dots) and draw_label() for text. Override map_click() to take clicks and
##map_hover() to follow the mouse. The view redraws its layers when it moves, and every frame while it is `live`.

var view : FacilityMapView #set by the view


func facility() -> FacilityMap:
	return view.facility if view != null else null


##A click on the map at this world position. Return true to take it (the layers below then don't get it).
func map_click(_world : Vector2) -> bool:
	return false


##A right click on the map at this world position. Return true to take it (the layers below then don't get it).
func map_right_click(_world : Vector2) -> bool:
	return false


##The mouse moved over the map, at this world position.
func map_hover(_world : Vector2) -> void:
	pass


##A size in screen pixels as world pixels at the current zoom, so it looks the same however far in or out the map is.
func px(screen_pixels : float) -> float:
	return screen_pixels / view.zoom if view != null and view.zoom > 0.0 else screen_pixels


##Text at a world position, the same size on screen at any zoom and sharp (not scaled). `align` centres it on the point by default.
func draw_label(world : Vector2, text : String, font_size : int, colour : Color, width_px : float = 160.0, align : HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font : Font = ThemeDB.fallback_font if view == null else view.get_theme_default_font()
	var inverse : float = 1.0 / view.zoom if view != null and view.zoom > 0.0 else 1.0
	draw_set_transform(world, 0.0, Vector2.ONE * inverse)
	var x : float = -width_px / 2.0 if align == HORIZONTAL_ALIGNMENT_CENTER else 0.0
	draw_string(font, Vector2(x, font_size * 0.35), text, align, width_px, font_size, colour)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


##The world rectangles of a room, as the map has them.
func room_rects(room_id : String) -> Array[Rect2]:
	return facility().room_rects_px(room_id) if facility() != null and facility().rooms.has(room_id) else [] as Array[Rect2]
