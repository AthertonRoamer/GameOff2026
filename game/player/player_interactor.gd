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
##While a screen is open the player stands still (its input is off) and plays the interact animation, which the other peers see too
##(PlayerInput.interacting is part of the synced input). E closes the screen again; the screen closes itself on Esc.

signal prompt_changed(text : String) #"" when there is nothing in reach
signal inventory_full_changed(full : bool) #true while the only thing in reach is an item the player would take but has no room for

const GROUP : StringName = &"interactables"

@onready var player : Player = get_parent()

var target : Node #the closest interactable in reach, or null
var screen : Control #the screen the player is using, or null

var _prompt : String = ""
var _inventory_full : bool = false


func _ready() -> void:
	set_process((player.get_node("Input") as PlayerInput).is_multiplayer_authority()) #by node: this is readied before the player, whose @onready vars are still unset
	player.died.connect(close_screen)


func _process(_delta : float) -> void:
	_find_target()
	var text : String = target.get_prompt() if target != null else ""
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)
	if Input.is_action_just_pressed("player_interact"):
		if screen != null:
			screen.close()
		elif target != null:
			use(target)


##Uses an interactable now, as E would (the playground's check mode calls it directly).
func use(interactable : Node) -> void:
	var opened : Control = interactable.interact(player)
	if opened == null:
		return
	screen = opened
	player.set_active(false) #the player stands at the console while the screen is up
	player.input.interacting = true
	screen.closed.connect(_on_screen_closed, CONNECT_ONE_SHOT)


func close_screen() -> void:
	if screen != null:
		screen.close()


func _on_screen_closed() -> void:
	screen = null
	player.input.interacting = false
	if player.is_alive():
		player.set_active(true)


##Sets target to the closest usable interactable in reach, and reports when all that is in reach is an item there is no room for.
func _find_target() -> void:
	target = null
	var full_pickup_in_reach : bool = false
	if screen == null and player.input.active:
		var best_distance : float = INF
		for node : Node in get_tree().get_nodes_in_group(GROUP):
			if not node.is_in_reach(player.global_position) or (node.has_method("can_interact") and not node.can_interact(player)):
				continue
			if node is Pickup and player.inventory.first_free_slot() < 0:
				full_pickup_in_reach = true
				continue
			var distance : float = (node as Node2D).global_position.distance_to(player.global_position)
			if distance < best_distance:
				target = node
				best_distance = distance
	var inventory_full : bool = full_pickup_in_reach and target == null
	if inventory_full != _inventory_full:
		_inventory_full = inventory_full
		inventory_full_changed.emit(inventory_full)
