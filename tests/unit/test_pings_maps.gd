extends Node

## The maps' shared icons (MapIntel), pings (placing them from a map, the naming box), the chat fading away, and the role reveal's who's who.
##   Godot_console.exe --headless --path . res://tests/unit/test_pings_maps.tscn

const MAPS : Dictionary = { #scene -> where its FacilityMapView is
	"res://game/ui/map_view/map_screen.tscn": "Map",
	"res://game/utility/door_map_screen.tscn": "Map",
	"res://game/abilities/vent_screen.tscn": "Map",
	"res://game/phases/spawn_select/spawn_select_phase.tscn": "Screen/Margin/Box/Map",
	"res://game/player_hud/player_hud.tscn": "Minimap",
}
const ICONS : Array[String] = ["Rooms", "Regions", "RelicRooms", "Exits", "Doors", "Vents", "Consoles", "Generators", "Pings"]
const PANEL : String = "res://game/utility/door_map_screen.tscn" #the only map with the lights, the cameras and the doors' state

var _failures : int = 0


func check(ok : bool, what : String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _ready() -> void:
	print("every map has the same icons, and only the panel has the panel's")
	for path : String in MAPS:
		var scene : Node = (load(path) as PackedScene).instantiate()
		var view : Node = scene.get_node(MAPS[path])
		var missing : Array = ICONS.filter(func(n : String) -> bool: return not view.has_node(n))
		check(missing.is_empty(), "%s %s" % [path.get_file(), "" if missing.is_empty() else "lacks %s" % [missing]])
		var panel : bool = path == PANEL
		check(view.has_node("Lights") == panel and view.has_node("Cameras") == panel and (view.get_node("Doors") as DoorsLayer).show_state == panel, "%s: lights, cameras and door states %s" % [path.get_file(), "shown" if panel else "not shown"])
		scene.free()

	var facility : FacilityMap = (load("res://game/environment/facility_map_wings.tscn") as PackedScene).instantiate()
	add_child(facility)
	var player : Player = (load("res://game/player/player.tscn") as PackedScene).instantiate()
	player.role = load("res://game/roles/guard.tres")
	add_child(player)
	var intel : MapIntel = MapIntel.new()
	add_child(intel)
	intel.viewer = func() -> Player: return player
	var chooser : DesignatedExitChooser = DesignatedExitChooser.new()
	add_child(chooser)
	chooser.designated = facility.exits.keys()[0]
	intel.exit_chooser = chooser
	var screen : MapScreen = (load("res://game/ui/map_view/map_screen.tscn") as PackedScene).instantiate()
	screen.facility = facility
	add_child(screen)
	screen.size = Vector2(1280, 720)
	screen.player = player
	screen.exit_chooser = chooser
	screen.open()
	await get_tree().process_frame
	await get_tree().process_frame

	print("who sees what")
	var generators : GeneratorsLayer = screen.map.get_node("Generators")
	var exits : ExitsLayer = screen.map.get_node("Exits")
	check(generators.visible and exits.highlighted == "", "a guard: generators, no target exit")
	player.role = load("res://game/roles/infiltrator.tres")
	await get_tree().process_frame
	await get_tree().process_frame
	check(generators.visible and exits.highlighted == chooser.designated, "an intruder: generators too, and the target exit")
	var doors : DoorsLayer = screen.map.get_node("Doors")
	check(doors.zoom_alpha(0.8) == 1.0 and is_equal_approx(doors.zoom_alpha(0.05), doors.faded_alpha) and doors.faded_alpha < 0.3, "zoomed out, the doors fade")
	screen.map.fit_all()
	await get_tree().process_frame
	var names : RegionNamesLayer = screen.map.get_node("RegionNames")
	var tags : Array = (screen.map.get_node("Regions") as RegionsLayer).name_tags(names).values()
	var apart : bool = true
	for i in tags.size():
		for j in range(i + 1, tags.size()):
			apart = apart and not (tags[i] as Rect2).intersects(tags[j])
	check(tags.size() == facility.regions.size() and apart, "zoomed out, no zone name covers another (%d)" % tags.size())
	check(names.get_index() > screen.map.get_node("Generators").get_index() and names.get_index() > doors.get_index(), "zone names are drawn over the icons")
	check((screen.map.get_node("Doors") as DoorsLayer).interactive == false and (screen.map.get_node("Vents") as VentsLayer).interactive == false, "the full map's icons take no clicks")

	print("pings from a map")
	var asked : Array = []
	intel.ping_requested.connect(func(at : Vector2, on_screen : Vector2) -> void: asked.append([at, on_screen]))
	var point : Vector2 = Vector2(300, 200)
	screen.map._gui_input(_button(MOUSE_BUTTON_MIDDLE, true, point))
	screen.map._gui_input(_button(MOUSE_BUTTON_MIDDLE, false, point))
	check(asked.size() == 1 and (asked[0][0] as Vector2).distance_to(facility.to_global(screen.map.screen_to_world(point))) < 0.5, "a middle click asks for a ping there")
	screen.map._gui_input(_button(MOUSE_BUTTON_MIDDLE, true, point))
	var drag : InputEventMouseMotion = InputEventMouseMotion.new()
	drag.position = point + Vector2(60, 0)
	drag.relative = Vector2(60, 0)
	screen.map._gui_input(drag)
	screen.map._gui_input(_button(MOUSE_BUTTON_MIDDLE, false, point + Vector2(60, 0)))
	check(asked.size() == 1, "a middle drag scrolls and does not ping")
	for i in 5:
		intel.add_ping(0, "Ann", Vector2(i, 0), "spot %d" % i)
	intel.add_ping(1, "Zed", Vector2.ZERO, "")
	check(intel.pings.size() == intel.pings_per_player + 1 and intel.pings[0]["label"] == "spot 2", "a player's oldest pings make way")
	check(PingsLayer.caption(intel.pings[0]) == "spot 2" and PingsLayer.caption(intel.pings[-1]) == "Zed", "a ping shows its label, or who placed it")
	intel.ping_seconds = 0.2
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	check(intel.pings.is_empty(), "pings expire")
	screen.close()

	await _test_box_and_chat(player)
	await _test_roster()
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(_failures)


func _test_box_and_chat(player : Player) -> void:
	print("the naming box and the chat")
	var relay : RecordingRelay = RecordingRelay.new()
	add_child(relay)
	var hud : CanvasLayer = (load("res://game/player_hud/player_hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	player.health = 100.0
	hud.bind_chat(relay, player, [0, 1] as Array[int])
	hud.chat.switch_to(1)
	var box : PingControl = hud.ping_control
	box.open(Vector2(40, 50), Vector2(5000, 5000))
	check(box.is_open() and player.input.typing and (box.get_node("Box/Panel/Rows/Title") as Label).text == "PING TO INTRUDERS", "it opens, holds the player still and says the channel")
	var panel : PanelContainer = box.get_node("Box/Panel")
	check(Rect2(Vector2.ZERO, panel.get_viewport_rect().size).encloses(panel.get_global_rect()), "it stays on the screen")
	(box.get_node("Box/Panel/Rows/Label") as LineEdit).text = "guard here"
	box.place()
	check(relay.sent == [[1, Vector2(40, 50), "guard here"]] and not box.is_open() and not player.input.typing, "placing sends the label on that channel and gives the player back")
	box.open(Vector2.ZERO, Vector2.ZERO)
	box.close()
	check(relay.sent.size() == 1, "closing sends nothing")

	var chat : ChatWindow = hud.chat
	chat.idle_hide_seconds = 0.3
	chat.fade_seconds = 0.1
	chat.wake()
	await get_tree().create_timer(0.7).timeout
	check(chat.is_faded() and chat._log.modulate.a == 0.0 and chat._header.modulate.a == 0.0 and chat.self_modulate.a == 0.0 and chat._log.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED, "idle, the chat fades away and takes no clicks")
	check(chat._line.is_visible_in_tree() and chat._line.modulate.a == 1.0 and chat.modulate.a == 1.0 and chat._line.placeholder_text.contains("Enter"), "but the line to type in, \"Press Enter to chat\", always shows")
	relay.message_received.emit(0, "Bob", "hello", false)
	check(not chat.is_faded() and chat._log.modulate.a == 1.0 and chat.self_modulate.a == 1.0, "a message brings it back")
	await get_tree().create_timer(0.7).timeout
	var enter : InputEventAction = InputEventAction.new()
	enter.action = "chat_open"
	enter.pressed = true
	chat._unhandled_input(enter)
	await get_tree().process_frame
	check(not chat.is_faded() and chat.is_typing(), "Enter opens it to type")
	await get_tree().create_timer(0.7).timeout
	check(not chat.is_faded(), "it stays while typing")
	chat.stop_typing()
	hud.visible = false
	hud.show_chat_early(true, true)
	await get_tree().create_timer(0.7).timeout
	check(hud.chat_layer.visible and chat.is_visible_in_tree() and not chat.is_faded(), "at the role reveal it is up although the HUD is not, and stays")
	hud.show_chat_early(false)
	await get_tree().process_frame
	check(not hud.chat_layer.visible, "with neither, it is hidden")
	hud.queue_free()
	relay.queue_free()


func _test_roster() -> void:
	print("who's who at the role reveal")
	var reveal : RoleRevealPhase = (load("res://game/phases/role_reveal/role_reveal_phase.tscn") as PackedScene).instantiate()
	add_child(reveal)
	var roster : Array[Dictionary] = [{"id": 1, "name": "Ann", "role": load("res://game/roles/medic.tres")}, {"id": 2, "name": "Zed", "role": load("res://game/roles/infiltrator.tres")}]
	reveal.show_roster(roster, 1)
	var lines : Array = reveal.roster_box.get_children().map(func(l : Label) -> String: return l.text)
	check(lines.size() == 4 and lines[0] == "INTRUDER" and lines[1].begins_with("Zed") and lines[2] == "GUARDS" and lines[3].begins_with("Ann (you)"), "the intruder apart, then the guards by role: %s" % [lines])
	reveal.queue_free()


func _button(index : MouseButton, pressed : bool, at : Vector2) -> InputEventMouseButton:
	var event : InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = at
	return event


class RecordingRelay extends ChatRelay:
	var sent : Array = []

	func submit_ping(channel : int, at : Vector2, label : String) -> void:
		sent.append([channel, at, label])
