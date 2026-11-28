class_name MapLayer
extends Node2D

##One thing drawn on a FacilityMapView: rooms, doors, spawn rooms, exits, a player's dot... Put layers under the FacilityMapView in a screen's
##scene, in drawing order. A layer draws in world pixels in its own _draw() (the view scrolls and zooms them all), and uses px() for anything that
##should stay the same size on screen at any zoom (line widths, dots) and draw_label() for text. Override map_click() to take clicks and
##map_hover() to follow the mouse. The view redraws its layers when it moves, and every frame while it is `live`.

@export_group("Zoomed out")
@export var fade_full_zoom : float = 0.0 ## drawn in full at this zoom and closer. 0: never fades
@export var fade_out_zoom : float = 0.0 ## faded as far as it goes at this zoom and further out
@export_range(0.0, 1.0, 0.05) var faded_alpha : float = 0.0 ## how strongly it is still drawn then

var view : FacilityMapView #set by the view


## How strongly the layer is drawn at a zoom (the view sets it), so the small things make way for the rooms as the map zooms out.
func zoom_alpha(zoom : float) -> float:
	if fade_full_zoom <= fade_out_zoom:
		return 1.0
	return lerpf(faded_alpha, 1.0, clampf(inverse_lerp(fade_out_zoom, fade_full_zoom, zoom), 0.0, 1.0))


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


##What the icon drawn at this world position is ("Door", "Generator: running"...), or "" when there is none of this layer's there. The view shows it by the mouse.
func icon_label(_world : Vector2) -> String:
	return ""


##True for a layer whose labels name whole areas (a room, a zone) rather than small icons: the view asks it only after every icon layer, so an icon inside
##a labelled room (a turret in a spawn room) still gets its own label.
func labels_areas() -> bool:
	return false


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
