class_name ItemSpawner
extends Node

##Items lying about the facility: in each room the map marks as an item room (FacilityRoom.spawns_items), the lobby rolls the room's chance
##(FacilityRoom.item_chance, 30% by default) once, when the match loads, and on a hit puts one item at a random spot along the room's walls that is clear of
##furniture and not in front of a door (FacilityMap.item_spots). The item is picked at random from the room's own list (FacilityRoom.item_pool) or, when it has
##none, from the map's (the ItemRooms node's items). Nothing turns up later.
##The lobby rolls them (roll) and sends the result with the roles, so every peer puts the same items in the same places, in the same order as the other
##placers (the pickups are numbered as they are made). They are ordinary pickups: anyone can take one (E), drop it (G), and they fall from a dead player like
##anything else. Like every pickup they are only drawn where the local player can see them (PlayerSight), which includes a room on a live camera feed. No
##map shows them.

@export var pickups : PickupControl

var facility : FacilityMap

var placed_rooms : Array[String] = [] #the rooms that got an item this match, in the order they were placed (for tests and tools)


## The map's own list, or none (no ItemRooms node).
func items() -> Array[Item]:
	var node : FacilityItemRooms = facility.item_rooms_node if facility != null else null
	return node.items if node != null else [] as Array[Item]


## Every item that can turn up anywhere, each once: the map's list, then the rooms' own lists, in scene order (the same on every peer). The roll's picks index this.
func all_items() -> Array[Item]:
	var result : Array[Item] = []
	var lists : Array = [items()]
	if facility != null:
		for room_id : String in facility.item_rooms():
			lists.append(facility.item_pool(room_id))
	for list : Array in lists:
		for item in list:
			if item is Item and not result.has(item):
				result.append(item)
	return result


## What can turn up in this room: its own list, or the map's when it has none (null entries left out, repeats kept: they make an item likelier).
func pool_of(room_id : String) -> Array[Item]:
	var own : Array = facility.item_pool(room_id) if facility != null else []
	var result : Array[Item] = []
	for item in (own if not own.is_empty() else items()):
		if item is Item:
			result.append(item)
	return result


##Lobby only. Which item goes where: {"items": PackedInt32Array of indices into all_items(), "at": PackedVector2Array of world positions}, one entry per room
##that rolled a hit (and has a free spot and something to put there).
func roll(rng : RandomNumberGenerator) -> Dictionary:
	var picks : PackedInt32Array = PackedInt32Array()
	var at : PackedVector2Array = PackedVector2Array()
	if facility == null:
		return {"items": picks, "at": at}
	var every : Array[Item] = all_items()
	for room_id : String in facility.item_rooms():
		if rng.randf() >= facility.item_chance(room_id):
			continue
		var pool : Array[Item] = pool_of(room_id)
		if pool.is_empty():
			continue
		var spots : PackedVector2Array = facility.item_spots(room_id)
		if spots.is_empty():
			push_warning("ItemSpawner: room %s has no clear spot by its walls for an item" % room_id)
			continue
		picks.append(every.find(pool[rng.randi_range(0, pool.size() - 1)]))
		at.append(facility.to_global(spots[rng.randi_range(0, spots.size() - 1)]))
	return {"items": picks, "at": at}


##Every peer, once, at load: puts roll()'s items on the floor.
func place(picks : PackedInt32Array, at : PackedVector2Array) -> void:
	var every : Array[Item] = all_items()
	placed_rooms.clear()
	for i in mini(picks.size(), at.size()):
		if picks[i] < 0 or picks[i] >= every.size():
			continue
		pickups.spawn(every[picks[i]], at[i])
		if facility != null:
			placed_rooms.append(facility.room_at(facility.to_local(at[i])))
