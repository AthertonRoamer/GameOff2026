extends Node

# Offline test for items found lying in the item rooms (FacilityItemRooms, FacilityRoom.spawns_items / item_chance, FacilityMap.item_spots, ItemSpawner),
# on the real level. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_item_spawns.tscn

const GAME_SCENE : PackedScene = preload("res://game/game.tscn")
const PLAYER_SCENE : PackedScene = preload("res://game/player/player.tscn")
const FAR_AWAY : Vector2 = Vector2(-5000, -5000)

var failures : int = 0


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


func _ready() -> void:
	var game : Game = GAME_SCENE.instantiate()
	add_child(game)
	var map : FacilityMap = game.level.facility
	var spawner : ItemSpawner = game.item_spawner
	var pickups : PickupControl = game.pickups

	#the map's item rooms node
	check(map.item_rooms_node != null, "the map has an ItemRooms node")
	check(not spawner.items().is_empty(), "with items to spawn")
	check(not spawner.items().any(func(item : Item) -> bool: return item is Artifact), "and no relic among them")
	var fresh_room : FacilityRoom = FacilityRoom.new()
	check(fresh_room.item_chance == 30 and not fresh_room.spawns_items, "a room starts with a 30% chance, and is not an item room until it is made one")
	fresh_room.item_chance = 150
	check(fresh_room.item_chance == 100, "the chance is a percent: it stops at 100")
	fresh_room.free()

	#every room can be one: make them all item rooms
	var room_nodes : Array[FacilityRoom] = []
	for room : FacilityRoom in map.room_nodes():
		if not room.is_exit() and map.has_room(room.room_id()):
			room_nodes.append(room)
	for room : FacilityRoom in room_nodes:
		room.spawns_items = false
	map.build()
	check(map.item_rooms().is_empty(), "no item rooms: none")
	check(spawner.roll(make_rng(1))["items"].is_empty(), "and nothing is rolled")

	for room : FacilityRoom in room_nodes:
		room.spawns_items = true
		room.item_chance = 100
	map.build()
	await get_tree().physics_frame
	check(map.item_rooms().size() == room_nodes.size(), "every room ticked is an item room (%d)" % room_nodes.size())

	#where an item can lie
	var with_spots : int = 0
	var bad : Array[String] = []
	var furniture : Array[Furniture] = []
	for node : Node in map.props_node.find_children("*", "Furniture", true, false):
		furniture.append(node)
	for room_id : String in map.item_rooms():
		var spots : PackedVector2Array = map.item_spots(room_id)
		if not spots.is_empty():
			with_spots += 1
		for spot : Vector2 in spots:
			if map.room_at(spot) != room_id:
				bad.append("%s: %s is not in the room" % [room_id, spot])
				continue
			var cell : Vector2i = map.world_to_cell(spot)
			var near_wall : bool = false
			for side : Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if map.wall_cells.has(cell + side * (FacilityMap.ITEM_WALL_GAP_CELLS + 1)):
					near_wall = true
			if not near_wall:
				bad.append("%s: %s is not by a wall" % [room_id, spot])
			for door : FacilityDoor in map.doors_of_room(room_id):
				var middle : Vector2 = map.to_local(door.global_position)
				var door_rect : Rect2i = door.cell_rect(map)
				var centre : Vector2 = Vector2(door_rect.get_center()) * FacilityMap.TILE
				var across : float = absf(spot.y - centre.y) if door.horizontal else absf(spot.x - centre.x)
				var along : float = absf(spot.x - centre.x) if door.horizontal else absf(spot.y - centre.y)
				if across < 3.0 * FacilityMap.TILE and along < door_rect.size[0 if door.horizontal else 1] * FacilityMap.TILE / 2.0 + FacilityMap.TILE:
					bad.append("%s: %s is in front of door %s (%s)" % [room_id, spot, door.name, middle])
			for piece : Furniture in furniture:
				var polygon : PackedVector2Array = map.get_global_transform().affine_inverse() * piece.footprint_polygon()
				if Geometry2D.is_point_in_polygon(spot, polygon):
					bad.append("%s: %s is on %s" % [room_id, spot, piece.name])
	check(with_spots >= room_nodes.size() / 2, "most rooms have somewhere for an item (%d of %d)" % [with_spots, room_nodes.size()])
	check(bad.is_empty(), "every spot is in its room, by a wall, off the furniture and out of the doorways%s" % ("" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 6))))
	check(map.item_spots(map.item_rooms()[0]) == map.item_spots(map.item_rooms()[0]), "the spots are the same every time they are asked for")

	#the roll
	var all : Dictionary = spawner.roll(make_rng(3))
	check(all["items"].size() == with_spots and all["at"].size() == with_spots, "at 100%% every room with a spot gets one item (%d)" % all["items"].size())
	check(all == spawner.roll(make_rng(3)), "the same roll gives the same items in the same places")
	var kinds : Dictionary = {}
	for pick : int in all["items"]:
		kinds[pick] = true
	check(kinds.size() > 1, "the items are picked at random from the list")
	for room : FacilityRoom in room_nodes:
		room.item_chance = 0
	map.build()
	check(spawner.roll(make_rng(3))["items"].is_empty(), "at 0% nothing turns up")
	for room : FacilityRoom in room_nodes:
		room.item_chance = 30
	map.build()
	var total : int = 0
	for i in 40:
		total += (spawner.roll(make_rng(100 + i))["items"] as PackedInt32Array).size()
	var share : float = float(total) / (40.0 * with_spots)
	check(share > 0.2 and share < 0.4, "at the default 30%% about three rooms in ten have an item (%.2f)" % share)

	#placing: ordinary pickups, on the floor where the roll said
	var before : int = pickups.get_pickups().size()
	spawner.place(all["items"], all["at"])
	var placed : Array = pickups.get_pickups().slice(before)
	check(placed.size() == all["items"].size(), "placing puts one pickup per rolled item")
	var all_right : bool = true
	for i in placed.size():
		var pickup : Pickup = placed[i]
		all_right = all_right and pickup.global_position.is_equal_approx(all["at"][i]) and pickup.item == spawner.all_items()[all["items"][i]]
	check(all_right, "each pickup is the rolled item, where it was rolled")
	check(spawner.placed_rooms.size() == placed.size(), "and the spawner knows which rooms got one")

	#anyone can take one and drop it again
	var player : Player = PLAYER_SCENE.instantiate()
	player.starting_items = [] as Array[Item]
	player.position = FAR_AWAY
	player.team = Team.DEFENDERS
	game.level.actors.add_child(player)
	pickups.player_lookup = func(_peer_id : int) -> Player: return player
	await get_tree().physics_frame
	await get_tree().physics_frame
	var first : Pickup = placed[0]
	var item : Item = first.item
	check(first.can_interact(player), "a found item can be taken by anyone")
	player.position = first.global_position + Vector2(20, 0)
	pickups.request_pickup(first)
	pickups._apply_due(NetworkTime.tick + pickups.apply_delay_ticks)
	check(not pickups.get_pickups().has(first), "taking it takes it off the floor")
	var slot : int = player.inventory.slots.find(item)
	check(slot >= 0, "and puts it in the inventory")
	var count : int = pickups.get_pickups().size()
	pickups.request_drop(slot)
	pickups._apply_due(NetworkTime.tick + pickups.apply_delay_ticks)
	check(pickups.get_pickups().size() == count + 1 and player.inventory.slots[slot] == null, "and it can be dropped again")

	#seen only where the local player can see: the same sight rule as every pickup (PlayerSight: the view cone, and a room on a live camera)
	var sight_line : Array = [0.0]
	pickups.sight = func(point : Vector2) -> float: return 1.0 if point.x < sight_line[0] else 0.0
	await get_tree().create_timer(0.4).timeout
	var hidden : bool = true
	for entry in pickups.get_pickups():
		if is_instance_valid(entry) and (entry as Pickup).global_position.x >= 0.0 and (entry as Pickup).modulate.a > 0.0:
			hidden = false
	check(hidden, "a found item out of view is not drawn")
	pickups.sight = Callable()

	#no map shows items
	var layers : Array[String] = []
	for path : String in DirAccess.get_files_at("res://game/ui/map_view/layers"):
		if path.ends_with(".gd"):
			var source : String = FileAccess.get_file_as_string("res://game/ui/map_view/layers/" + path)
			if source.contains("get_pickups") or source.contains("ItemSpawner"):
				layers.append(path)
	check(layers.is_empty(), "no map layer draws items lying about %s" % [layers])

	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)
