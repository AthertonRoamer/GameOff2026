extends Node

# Offline test for ammunition, reloading, stamina, and the maps on the HUD, on the real game scene. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_ammo.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")

var failures : int = 0
var player : Player
var inventory : Inventory
var tick : int = 1000


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


## One rollback tick of the inventory, with the buttons as the player holds them.
func step(count : int = 1) -> void:
	for i in count:
		inventory._rollback_tick(0.016, tick, true)
		tick += 1
		player.input.reload = false


func _ready() -> void:
	var game : Game = GAME_SCENE.instantiate()
	add_child(game)
	var level : NightShiftLevel = game.level
	player = game.spawner.player_scene.instantiate()
	level.actors.add_child(player)
	inventory = player.inventory
	var pistol : Gun = inventory.active_item as Gun
	check(pistol != null and inventory.slots[1] == null, "a player starts with the pistol only")
	check(inventory.magazine == pistol.magazine_size and inventory.reserve_at(tick) == inventory.spare_rounds_at_start, "full magazine and a starting supply")

	#firing uses a round each, no faster than the gun's cooldown
	player.input.use_item = true
	step()
	check(inventory.magazine == pistol.magazine_size - 1, "a shot uses a round")
	step(pistol.cooldown_ticks - 1)
	check(inventory.magazine == pistol.magazine_size - 1, "no round is used inside the cooldown")
	step()
	check(inventory.magazine == pistol.magazine_size - 2, "the next shot comes after it")
	player.input.use_item = false

	#an empty magazine: the trigger starts a reload, nothing fires while it runs, and it ends full
	inventory.magazine = 0
	inventory.last_use_tick = -1000
	player.input.use_item = true
	step()
	check(inventory.is_reloading() and inventory.magazine == 0, "pulling the trigger on an empty magazine starts a reload")
	step(pistol.reload_ticks() - 2)
	check(inventory.is_reloading() and inventory.magazine == 0, "nothing fires and nothing is loaded while it runs (the trigger is still held)")
	player.input.use_item = false
	step(2)
	check(not inventory.is_reloading() and inventory.magazine == pistol.magazine_size, "the reload fills the magazine")
	check(inventory.reserve_at(tick) == inventory.spare_rounds_at_start - pistol.magazine_size, "from the supply")
	player.input.use_item = false

	#R reloads what is missing, and only what the supply has
	inventory.magazine = pistol.magazine_size - 5
	var supply : int = inventory.reserve_at(tick)
	player.input.reload = true
	step()
	check(inventory.is_reloading(), "R starts a reload of a part-empty magazine")
	step(pistol.reload_ticks())
	check(inventory.magazine == pistol.magazine_size and inventory.reserve_at(tick) == supply - 5, "it takes only the five that were missing")
	player.input.reload = true
	step()
	check(not inventory.is_reloading(), "a full magazine does not reload")

	#a reload is stopped by putting the gun away
	inventory.magazine = 3
	player.input.reload = true
	step()
	player.input.holster = true
	step()
	player.input.holster = false
	check(not inventory.is_reloading() and inventory.magazine == 3, "holstering the gun stops the reload")
	player.input.holster = true
	step()
	player.input.holster = false

	#boxes of ammo: one slot, however many are picked up, and the rounds go to the supply
	var box : AmmoItem = load("res://game/items/ammo/ammo_box.tres")
	var before : int = inventory.reserve_at(tick)
	var slot : int = box.slot_for(inventory)
	check(slot == 1, "a first box would take the first free slot")
	box.put_into(inventory, slot, tick)
	check(inventory.slots[1] == box and inventory.reserve_at(tick) == before + box.rounds, "it takes a slot and adds its rounds")
	check(box.slot_for(inventory) == 1, "a second box joins the first one's slot")
	box.put_into(inventory, 1, tick)
	check(inventory.slots[1] == box and inventory.slots[2] == null and inventory.reserve_at(tick) == before + box.rounds * 2, "so it takes no new slot")
	check(inventory.reserve_at(tick - 10) == before, "the rounds are not there before the tick they were picked up on (a rollback)")
	for i in 3:
		inventory.put_in_slot(2 + i if i < 2 else 3, load("res://game/items/guns/pistol.tres"))
	check(inventory.first_free_slot() == -1 and box.slot_for(inventory) == 1, "with the inventory full, ammo can still be added to the slot it has")

	#an empty supply frees the slot
	inventory.loaded_total += inventory.reserve_at(tick)
	inventory._process(0.0)
	check(inventory.slots[1] == null, "a used up supply gives its slot back")

	#stamina
	player.input.run = true
	player.input.movement = Vector2.RIGHT
	check(player.is_running(), "shift and moving is running")
	var runs : int = 0
	while not player.winded and runs < 1000:
		player._update_stamina(0.1)
		runs += 1
	check(player.winded and player.stamina <= 0.0 and not player.is_running(), "running uses stamina up (in %d s), and then the player is winded" % (runs / 10))
	player._update_stamina(1.0)
	check(player.winded, "a little stamina is not enough to run again")
	player.input.run = false
	for i in 100:
		player._update_stamina(0.1)
	check(player.stamina >= player.stamina_recover_at and not player.winded, "it comes back while not running")
	player.input.run = true
	check(player.is_running(), "and the player runs again")

	#the HUD: the maps and the ammo
	var hud : CanvasLayer = load("res://game/player_hud/player_hud.tscn").instantiate()
	add_child(hud)
	hud.bind_map(level.facility)
	hud.bind_player(player)
	await get_tree().process_frame
	await get_tree().process_frame
	check(hud.minimap.facility == level.facility and hud.minimap.size.x > 0.0, "the minimap shows the facility")
	check(hud.minimap.mouse_filter == Control.MOUSE_FILTER_IGNORE, "and takes no clicks")
	check(not hud.map_screen.visible, "the full map starts closed")
	hud.map_screen.toggle()
	check(hud.map_screen.visible and hud.map_screen.map.facility == level.facility, "the map key opens the full map")
	hud.map_screen.toggle()
	check(not hud.map_screen.visible, "and closes it")
	inventory.set_items([pistol])
	await get_tree().process_frame
	check(hud.ammo_label.visible and hud.ammo_label.text == "%d / %d" % [pistol.magazine_size, inventory.spare_rounds_at_start], "the HUD shows the magazine and the supply")

	#the reload animation: every role's skin has one, played over the time the reload takes
	for skin_name : String in ["guard", "medic", "gunner", "electrician", "shade", "ventrat", "intruder"]:
		var skin : NightShiftCharacter = load("res://game/player/skin/player_skin.tscn").instantiate()
		add_child(skin)
		skin.use_skin(skin_name)
		skin.update_visual(Vector2.ZERO, Vector2.UP, true, false, false, 0, 0.0)
		check(skin.torso.animation == &"torso_idle_aim", "%s: not reloading, the gun is up" % skin_name)
		skin.update_visual(Vector2.ZERO, Vector2.UP, true, false, false, 0, pistol.reload_seconds)
		var frames : SpriteFrames = skin.torso.sprite_frames
		var native : float = frames.get_frame_count(&"torso_reload") / frames.get_animation_speed(&"torso_reload")
		check(skin.torso.animation == &"torso_reload" and is_equal_approx(skin.torso.speed_scale * pistol.reload_seconds, native), "%s: reloading plays its reload sheet over the reload's time" % skin_name)
		skin.torso.frame = 5
		skin.update_visual(Vector2.ZERO, Vector2.UP, true, false, false, 0, pistol.reload_seconds)
		check(skin.torso.animation == &"torso_reload" and skin.torso.frame == 5, "%s: and does not start it again" % skin_name)
		skin.update_visual(Vector2.ZERO, Vector2.UP, true, false, false, 0, 0.0)
		check(skin.torso.animation == &"torso_idle_aim", "%s: the gun stays up when it is over" % skin_name)
		skin.queue_free()
	#ammo lying in the map
	var locations : Array[Node] = get_tree().get_nodes_in_group(AmmoLocation.GROUP)
	check(locations.size() >= 4, "the map has places for ammo (%d)" % locations.size())
	var floor_before : int = game.pickups.get_pickups().size()
	game.ammo_placer.place()
	check(game.pickups.get_pickups().size() == floor_before + locations.size(), "a box lies on each of them")

	#a deathmatch brings new boxes over time, to locations that are empty
	check(game.ammo_placer.empty_locations().is_empty(), "no location is empty while every box lies there")
	for pickup : Pickup in game.pickups.get_pickups():
		if pickup.item is AmmoItem:
			pickup.queue_free()
			break
	await get_tree().process_frame
	check(game.ammo_placer.empty_locations().size() == 1, "a taken box leaves its location empty")
	game.ammo_placer.trickle_seconds = 0.0
	game.ammo_placer.start_trickle()
	await get_tree().process_frame
	await get_tree().process_frame
	check(game.ammo_placer.empty_locations().is_empty(), "and the trickle puts a new one there")

	#a role change during play: the ammunition starts again on one tick, and a rollback that puts the old state back does not undo it
	player.input.use_item = false
	inventory.set_items([pistol], tick + 2)
	inventory.loaded_total = 99
	inventory.magazine = 0
	step(2)
	check(inventory.loaded_total == 99, "before the tick, the old state is as a rollback left it")
	step()
	check(inventory.loaded_total == 0 and inventory.magazine == pistol.magazine_size and inventory.reserve_at(tick) == inventory.spare_rounds_at_start, "on it, the new role's ammunition begins")

	#the debug role picker lists every role
	var picker : DebugRolePicker = game.get_node("DebugRolePicker")
	picker._set_open(true)
	check(picker.visible and picker._list.get_child_count() == game.role_assigner.all_roles().size() and picker._list.get_child_count() >= 7, "the debug role picker has a button for each role")

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(failures)
