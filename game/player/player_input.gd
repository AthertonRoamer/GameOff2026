class_name PlayerInput
extends NetInput

var movement : Vector2 = Vector2.ZERO
var aim : Vector2 = Vector2.ZERO
var use_item : bool = false
var run : bool = false #shift held
var holster : bool = false #the holster key (H) went down: draw or holster the active item (see Inventory)
var slot_select : int = -1
var slot_delta : int = 0
var flashlight_on : bool = true #a state, not a press: the flashlight action flips it. Sent with the input, so every peer sees the beam
var interacting : bool = false #at a console with its screen up (set by PlayerInteractor, not gathered)
var active : bool = false


func _gather() -> void:
	movement = Input.get_vector("player_left", "player_right", "player_up", "player_down") if active else Vector2.ZERO
	aim = (get_parent() as Node2D).get_global_mouse_position() if active else aim
	use_item = active and Input.is_action_pressed("player_use_active_item")
	run = active and Input.is_action_pressed("player_run")
	holster = active and Input.is_action_just_pressed("player_holster")
	slot_select = _gather_slot_select() if active else -1
	slot_delta = _gather_slot_delta() if active else 0
	if active and Input.is_action_just_pressed("player_flashlight"):
		flashlight_on = not flashlight_on


func _gather_slot_select() -> int:
	for i in range(4):
		if Input.is_action_just_pressed("inventory_slot_%d" % (i + 1)):
			return i
	return -1


func _gather_slot_delta() -> int:
	if Input.is_action_just_pressed("inventory_scroll_up"):
		return -1
	if Input.is_action_just_pressed("inventory_scroll_down"):
		return 1
	return 0
