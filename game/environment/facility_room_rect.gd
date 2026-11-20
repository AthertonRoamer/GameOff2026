@tool
class_name FacilityRoomRect
extends Control

##One rectangle of a room's floor. Select it in the 2D view and drag its handles (the usual Control handles: corners and edges) or set position and
##size in the inspector; it snaps to the map's 0.25 m grid (11 px) by itself, and the map rebuilds its floor, walls and shadows around the new size
##as soon as you let go. A room is a FacilityRoom node with one or more of these under it (a corridor that goes round the building is one room with
##several). It only exists to be edited: in the game it draws nothing and ignores the mouse. Only the position and size matter, never the art.

const TILE : int = FacilityTileSet.TILE

@export var draw_outside_editor : bool = false #shows the rectangle in a running game too, for finding out where a room really is


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(TILE, TILE)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_rect_changed.connect(_on_rect_changed)
	queue_redraw()


##This rectangle in cells (x0, y0, width, height), counted in the space of `space` (the map).
func cell_rect(space : Node2D) -> Rect2i:
	var top_left : Vector2 = space.to_local(global_position)
	return Rect2i(roundi(top_left.x / TILE), roundi(top_left.y / TILE), maxi(1, roundi(size.x / TILE)), maxi(1, roundi(size.y / TILE)))


##Puts position and size on the 11 px grid. Only writes what is off the grid, so dragging a handle is not fought over.
func snap_to_grid() -> void:
	var snapped_position : Vector2 = (position / TILE).round() * TILE
	var snapped_size : Vector2 = (size / TILE).round().max(Vector2.ONE) * TILE
	if not position.is_equal_approx(snapped_position):
		position = snapped_position
	if not size.is_equal_approx(snapped_size):
		size = snapped_size


func _on_rect_changed() -> void:
	if Engine.is_editor_hint():
		snap_to_grid()
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() and not draw_outside_editor:
		return
	var room : FacilityRoom = get_parent() as FacilityRoom
	var colour : Color = room.kind_colour() if room != null else Color.WHITE
	draw_rect(Rect2(Vector2.ZERO, size), Color(colour, 0.2))
	draw_rect(Rect2(Vector2.ZERO, size), Color(colour, 0.9), false, 2.0)
	if room != null and get_index() == 0: #the room's name goes in its first rectangle
		var label : String = room.display_name if room.display_name != "" else String(room.name)
		draw_string(ThemeDB.fallback_font, Vector2(8.0, 22.0), label, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 18, Color(colour, 1.0))
		if room.clash_with != "":
			draw_string(ThemeDB.fallback_font, Vector2(8.0, 44.0), "overlaps " + room.clash_with, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 14, Color("#e5484d"))
