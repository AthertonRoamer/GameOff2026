extends SceneTree

## One-time conversion (history, do not run it again: it overwrites the scene, and the rooms have been edited since): builds facility_map.tscn (rooms,
## doors, vents and the door control panel as nodes) from the old facility_layout.json, keeping the order of the rooms and doors, so door numbers stay
## the same. After this the scene is what you edit, and the JSON is only history. (The scene has no tile layers: FacilityMap makes them itself.)
##   godot --headless --path . --script res://tools/art/convert_layout_to_scene.gd

const LAYOUT : String = "res://night_shift/environment/facility_layout.json"
const SCENE : String = "res://night_shift/environment/facility_map.tscn"
const DOOR_SCENE : PackedScene = preload("res://night_shift/environment/facility_door.tscn")
const PANEL_SCENE : PackedScene = preload("res://game/utility/door_control_panel.tscn")
const TILE : float = 11.0


func _init() -> void:
	var layout : Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var root : FacilityMap = FacilityMap.new()
	root.name = "FacilityMap"
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var rooms_node : Node2D = _add_node(root, "Rooms")
	var doors_node : Node2D = _add_node(root, "Doors")
	var vents_node : Node2D = _add_node(root, "Vents")
	var props : Node2D = _add_node(root, "Props")
	props.y_sort_enabled = true
	var actors : Node2D = _add_node(root, "Actors")
	actors.y_sort_enabled = true

	for data : Dictionary in layout["rooms"]:
		var room : FacilityRoom = FacilityRoom.new()
		room.name = data["id"]
		room.display_name = data["name"]
		room.kind = FacilityRoom.KIND_NAMES.find(data["kind"])
		room.function = maxi(0, FacilityRoom.FUNCTION_NAMES.find(data.get("function", "")))
		_add(rooms_node, room, root)
		var number : int = 1
		for r : Array in data["rects"]:
			var rect : FacilityRoomRect = FacilityRoomRect.new()
			rect.name = "Rect%d" % number
			rect.position = Vector2(int(r[0]) * TILE, int(r[1]) * TILE)
			rect.size = Vector2((int(r[2]) - int(r[0]) + 1) * TILE, (int(r[3]) - int(r[1]) + 1) * TILE)
			_add(room, rect, root)
			number += 1
	for data : Dictionary in layout["doors"]:
		var r : Array = data["rect"]
		var cells : Vector2 = Vector2(int(r[2]) - int(r[0]) + 1, int(r[3]) - int(r[1]) + 1)
		var door : FacilityDoor = DOOR_SCENE.instantiate()
		door.name = "Door_%s_%s" % [data["a"], data["b"]]
		door.horizontal = cells.x >= cells.y
		door.position = Vector2(int(r[0]), int(r[1])) * TILE + cells * TILE / 2.0
		_add(doors_node, door, root)

	var vent_number : int = 1
	for v : Array in layout.get("vents", []):
		var marker : Marker2D = Marker2D.new()
		marker.name = "Vent%d" % vent_number
		marker.position = Vector2(int(v[0]), int(v[1])) * TILE
		_add(vents_node, marker, root)
		vent_number += 1

	var panel : ControlPanel = PANEL_SCENE.instantiate() #the door console stood against the north wall of the Door Control room
	panel.name = "DoorControlPanel"
	panel.position = Vector2(85.0 * TILE + 62.0, 37.0 * TILE + 22.0)
	_add(props, panel, root)

	var packed : PackedScene = load(SCENE)
	var error : Error = packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, SCENE)
	print("convert_layout_to_scene: %s" % error_string(error))
	quit(0 if error == OK else 1)


func _add(parent : Node, node : Node, owner_node : Node) -> void:
	parent.add_child(node)
	node.owner = owner_node


func _add_node(parent : Node, node_name : String) -> Node2D:
	var node : Node2D = Node2D.new()
	node.name = node_name
	_add(parent, node, parent.owner if parent.owner != null else parent)
	return node
