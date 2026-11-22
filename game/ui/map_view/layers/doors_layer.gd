class_name DoorsLayer
extends MapLayer

##Every door, coloured by its state: open, closed or locked. A door whose change is on its way blinks. When `interactive`, hovering one highlights it
##and clicking it asks `control` to flip it (the lobby decides, then every peer switches it on the same tick). Without a control (a bare test) a
##click flips the door locally.

const OPEN_COLOUR : Color = Palette.OK
const CLOSED_COLOUR : Color = Palette.ALARM
const LOCKED_COLOUR : Color = Palette.BACKUP
const MIN_THICKNESS_PX : float = 5.0 #doors are a wall thick, too thin to see or click when zoomed out
const MIN_LENGTH_PX : float = 12.0
const CLICK_SLACK_PX : float = 7.0

signal door_toggled(door : FacilityDoor) #a click asked for this door to flip

@export var interactive : bool = true

var control : FacilityControl
var _hover : FacilityDoor


##Asks for a door to flip, the way a click does. Returns false for a locked door or one already switching.
func toggle_door(door : FacilityDoor) -> bool:
	if door.state == FacilityDoor.State.LOCKED or (control != null and control.is_pending(door)):
		return false
	var target : FacilityDoor.State = FacilityDoor.State.OPEN if door.state == FacilityDoor.State.CLOSED else FacilityDoor.State.CLOSED
	if control != null:
		control.request_door(door, target)
	else:
		door.state = target
	door_toggled.emit(door)
	queue_redraw()
	return true


##The door at a world position, if any (the click area is a little bigger than the door).
func door_at(world : Vector2) -> FacilityDoor:
	var map : FacilityMap = facility()
	if map == null:
		return null
	var best : FacilityDoor = null
	var best_distance : float = INF
	for door in map.doors:
		var rect : Rect2 = door_rect(door)
		if not rect.grow(px(CLICK_SLACK_PX)).has_point(world):
			continue
		var distance : float = rect.get_center().distance_to(world)
		if distance < best_distance:
			best = door
			best_distance = distance
	return best


##A door's rectangle in world pixels, made no smaller than can be seen and clicked at the current zoom.
func door_rect(door : FacilityDoor) -> Rect2:
	var length : float = maxf(FacilityDoor.LENGTH_PX, px(MIN_LENGTH_PX))
	var thickness : float = maxf(FacilityTileSet.TILE * 2.0, px(MIN_THICKNESS_PX))
	var size_px : Vector2 = Vector2(length, thickness) if door.horizontal else Vector2(thickness, length)
	return Rect2(door.position - size_px / 2.0, size_px)


func map_hover(world : Vector2) -> void:
	var now : FacilityDoor = door_at(world) if interactive else null
	if now != _hover:
		_hover = now
		queue_redraw()


func map_click(world : Vector2) -> bool:
	if not interactive:
		return false
	var door : FacilityDoor = door_at(world)
	if door == null:
		return false
	toggle_door(door)
	return true


func _draw() -> void:
	var map : FacilityMap = facility()
	if map == null:
		return
	for door in map.doors:
		var rect : Rect2 = door_rect(door)
		var colour : Color = [OPEN_COLOUR, CLOSED_COLOUR, LOCKED_COLOUR][door.state]
		if control != null and control.is_pending(door): #switching: blink while the change is on its way
			colour = colour.lerp(Palette.TEXT, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0))
		if door == _hover:
			draw_rect(rect.grow(px(4.0)), Color(colour, 0.35))
		draw_rect(rect.grow(px(1.5)), Palette.VOID)
		draw_rect(rect, colour)
