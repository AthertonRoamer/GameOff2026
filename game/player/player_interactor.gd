class_name PlayerInteractor
extends Node

##Lets the local player use things in the world with the interact action (E). It only runs on the peer that controls this player.
##
##An interactable is any node in the GROUP group with:
##  get_prompt() -> String                 what the HUD shows while it is in reach
##  is_in_reach(world_position) -> bool    can a player standing here use it
##  interact(player) -> Control            does its thing; returns a screen to hold the player at (a Control with close() and a `closed`
##                                         signal), or null for something instant
##  can_interact(player) -> bool           optional: false hides it from this player
##  hold_seconds(player) -> float          optional: E has to be held this long (a progress bar on the HUD) before interact() is called. The player
##                                         stands still meanwhile. Letting go, walking out of reach or dying cancels it. The interactable may also have
##                                         hold_started(player) and hold_cancelled(player), told when a hold begins and when it ends without finishing
##While a screen is open the player stands still (its input is off) and plays the interact animation, which the other peers see too
##(PlayerInput.interacting is part of the synced input). E closes the screen again; the screen closes itself on Esc.

signal prompt_changed(text : String) #"" when there is nothing in reach
signal inventory_full_changed(full : bool) #true while the only thing in reach is an item the player would take but has no room for
signal hold_progress_changed(progress : float) #0 to 1 while E is held on something that needs holding, -1 when the hold ends (finished or not)

const GROUP : StringName = &"interactables"

@onready var player : Player = get_parent()

var target : Node #the closest interactable in reach, or null
var screen : Control #the screen the player is using, or null

var holding : Node #what E is being held on, or null
var hold_action : StringName = &"player_interact" #the key being held: E, or Q for a medic making medicine
var hold_time : float = 0.0
var hold_total : float = 0.0

var _prompt : String = ""
var _inventory_full : bool = false
var item_use : ItemUse #the item in the hand, as something to hold E on (medicine)
var medicine_maker : MedicineMaker #a medic making their next dose of medicine (Q held)


func _ready() -> void:
	item_use = ItemUse.new()
	item_use.name = "ItemUse"
	item_use.player = player
	add_child(item_use)
	medicine_maker = MedicineMaker.new()
	medicine_maker.name = "MedicineMaker"
	medicine_maker.player = player
	add_child(medicine_maker)
	set_process((player.get_node("Input") as PlayerInput).is_multiplayer_authority()) #by node: this is readied before the player, whose @onready vars are still unset
	player.died.connect(close_screen)
	player.died.connect(cancel_hold)


func _process(delta : float) -> void:
	if holding != null:
		_continue_hold(delta)
		return
	_find_target()
	var text : String = target.get_prompt() if target != null else ""
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)
	if Input.is_action_just_pressed("player_make_medicine") and not player.input.typing and screen == null and player.input.active and medicine_maker.can_interact(player):
		start_hold(medicine_maker, &"player_make_medicine") #(a medic whose next dose is ready: Q held makes it)
		return
	if Input.is_action_just_pressed("player_interact") and not player.input.typing: #(an e typed in the chat is not a press)
		if screen != null:
			screen.close()
		elif target != null and target.has_method("hold_seconds"):
			start_hold(target)
		elif target != null:
			use(target)


##The item keys, for an item in the hand: G drops it where the player stands, and a click with a portable generator puts it down (Item.ClickUse.PLACE;
##medicine is used by holding E on it instead, see ItemUse). Both go through the lobby (PickupControl). Unhandled input only, so a click on a screen or the chat is not a use.
func _unhandled_input(event : InputEvent) -> void:
	if not is_processing() or holding != null or screen != null or player.input.typing or not player.input.active or not player.is_alive():
		return
	var dropping : bool = event.is_action_pressed("player_drop") and not event.is_echo()
	var clicking : bool = event.is_action_pressed("player_use_active_item") and not event.is_echo()
	if not dropping and not clicking:
		return
	var item : Item = player.inventory.active_item
	var control : Node = get_tree().get_first_node_in_group(PickupControl.GROUP)
	if item == null or control == null:
		return
	if dropping:
		control.request_drop(player.inventory.active_slot)
	elif not item.drawable and item.click_use in [Item.ClickUse.PLACE, Item.ClickUse.THROW]: #(medicine is used by holding E instead: see ItemUse)
		control.request_use(player.inventory.active_slot)


##Starts holding E on an interactable that needs it (as pressing E does). The playground's check mode calls it directly.
func start_hold(interactable : Node, action : StringName = &"player_interact") -> void:
	holding = interactable
	hold_action = action
	hold_time = 0.0
	hold_total = maxf(0.01, interactable.hold_seconds(player))
	player.set_active(false) #the player stands still while working it
	player.input.at_console = true
	player.input.interacting = true
	if interactable.has_method("hold_started"):
		interactable.hold_started(player)
	hold_progress_changed.emit(0.0)


##Lets go before the hold is done.
func cancel_hold() -> void:
	if holding == null:
		return
	var was : Node = holding
	_end_hold()
	if is_instance_valid(was) and was.has_method("hold_cancelled"):
		was.hold_cancelled(player)


func _continue_hold(delta : float) -> void:
	var still_ok : bool = is_instance_valid(holding) and player.is_alive() and Input.is_action_pressed(hold_action) \
		and holding.is_in_reach(player.global_position) and (not holding.has_method("can_interact") or holding.can_interact(player))
	if not still_ok:
		cancel_hold()
		return
	hold_time += delta
	if hold_time < hold_total:
		hold_progress_changed.emit(hold_time / hold_total)
		return
	var done : Node = holding
	_end_hold()
	done.interact(player)


func _end_hold() -> void:
	holding = null
	hold_time = 0.0
	player.input.at_console = false
	player.input.interacting = false
	if player.is_alive():
		player.set_active(true)
	hold_progress_changed.emit(-1.0)


##Uses an interactable now, as E would (the playground's check mode calls it directly).
func use(interactable : Node) -> void:
	var opened : Control = interactable.interact(player)
	if opened == null:
		return
	screen = opened
	player.set_active(false) #the player stands at the console while the screen is up
	player.input.at_console = true
	player.input.interacting = true #(at once; from now on gathered with the keys)
	screen.closed.connect(_on_screen_closed, CONNECT_ONE_SHOT)


func close_screen() -> void:
	if screen != null:
		screen.close()


func _on_screen_closed() -> void:
	screen = null
	player.input.at_console = false
	player.input.interacting = false
	if player.is_alive():
		player.set_active(true)


##Sets target to the closest usable interactable in reach, and reports when all that is in reach is an item there is no room for.
func _find_target() -> void:
	target = null
	var full_pickup_in_reach : bool = false
	if screen == null and player.input.active:
		if item_use.can_interact(player): #the item chosen in the hand comes first: choosing medicine is choosing to use it
			target = item_use
	if target == null and screen == null and player.input.active:
		var best_distance : float = INF
		for node : Node in get_tree().get_nodes_in_group(GROUP):
			if not node.is_in_reach(player.global_position) or (node.has_method("can_interact") and not node.can_interact(player)):
				continue
			if node is Pickup and (node as Pickup).item.slot_for(player.inventory) < 0:
				full_pickup_in_reach = true
				continue
			if not node is Node2D:
				continue
			var distance : float = (node as Node2D).global_position.distance_to(player.global_position)
			if distance < best_distance:
				target = node
				best_distance = distance
	var inventory_full : bool = full_pickup_in_reach and target == null
	if inventory_full != _inventory_full:
		_inventory_full = inventory_full
		inventory_full_changed.emit(inventory_full)
