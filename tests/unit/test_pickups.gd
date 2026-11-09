extends Node

# Offline test for artifact placement and picking items up, on the real level. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_pickups.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const PLAYER_SCENE : PackedScene = preload("res://game/player/player.tscn")
const PISTOL : Item = preload("res://game/items/guns/pistol.tres")
const FAR_AWAY : Vector2 = Vector2(-5000, -5000)

var failures : int = 0
var level : NightShiftLevel
var pickups : PickupControl
var player : Player


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func make_rng(seed_value : int) -> RandomNumberGenerator:
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


##Puts the player next to the pickup and asks for it, as pressing E does, then lets its tick arrive.
func take(pickup : Pickup) -> void:
	player.position = pickup.global_position + Vector2(20, 0)
	pickups.request_pickup(pickup)
	pickups._apply_due(NetworkTime.tick + pickups.apply_delay_ticks)


func _ready() -> void:
	var game : Game = GAME_SCENE.instantiate()
	add_child(game)
	level = game.level
	pickups = game.pickups
	var placer : ArtifactPlacer = game.artifact_placer

	#who may carry an artifact
	check(placer.can_carry(Team.ATTACKERS, true), "intruders can take artifacts")
	check(placer.can_carry(Team.ATTACKERS, false), "attacking guards can by default")
	check(not placer.can_carry(Team.DEFENDERS, false), "defenders can't by default")
	placer.attacking_guards_can_pick_up = false
	placer.defenders_can_pick_up = true
	check(placer.can_carry(Team.ATTACKERS, true), "intruders still can with the guard option off")
	check(not placer.can_carry(Team.ATTACKERS, false), "the attacking guard option turns them off")
	check(placer.can_carry(Team.DEFENDERS, false), "the defender option turns them on")
	placer.attacking_guards_can_pick_up = true
	placer.defenders_can_pick_up = false

	#placement
	var locations : Array[Node] = get_tree().get_nodes_in_group(ArtifactLocation.GROUP)
	check(locations.size() == 3, "the map has three artifact locations")
	var picks : PackedInt32Array = placer.roll(make_rng(7))
	var different : Dictionary = {}
	for pick in picks:
		different[pick] = true
	check(picks.size() == 3 and different.size() == 3, "each location gets a different artifact")
	check(picks == placer.roll(make_rng(7)), "the same roll gives the same placement")
	var layouts : Dictionary = {}
	for i in 30:
		layouts[placer.roll(make_rng(i))] = true
	check(layouts.size() > 1, "different matches place artifacts differently")
	placer.place(picks)
	var placed : Array = pickups.get_pickups()
	check(placed.size() == 3, "placing creates one pickup per location")
	for i in placed.size():
		check((placed[i] as Pickup).global_position.is_equal_approx((locations[i] as Node2D).global_position), "pickup %d is on its location" % i)
		check((placed[i] as Pickup).item == placer.artifacts[picks[i]], "pickup %d holds the rolled artifact" % i)
		check((placed[i] as Pickup).icon_sprite.texture == (placed[i] as Pickup).item.icon, "pickup %d shows the artifact's image" % i)

	#taking one, with a real player
	player = PLAYER_SCENE.instantiate()
	player.starting_items = [] as Array[Item] #the scene's default guns would fill the inventory
	player.position = FAR_AWAY
	player.team = Team.DEFENDERS
	level.actors.add_child(player)
	pickups.player_lookup = func(_peer_id : int) -> Player: return player
	await get_tree().physics_frame
	await get_tree().physics_frame

	var first : Pickup = placed[0]
	check(first.get_prompt() == "E   take the %s" % first.item.item_name, "the prompt names the item")
	take(first)
	check(pickups.get_pickups().has(first), "a defender can't take an artifact")
	check(not first.can_interact(player), "a defender isn't offered it")
	player.team = Team.ATTACKERS
	player.position = FAR_AWAY
	pickups.request_pickup(first)
	pickups._apply_due(NetworkTime.tick + pickups.apply_delay_ticks)
	check(pickups.get_pickups().has(first), "out of reach: not taken")
	take(first)
	check(not pickups.get_pickups().has(first), "an attacking guard takes it off the floor")
	check(player.inventory.slots.has(first.item), "and it is in the inventory")

	#the pickup is generic: any item, and anyone when it has no rule
	var pistol : Pickup = pickups.spawn(PISTOL, placed[1].global_position)
	player.team = Team.DEFENDERS
	take(pistol)
	check(player.inventory.slots.has(PISTOL), "any item can be picked up, by anyone when it has no rule")

	#only one player gets it, one at a time
	player.team = Team.ATTACKERS
	var second : Pickup = placed[1]
	player.position = second.global_position + Vector2(20, 0)
	pickups.request_pickup(second)
	var third : Pickup = placed[2]
	player.position = third.global_position + Vector2(20, 0)
	pickups.request_pickup(third)
	check(pickups._pending.size() == 1, "one pickup at a time per player, so two can't claim the same slot")
	pickups._apply_due(NetworkTime.tick + pickups.apply_delay_ticks)

	#a full inventory
	player.inventory.put_in_slot(player.inventory.first_free_slot(), PISTOL)
	check(player.inventory.first_free_slot() == -1, "the inventory is now full")
	take(third)
	check(pickups.get_pickups().has(third), "a full inventory can't take more")

	#what the player sees: the HUD, driven by the real interactor
	var hud : CanvasLayer = preload("res://game/player_hud/player_hud.tscn").instantiate()
	add_child(hud)
	hud.bind_player(player)
	await get_tree().process_frame
	check(hud._slot_icons[2].texture == player.inventory.slots[2].icon, "the HUD slots show picked up items")
	player.input.active = true
	player.position = third.global_position + Vector2(20, 0)
	player.interactor._process(0.0)
	check(hud.inventory_full_label.visible and hud.inventory_full_label.text == "Inventory full", "in reach with a full inventory: the label shows")
	check(not hud.interact_prompt.visible and player.interactor.target == null, "and there is no prompt to take it")
	player.team = Team.DEFENDERS
	player.interactor._process(0.0)
	check(not hud.inventory_full_label.visible and not hud.interact_prompt.visible, "someone not allowed to take it sees nothing, even when full")
	player.team = Team.ATTACKERS
	player.interactor._process(0.0)
	check(hud.inventory_full_label.visible, "the label comes back for someone allowed to take it")
	var panel : ControlPanel = level.consoles.panel_for("doors")
	var panel_home : Vector2 = panel.global_position
	panel.global_position = third.global_position + Vector2(0, 40)
	player.interactor._process(0.0)
	check(not hud.inventory_full_label.visible, "a console in reach too: no inventory full label")
	check(player.interactor.target == panel and hud.interact_prompt.visible, "and the console's prompt shows as normal")
	panel.global_position = panel_home
	player.position = panel_home + Vector2(0, 40)
	player.interactor._process(0.0)
	check(not hud.inventory_full_label.visible, "at a console with a full inventory and no item near: no label")
	player.position = FAR_AWAY
	player.interactor._process(0.0)
	check(not hud.inventory_full_label.visible, "out of reach: the label goes away")
	player.position = third.global_position + Vector2(20, 0)
	player.inventory.put_in_slot(3, null)
	player.interactor._process(0.0)
	check(not hud.inventory_full_label.visible and hud.interact_prompt.visible, "with a free slot the label goes and the prompt comes back")
	player.input.active = false

	#the target: one of the placed artifacts, shown only once a peer has been told
	var chooser : TargetArtifactChooser = game.target_chooser
	var targets : Dictionary = {}
	for i in 40:
		targets[chooser.choose(picks, make_rng(i))] = true
	check(targets.size() == picks.size() and targets.keys().all(func(t : int) -> bool: return picks.has(t)), "the target is always a placed artifact, and any of them can be")
	check(chooser.choose(PackedInt32Array(), make_rng(1)) == -1, "no target when nothing was placed")
	check(chooser.target == null, "nobody knows the target until they are told")
	chooser.set_target(picks[1])
	check(chooser.target == placer.artifacts[picks[1]], "being told sets the target")
	chooser.set_target(-1)
	check(chooser.target == null, "a peer sent no target has none")
	check(not hud.target_label.visible, "the target label starts hidden")
	check(hud.target_label.anchor_left == 0.5 and hud.target_label.anchor_right == 0.5 and hud.target_label.anchor_top == 0.0, "the target label is anchored to the top middle")
	hud.show_target(null)
	check(not hud.target_label.visible, "no target: the label stays hidden")
	hud.show_target(placer.artifacts[picks[0]])
	check(hud.target_label.visible and hud.target_label.text == "Target: %s" % placer.artifacts[picks[0]].item_name, "the label names the target")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
