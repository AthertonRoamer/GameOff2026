class_name LightsLayer
extends MapLayer

##The rooms' ceiling lights: a lit room is washed in light colour, and a light whose change is on its way blinks. When `interactive`, hovering a room
##outlines it and clicking it asks `control` to switch its light (the lobby decides, then every peer switches it on the same tick). Put it under the
##DoorsLayer, so a click on a door still works the door. Without a control nothing can be switched.

const ON_COLOUR : Color = Palette.FLASH

signal light_toggled(index : int) #a click asked for this light to switch

@export var interactive : bool = true

var control : FacilityControl
var _hover : int = -1


##Asks for a light to switch, the way a click does. Returns false for no light, no control, or one already switching.
func toggle_light(index : int) -> bool:
	if control == null or index < 0 or index >= control.light_count() or control.is_light_pending(index):
		return false
	control.request_light(index, not control.is_light_on(index))
	light_toggled.emit(index)
	queue_redraw()
	return true


##The light of the room at a world position, or -1.
func light_at(world : Vector2) -> int:
	var map : FacilityMap = facility()
	return map.light_of_room(map.room_at(world)) if map != null else -1


func map_hover(world : Vector2) -> void:
	var now : int = light_at(world) if interactive else -1
	if now != _hover:
		_hover = now
		queue_redraw()


func map_click(world : Vector2) -> bool:
	if not interactive:
		return false
	var index : int = light_at(world)
	if index < 0:
		return false
	toggle_light(index)
	return true


func _process(_delta : float) -> void:
	if visible:
		queue_redraw() #(lights change, and a switching one blinks)


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null or control == null:
		return
	for index in mini(control.light_count(), map.light_rooms.size()):
		var on : bool = control.is_light_on(index)
		var alpha : float = 0.3 if on else 0.0
		if control.is_light_pending(index): #switching: blink while the change is on its way
			alpha = 0.15 + 0.15 * sin(Time.get_ticks_msec() / 60.0)
		var rects : Array[Rect2] = room_rects(map.light_rooms[index])
		if alpha > 0.0:
			for rect : Rect2 in rects:
				draw_rect(rect, Color(ON_COLOUR, alpha))
		if index == _hover:
			var no_power : bool = not on and control.power != null and not control.power.can_afford(control.light_region(index), control.power.light_cost())
			for rect : Rect2 in rects:
				draw_rect(rect, Palette.ALARM if no_power else ON_COLOUR, false, px(2.0))
			if no_power and not rects.is_empty(): #switching it on would be refused: say so before the click
				draw_label(rects[0].get_center() + Vector2(0.0, px(16.0)), "NO POWER", 11, Palette.ALARM, 90.0)
