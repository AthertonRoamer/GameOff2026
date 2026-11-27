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
const RELOAD : int = 1 << 16 #the reload key (R) went down
const SNEAK : int = 1 << 17 #ctrl held: a slow, silent walk
const SLOT_SHIFT : int = 5 #3 bits: the slot chosen this tick plus one (so 0 is none)
const DELTA_SHIFT : int = 8 #2 bits: the wheel's turn this tick plus one (so 1 is none)
const LAG_SHIFT : int = 10 #6 bits: how many ticks behind the lobby this player sees the others (0 to 63), for lag compensated shots

var movement : Vector2 = Vector2.ZERO
var aim : Vector2 = Vector2.ZERO
var buttons : int = FLASHLIGHT | (1 << DELTA_SHIFT) #the flashlight starts on, no slot chosen, no wheel turn
var active : bool = false #not sent: only this peer's own player is gathered
var typing : bool = false #not sent: this peer is typing in the chat (ChatWindow). Nothing is gathered while it is, without touching `active`, which the phases and consoles own
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
var sneak : bool:
	get: return buttons & SNEAK != 0
	set(value): _set_flag(SNEAK, value)
var reload : bool:
	get: return buttons & RELOAD != 0
	set(value): _set_flag(RELOAD, value)
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


## The key presses (not the held keys) since the last tick. A press is a moment, and the game draws more frames than it runs ticks, so asking Input "was it just pressed"
## when a tick gathers misses the presses that fall between ticks (R, F and the slot keys sometimes did nothing). They are noted as they happen and handed over by the tick.
var _pressed : Dictionary = {} #action -> how many times it was pressed
var _slot_pressed : int = -1
var _scroll : int = 0


func _input(event : InputEvent) -> void:
	if not active or typing or not event.is_pressed() or event.is_echo():
		return
	for action : StringName in [&"player_holster", &"player_reload", &"player_flashlight"]:
		if event.is_action(action):
			_pressed[action] = _pressed.get(action, 0) + 1
	for i in 4:
		if event.is_action("inventory_slot_%d" % (i + 1)):
			_slot_pressed = i
	if event.is_action("inventory_scroll_up"):
		_scroll = -1
	elif event.is_action("inventory_scroll_down"):
		_scroll = 1


func _took_press(action : StringName) -> int:
	var count : int = _pressed.get(action, 0)
	_pressed[action] = 0
	return count


func _gather() -> void:
	var on : bool = active and not typing
	movement = Input.get_vector("player_left", "player_right", "player_up", "player_down") if on else Vector2.ZERO
	aim = (get_parent() as Node2D).get_global_mouse_position() if on else aim
	use_item = on and Input.is_action_pressed("player_use_active_item")
	run = on and Input.is_action_pressed("player_run")
	sneak = on and Input.is_action_pressed("player_sneak")
	var holsters : int = _took_press(&"player_holster")
	var reloads : int = _took_press(&"player_reload")
	var flashlights : int = _took_press(&"player_flashlight")
	holster = on and holsters > 0
	reload = on and reloads > 0
	slot_select = _slot_pressed if on else -1
	slot_delta = _scroll if on else 0
	_slot_pressed = -1
	_scroll = 0
	interacting = at_console
	view_lag = ceili(NetworkTime.remote_rtt * 0.5 * NetworkTime.tickrate) + NetworkRollback.display_offset
	if on and flashlights % 2 == 1:
		flashlight_on = not flashlight_on


func _set_flag(flag : int, value : bool) -> void:
	buttons = (buttons | flag) if value else (buttons & ~flag)
