class_name Inventory
extends Node

##4-slot inventory, child of Player. Defines its own _rollback_tick so firing/slot-switching logic
##lives here instead of cluttering player.gd; RollbackSynchronizer finds and ticks any rollback-aware
##descendant of its root, not just the root itself.

const SLOT_COUNT : int = 4

signal active_slot_changed(slot : int)
signal drawn_changed(drawn : bool)
signal items_changed

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

##Ammunition. The magazine, the reload and the rounds fired from the supply are rollback state (every peer simulates them the same); the supply itself is worked out from
##them: what the player started with, plus the boxes picked up by that tick (the log, which a rollback never touches), less the rounds already loaded.
var spare_rounds_at_start : int = 24 #the supply a player starts with (no slot: it is in their pockets): the player's starting_spare_rounds
var magazine : int = 0 #rounds in the gun
var reload_end_tick : int = -1 #the tick a reload in progress finishes on, -1 when not reloading
var loaded_total : int = 0 #rounds ever taken from the supply into the magazine
var _reset_tick : int = -1
var _supply_log : Array[Vector2i] = [] #(tick the box was picked up on, rounds)

@onready var player : Player = get_parent()
@onready var use_action : RewindableAction = $UseAction

var active_item : Item:
	get: return slots[active_slot] if active_slot < slots.size() else null


func _ready() -> void:
	set_items(player.starting_items)


##Fills the slots with these items (the rest empty) and takes the first one out, as at the start.
##reset_tick: when the role changes during play, the ammunition state (rollback state: a rollback would put the old one back) is set again on this same tick on every peer,
##and the rollback replays that tick every time it simulates it. -1 for the start of the game.
func set_items(items : Array[Item], reset_tick : int = -1) -> void:
	_reset_tick = reset_tick
	for i in SLOT_COUNT:
		slots[i] = items[i] if i < items.size() else null
	active_slot = 0
	drawn = active_item != null and active_item.drawable #the first item starts out in the hands
	var gun : Gun = _first_gun()
	magazine = gun.magazine_size if gun != null else 0
	spare_rounds_at_start = player.starting_spare_rounds
	reload_end_tick = -1
	loaded_total = 0
	_supply_log.clear()
	items_changed.emit()


func _first_gun() -> Gun:
	for item : Item in slots:
		if item is Gun:
			return item
	return null


## The rounds in the supply at this tick (not counting the magazine).
func reserve_at(tick : int) -> int:
	var total : int = spare_rounds_at_start - loaded_total
	for entry : Vector2i in _supply_log:
		if entry.x <= tick:
			total += entry.y
	return maxi(total, 0)


func reserve_now() -> int:
	return reserve_at(NetworkTime.tick)


func is_reloading() -> bool:
	return reload_end_tick >= 0


## A box of ammo picked up on this tick (the same tick on every peer, see PickupControl).
func add_supply(tick : int, rounds : int) -> void:
	_supply_log.append(Vector2i(tick, rounds))


## The slot holding the ammo, or -1.
func ammo_slot() -> int:
	for i in slots.size():
		if slots[i] is AmmoItem:
			return i
	return -1


func _process(_delta : float) -> void:
	var pouch : int = ammo_slot() #an empty supply leaves nothing to carry: the box's slot is free again
	if pouch >= 0 and reserve_now() <= 0:
		slots[pouch] = null
		items_changed.emit()


##The first empty slot, or -1 when the inventory is full.
func first_free_slot() -> int:
	return slots.find(null)


func put_in_slot(slot : int, item : Item) -> void:
	slots[slot] = item
	items_changed.emit()


func _rollback_tick(_delta : float, tick : int, _is_fresh : bool) -> void:
	if tick == _reset_tick:
		var first_gun : Gun = _first_gun()
		magazine = first_gun.magazine_size if first_gun != null else 0
		loaded_total = 0
		reload_end_tick = -1
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
		reload_end_tick = -1
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

	var gun : Gun = item as Gun
	_update_reload(gun, tick)
	var loaded : bool = gun == null or (magazine > 0 and not is_reloading()) #a gun with an empty magazine, or being reloaded, does not fire
	var wants_to_use : bool = can_draw and drawn and loaded and player.input.use_item and tick - last_use_tick >= item.cooldown_ticks
	use_action.set_active(wants_to_use)
	if wants_to_use and gun != null:
		magazine -= 1 #(worked out here, not when the shot is confirmed: a resimulated tick has to fire and count the same way)
	if use_action.is_active():
		last_use_tick = tick
	if use_action.get_status() == RewindableAction.CONFIRMING and item:
		item.use(player, tick)


## A reload starts when R is pressed, or the trigger is pulled on an empty magazine, if the gun is out and there is supply to load; it ends reload_ticks later by filling the
## magazine from the supply. Putting the gun away (or choosing another item) stops it.
func _update_reload(gun : Gun, tick : int) -> void:
	if is_reloading():
		if gun == null or not drawn:
			reload_end_tick = -1
		elif tick >= reload_end_tick:
			var taken : int = mini(gun.magazine_size - magazine, reserve_at(tick))
			magazine += taken
			loaded_total += taken
			reload_end_tick = -1
		return
	if gun == null or not drawn or magazine >= gun.magazine_size or reserve_at(tick) <= 0:
		return
	if player.input.reload or (magazine <= 0 and player.input.use_item):
		reload_end_tick = tick + gun.reload_ticks()
