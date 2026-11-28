class_name SpawnLayer
extends MapLayer

##Spawn rooms, in their kind's colour (guard blue, intruder red) and labelled "GUARD SPAWN" / "INTRUDER SPAWN". The kind this player picks from
##(spawn_kind) is drawn strong; the other kind dimmed and dashed (show_other_kind). When `selectable`, hovering one of your kind lights it up and clicking it
##emits room_clicked. Also draws who has picked which room: a name tag per player, in the rooms they chose (set_picks).

signal room_clicked(room_id : String)

@export var selectable : bool = true
@export var show_other_kind : bool = true #also show the other kind's spawn rooms (dimmed, dashed, not clickable), so players know where the other side may start

var spawn_kind : int = SpawnRoomMarker.Kind.GUARD : set = set_spawn_kind
var own_pick : String = "" : set = set_own_pick #the local player's chosen room, drawn strongest
var local_id : int = 0 #whose tag is drawn as "YOU"
var _picks : Dictionary = {} #member id -> room id
var _names : Dictionary = {} #member id -> display name
var _hover : String = ""


func set_spawn_kind(value : int) -> void:
	spawn_kind = value
	queue_redraw()


func set_own_pick(value : String) -> void:
	own_pick = value
	queue_redraw()


##Who has picked which room (only the picks this peer may see), and the names to show for them.
func set_picks(picks : Dictionary, names : Dictionary) -> void:
	_picks = picks.duplicate()
	_names = names.duplicate()
	queue_redraw()


func rooms() -> Array[String]:
	return facility().spawn_rooms(spawn_kind) if facility() != null else [] as Array[String]


##The spawn room of this layer's kind at a world position, or "".
func room_at(world : Vector2) -> String:
	if facility() == null:
		return ""
	var room : String = facility().room_at(world)
	return room if rooms().has(room) else ""


func map_hover(world : Vector2) -> void:
	var now : String = room_at(world) if selectable else ""
	if now != _hover:
		_hover = now
		queue_redraw()


func map_click(world : Vector2) -> bool:
	if not selectable:
		return false
	var room : String = room_at(world)
	if room == "":
		return false
	room_clicked.emit(room)
	return true


func _draw() -> void:
	if facility() == null:
		return
	#every spawn room, the other kind's too (so you know where the other side may start), each labelled with its kind; only your own kind's can be
	#picked, and it is drawn stronger
	for kind : int in [SpawnRoomMarker.Kind.GUARD, SpawnRoomMarker.Kind.INTRUDER]:
		if kind != spawn_kind and not show_other_kind:
			continue
		var mine : bool = kind == spawn_kind
		var colour : Color = SpawnRoomMarker.colour_of(kind)
		for room : String in facility().spawn_rooms(kind):
			var fill : float = 0.08
			if mine:
				fill = 0.55 if room == own_pick else (0.3 if room == _hover else 0.16)
			var rects : Array[Rect2] = room_rects(room)
			for rect : Rect2 in rects:
				draw_rect(rect, Color(colour, fill))
				if mine:
					draw_rect(rect, colour, false, px(3.0 if room == own_pick else 2.0))
				else:
					_draw_dashed_rect(rect, Color(colour, 0.8), px(1.5))
			if not rects.is_empty():
				var top : Rect2 = rects[0]
				var text : String = "%s SPAWN" % SpawnRoomMarker.name_of(kind).to_upper()
				draw_label(Vector2(top.get_center().x, top.position.y + px(12.0)), text, 12, colour, maxf(top.size.x * view_zoom(), 120.0))
	#name tags: everyone in a room listed under its middle (below the room's name)
	var in_room : Dictionary = {} #room id -> [member ids]
	for member : int in _picks:
		var room : String = _picks[member]
		if facility().rooms.has(room):
			if not in_room.has(room):
				in_room[room] = []
			in_room[room].append(member)
	for room : String in in_room:
		var at : Vector2 = room_rects(room)[0].get_center() + Vector2(0.0, px(18.0))
		var members : Array = in_room[room]
		members.sort()
		for i in members.size():
			var member : int = members[i]
			var label : String = "YOU" if member == local_id else String(_names.get(member, "?"))
			var tag_colour : Color = Palette.TEXT if member == local_id else Palette.FLASH
			draw_label(at + Vector2(0.0, px(16.0) * i), label, 13, tag_colour)


func view_zoom() -> float:
	return view.zoom if view != null and view.zoom > 0.0 else 1.0


func _draw_dashed_rect(rect : Rect2, colour : Color, width : float) -> void:
	var dash : float = px(8.0)
	var corners : Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], colour, width, dash)


func icon_label(world : Vector2) -> String:
	if facility() == null:
		return ""
	var room : String = facility().room_at(world)
	if room == "":
		return ""
	for kind : int in [SpawnRoomMarker.Kind.GUARD, SpawnRoomMarker.Kind.INTRUDER]:
		if (kind == spawn_kind or show_other_kind) and facility().spawn_rooms(kind).has(room):
			var text : String = "%s spawn" % SpawnRoomMarker.name_of(kind)
			if kind != spawn_kind:
				text += ": the other side may start here"
			elif room == own_pick:
				text += ": you start here"
			elif selectable:
				text += ": click to start here"
			var pickers : Array[String] = []
			for member : int in _picks:
				if _picks[member] == room and member != local_id:
					pickers.append(String(_names.get(member, "?")))
			if not pickers.is_empty():
				pickers.sort()
				text += " (picked by %s)" % ", ".join(pickers)
			return text
	return ""


##Its labels name whole rooms (see MapLayer.labels_areas).
func labels_areas() -> bool:
	return true
