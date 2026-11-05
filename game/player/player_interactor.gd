class_name PlayerInteractor
extends Node

##Lets the local player use things in the world with the interact action (E). It only runs on the peer that controls this player.
##
##An interactable is any node in the GROUP group with:
##  get_prompt() -> String                 what the HUD shows while it is in reach
##  is_in_reach(world_position) -> bool    can a player standing here use it
##  interact(player) -> Control            does its thing; returns a screen to hold the player at (a Control with close() and a `closed`
##                                         signal), or null for something instant
##While a screen is open the player stands still (its input is off) and plays the interact animation, which the other peers see too
##(PlayerInput.interacting is part of the synced input). E closes the screen again; the screen closes itself on Esc.

signal prompt_changed(text : String) #"" when there is nothing in reach

const GROUP : StringName = &"interactables"

@onready var player : Player = get_parent()

var target : Node #the closest interactable in reach, or null
var screen : Control #the screen the player is using, or null

var _prompt : String = ""


func _ready() -> void:
	set_process((player.get_node("Input") as PlayerInput).is_multiplayer_authority()) #by node: this is readied before the player, whose @onready vars are still unset
	player.died.connect(func() -> void:
		if screen != null:
			screen.close())


func _process(_delta : float) -> void:
	target = null if screen != null or not player.input.active else _closest_in_reach()
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


func _on_screen_closed() -> void:
	screen = null
	player.input.interacting = false
	if player.is_alive():
		player.set_active(true)


func _closest_in_reach() -> Node:
	var best : Node = null
	var best_distance : float = INF
	for node : Node in get_tree().get_nodes_in_group(GROUP):
		if not node.is_in_reach(player.global_position):
			continue
		var distance : float = (node as Node2D).global_position.distance_to(player.global_position)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best
