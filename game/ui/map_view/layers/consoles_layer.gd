class_name ConsolesLayer
extends MapLayer

##The control panels (every ControlPanel under the map's Props): a small screen symbol, with what it works under it when `show_names` is on.

const COLOUR : Color = Palette.ITEM

@export var show_names : bool = true
@export var size_px : float = 9.0 ## the symbol's size on screen
@export var names_from_zoom : float = 0.3 ## no names further out than this: they pile up on each other

var _found : Array[ControlPanel] = []
var _found_in : FacilityMap


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null or map.props_node == null:
		return
	if _found_in != map: #(looked for once: the big map has thousands of things under Props)
		_found_in = map
		_found.clear()
		for node : Node in map.props_node.find_children("*", "StaticBody2D", true, false):
			if node is ControlPanel:
				_found.append(node)
	for panel in _found:
		if not is_instance_valid(panel):
			continue
		var at : Vector2 = map.to_local(panel.global_position)
		var half : float = px(size_px) / 2.0
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0).grow(px(1.5)), Palette.VOID)
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), COLOUR)
		draw_rect(Rect2(at - Vector2(half * 0.5, half * 0.5), Vector2(half, half * 0.7)), Palette.VOID)
		if show_names and view.zoom >= names_from_zoom:
			var what : String = panel.function if panel.function != "" else "console"
			draw_label(at + Vector2(0.0, px(size_px + 4.0)), what.to_upper() + " PANEL", 10, COLOUR, 120.0)


func icon_label(world : Vector2) -> String:
	var map : FacilityMap = facility()
	if map == null:
		return ""
	var reach : float = px(size_px / 2.0 + 4.0)
	for panel in _found:
		if is_instance_valid(panel) and map.to_local(panel.global_position).distance_to(world) <= reach:
			return ("%s panel" % panel.function.capitalize()) if panel.function != "" else "Console"
	return ""
