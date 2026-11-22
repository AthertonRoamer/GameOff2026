class_name PlayerInput
extends NetInput

## What a player is doing this tick. Sent to every peer every tick, so it is kept small: the movement and the aim, and every yes-or-no and small number in ONE
## integer, `buttons` (the only thing besides the two vectors that is synced, see the player's RollbackSynchronizer). Every other variable is a property that
## reads and writes its bits, so the rest of the code uses them as it would plain variables: input.run, input.slot_select = 2.
## (Sent as eight separate values these were about four fifths of what a peer sent.)

const USE_ITEM : int = 1 << 0
const RUN : int = 1 << 1 #shift held
const HOLSTER : int = 1 << 2 #the holster key (H) went down: draw or holster the active item (see Inventory)
const FLASHLIGHT : int = 1 << 3 #a state, not a press: the flashlight action flips it. Sent with the input, so every peer sees the beam
const INTERACTING : int = 1 << 4 #at a console with its screen up (set by PlayerInteractor, not gathered)
const SLOT_SHIFT : int = 5 #3 bits: the slot chosen this tick plus one (so 0 is none)
const DELTA_SHIFT : int = 8 #2 bits: the wheel's turn this tick plus one (so 1 is none)
const LAG_SHIFT : int = 10 #6 bits: how many ticks behind the lobby this player sees the others (0 to 63), for lag compensated shots

var movement : Vector2 = Vector2.ZERO
var aim : Vector2 = Vector2.ZERO
var buttons : int = FLASHLIGHT | (1 << DELTA_SHIFT) #the flashlight starts on, no slot chosen, no wheel turn
var active : bool = false #not sent: only this peer's own player is gathered
var at_console : bool = false #not sent: this player has a console's screen up (set by PlayerInteractor). It is gathered into `interacting` every frame, like the keys: a
##flag only set once can be put back by the rollback restoring an older tick's input, and the player stays at the console after leaving it (dying there, say)

var use_item : bool:
	get: return buttons & USE_ITEM != 0
	set(value): _set_flag(USE_ITEM, value)
var run : bool:
	get: return buttons & RUN != 0
	set(value): _set_flag(RUN, value)
var holster : bool:
	get: return buttons & HOLSTER != 0
	set(value): _set_flag(HOLSTER, value)
var flashlight_on : bool:
	get: return buttons & FLASHLIGHT != 0
	set(value): _set_flag(FLASHLIGHT, value)
var interacting : bool:
	get: return buttons & INTERACTING != 0
	set(value): _set_flag(INTERACTING, value)
var slot_select : int: #the inventory slot chosen this tick, or -1
	get: return ((buttons >> SLOT_SHIFT) & 7) - 1
	set(value): buttons = (buttons & ~(7 << SLOT_SHIFT)) | ((value + 1) << SLOT_SHIFT)
var slot_delta : int: #the wheel: -1, 0 or 1
	get: return ((buttons >> DELTA_SHIFT) & 3) - 1
	set(value): buttons = (buttons & ~(3 << DELTA_SHIFT)) | ((value + 1) << DELTA_SHIFT)


var view_lag : int: #ticks this player sees the others behind the lobby: half the round trip, plus the display offset
	get: return (buttons >> LAG_SHIFT) & 63
	set(value): buttons = (buttons & ~(63 << LAG_SHIFT)) | (clampi(value, 0, 63) << LAG_SHIFT)


func _gather() -> void:
	movement = Input.get_vector("player_left", "player_right", "player_up", "player_down") if active else Vector2.ZERO
	aim = (get_parent() as Node2D).get_global_mouse_position() if active else aim
	use_item = active and Input.is_action_pressed("player_use_active_item")
	run = active and Input.is_action_pressed("player_run")
	holster = active and Input.is_action_just_pressed("player_holster")
	slot_select = _gather_slot_select() if active else -1
	slot_delta = _gather_slot_delta() if active else 0
	interacting = at_console
	view_lag = ceili(NetworkTime.remote_rtt * 0.5 * NetworkTime.tickrate) + NetworkRollback.display_offset
	if active and Input.is_action_just_pressed("player_flashlight"):
		flashlight_on = not flashlight_on


func _set_flag(flag : int, value : bool) -> void:
	buttons = (buttons | flag) if value else (buttons & ~flag)


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
