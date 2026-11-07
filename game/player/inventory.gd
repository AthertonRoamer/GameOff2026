class_name Inventory
extends Node

##4-slot inventory, child of Player. Defines its own _rollback_tick so firing/slot-switching logic
##lives here instead of cluttering player.gd; RollbackSynchronizer finds and ticks any rollback-aware
##descendant of its root, not just the root itself.

const SLOT_COUNT : int = 4

signal active_slot_changed(slot : int)
signal drawn_changed(drawn : bool)

@export var slots : Array[Item] = [null, null, null, null]
var active_slot : int = 0:
	set(value):
		active_slot = value
		active_slot_changed.emit(value)
var drawn : bool = false: #the active item is out in the hands. Selecting a drawable item draws it, anything else holsters; H flips it
	set(value):
		if value != drawn:
			drawn = value
			drawn_changed.emit(value)
var redraw_after_run : bool = false #the item was put away by running, so it comes back out when the run ends
var last_use_tick : int = -1000

@onready var player : Player = get_parent()
@onready var use_action : RewindableAction = $UseAction

var active_item : Item:
	get: return slots[active_slot] if active_slot < slots.size() else null


func _ready() -> void:
	for i in range(mini(player.starting_items.size(), SLOT_COUNT)):
		slots[i] = player.starting_items[i]
	drawn = active_item != null and active_item.drawable #the first item starts out in the hands


func _rollback_tick(_delta : float, tick : int, _is_fresh : bool) -> void:
	var previous_slot : int = active_slot
	if player.input.slot_select >= 0:
		active_slot = player.input.slot_select
	elif player.input.slot_delta != 0:
		active_slot = wrapi(active_slot + player.input.slot_delta, 0, SLOT_COUNT)
	var item : Item = active_item
	var can_draw : bool = item != null and item.drawable
	if active_slot != previous_slot: #choosing an item brings it out (a gun) or puts the last one away
		drawn = can_draw
		redraw_after_run = false
	elif player.input.holster:
		drawn = can_draw and not drawn
		redraw_after_run = false
	elif drawn and not can_draw:
		drawn = false
	if player.is_running() and drawn: #running puts the item away, and it comes back out when the run stops
		drawn = false
		redraw_after_run = true
	elif redraw_after_run and not player.is_running():
		drawn = can_draw
		redraw_after_run = false

	var wants_to_use : bool = can_draw and drawn and player.input.use_item and tick - last_use_tick >= item.cooldown_ticks
	use_action.set_active(wants_to_use)
	if use_action.is_active():
		last_use_tick = tick
	if use_action.get_status() == RewindableAction.CONFIRMING and item:
		item.use(player, tick)
