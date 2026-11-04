class_name Inventory
extends Node

##4-slot inventory, child of Player. Defines its own _rollback_tick so firing/slot-switching logic
##lives here instead of cluttering player.gd; RollbackSynchronizer finds and ticks any rollback-aware
##descendant of its root, not just the root itself.

const SLOT_COUNT : int = 4

signal active_slot_changed(slot : int)

@export var slots : Array[Item] = [null, null, null, null]
var active_slot : int = 0:
	set(value):
		active_slot = value
		active_slot_changed.emit(value)
var last_use_tick : int = -1000

@onready var player : Player = get_parent()
@onready var use_action : RewindableAction = $UseAction

var active_item : Item:
	get: return slots[active_slot] if active_slot < slots.size() else null


func _ready() -> void:
	for i in range(mini(player.starting_items.size(), SLOT_COUNT)):
		slots[i] = player.starting_items[i]


func _rollback_tick(_delta : float, tick : int, _is_fresh : bool) -> void:
	if player.input.slot_select >= 0:
		active_slot = player.input.slot_select
	elif player.input.slot_delta != 0:
		active_slot = wrapi(active_slot + player.input.slot_delta, 0, SLOT_COUNT)

	var item : Item = active_item
	var wants_to_use : bool = item != null and player.input.use_item and player.is_aiming() and tick - last_use_tick >= item.cooldown_ticks
	use_action.set_active(wants_to_use)
	if use_action.is_active():
		last_use_tick = tick
	if use_action.get_status() == RewindableAction.CONFIRMING and item:
		item.use(player, tick)
