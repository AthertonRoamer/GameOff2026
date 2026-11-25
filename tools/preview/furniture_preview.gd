extends Node2D

## Renders the furnished map with the game's darkness and a flashlight (one beam for each height, like the player's, see LightLayers), for looking at how the furniture is
## lit and what it shadows, and times it. Needs a window (not headless):
##   Godot.exe --path . res://tools/preview/furniture_preview.tscn -- <folder to save the pictures in>            pictures only
##   Godot.exe --path . res://tools/preview/furniture_preview.tscn -- <folder> bench                              also times the frames three ways (bench.txt in the folder)
##   ... -- <folder> beams                                                                                        also one picture of the table for each of the four beams on its own
## It saves one picture per spot below and quits.

const SMALL_MAP : String = "res://game/environment/facility_map.tscn"
const BIG_MAP : String = "res://game/environment/facility_map_wings.tscn"
const CONE : Texture2D = preload("res://game/player/flashlight/flashlight_cone.png")
const DARKNESS : Color = Color(0.176, 0.186, 0.248)
const SPOTS : Array[Dictionary] = [ #name, where the camera looks, where the flashlight is, which way it points (degrees)
	{"name": "office", "camera": Vector2(300, 1030), "light": Vector2(330, 1130), "angle": -80.0},
	{"name": "camera_room", "camera": Vector2(790, 500), "light": Vector2(860, 600), "angle": -125.0},
	{"name": "records", "camera": Vector2(1400, 1040), "light": Vector2(1440, 1150), "angle": -95.0},
	{"name": "cafeteria", "camera": Vector2(1633, 600), "light": Vector2(1600, 780), "angle": -75.0},
	{"name": "generator", "camera": Vector2(800, 720), "light": Vector2(670, 800), "angle": -20.0},
	{"name": "table_beam", "camera": Vector2(380, 150), "light": Vector2(380, 262), "angle": -90.0},
	{"name": "rack_beam", "camera": Vector2(420, 460), "light": Vector2(420, 560), "angle": -90.0},
	{"name": "desk_beam", "camera": Vector2(130, 990), "light": Vector2(130, 1100), "angle": -90.0},
	{"name": "chair_table", "camera": Vector2(175, 215), "light": Vector2(175, 274), "angle": -90.0},
	{"name": "lockers_dark", "camera": Vector2(1450, 190), "light": Vector2(1450, 190), "angle": 0.0, "dark": true},
]
const BIG_SPOTS : Array[Dictionary] = [ #the same for the big map (add `big` as the last argument)
	{"name": "big_armory", "camera": Vector2(3030, 1450), "light": Vector2(3030, 1600), "angle": -90.0},
	{"name": "big_cafeteria", "camera": Vector2(3646, 4500), "light": Vector2(3646, 4800), "angle": -90.0},
	{"name": "big_server", "camera": Vector2(2546, 2590), "light": Vector2(2546, 2840), "angle": -90.0},
	{"name": "big_generator", "camera": Vector2(5186, 2650), "light": Vector2(5186, 2950), "angle": -90.0},
	{"name": "big_atrium", "camera": Vector2(3470, 3200), "light": Vector2(3470, 3500), "angle": -90.0},
	{"name": "big_barracks", "camera": Vector2(2766, 4000), "light": Vector2(2766, 4250), "angle": -90.0},
]
const BENCH_SPOTS : PackedStringArray = ["office", "records", "camera_room", "generator", "cafeteria", "big_armory", "big_cafeteria", "big_server", "big_generator", "big_atrium"]
const WARMUP_FRAMES : int = 150 #(the map paints its tiles a few chunks a frame after the camera moves: let that finish)
const BENCH_FRAMES : int = 240

var _map : FacilityMap
var _camera : Camera2D
var _lights : Array[PointLight2D] = []
var _spots : Array[Dictionary] = SPOTS


func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var folder : String = args[0] if not args.is_empty() else "."
	var big : bool = args.has("big")
	_spots = BIG_SPOTS if big else SPOTS
	_map = (load(BIG_MAP if big else SMALL_MAP) as PackedScene).instantiate()
	add_child(_map)
	var dark : CanvasModulate = CanvasModulate.new()
	dark.color = DARKNESS
	add_child(dark)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(3, 3)
	add_child(_camera)
	var light : PointLight2D = PointLight2D.new()
	light.name = "Cone"
	light.texture = CONE
	light.texture_scale = 0.945
	light.offset = Vector2(242, 0)
	light.energy = 1.7
	light.color = Color(1, 0.953, 0.769)
	light.shadow_enabled = true
	light.shadow_filter = 1
	add_child(light)
	_lights = LightLayers.add_height_cones(light)
	await get_tree().process_frame
	for spot : Dictionary in _spots:
		_aim(spot)
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [folder, spot["name"]])
	if args.size() > 1 and args[1] == "beams": #one picture of the table for each beam on its own
		for k in _lights.size():
			_aim(_spots[mini(5, _spots.size() - 1)])
			for i in _lights.size():
				_lights[i].enabled = i == k
			for i in 8:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/beam_%d.png" % [folder, k])
	if args.size() > 1 and args[1] == "bench":
		await _bench(folder)
	get_tree().quit()


func _aim(spot : Dictionary) -> void:
	_camera.position = spot["camera"]
	for light : PointLight2D in _lights:
		light.position = spot["light"]
		light.rotation_degrees = spot["angle"]
		light.enabled = not spot.get("dark", false)


## Average and slowest-5% frame time at several spots, with no furniture, with furniture lit by one beam that takes every shadow, and with furniture lit the real way.
func _bench(folder : String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var report : PackedStringArray = []
	var furnishing : Node = _map.props_node.get_node("Furnishing")
	var props : Node = furnishing.get_parent()
	for config : String in ["no furniture, one beam", "furniture, one beam (no heights)", "furniture, four beams (heights)"]:
		if config.begins_with("no"):
			props.remove_child(furnishing)
		elif furnishing.get_parent() == null:
			props.add_child(furnishing)
		for i in _lights.size():
			_lights[i].enabled = i == 0 or config.begins_with("furniture, four")
		if not config.begins_with("furniture, four"):
			_lights[0].range_item_cull_mask = LightLayers.ALL_PICTURES #(furniture is on its own layers: this one beam has to light them all and take every shadow)
			_lights[0].shadow_item_cull_mask = LightLayers.ALL
		else:
			_lights[0].range_item_cull_mask = LightLayers.receiver_layer(LightLayers.Tier.FLAT)
			_lights[0].shadow_item_cull_mask = LightLayers.shadow_layers(LightLayers.Tier.FLAT)
		var times : Array[float] = []
		for spot : Dictionary in _spots:
			if not BENCH_SPOTS.has(spot["name"]):
				continue
			_aim(spot)
			for i in _lights.size():
				_lights[i].enabled = i == 0 or config.begins_with("furniture, four")
			for i in WARMUP_FRAMES:
				await get_tree().process_frame
			var last : int = Time.get_ticks_usec()
			for i in BENCH_FRAMES:
				await RenderingServer.frame_post_draw
				var now : int = Time.get_ticks_usec()
				times.append((now - last) / 1000.0)
				last = now
		times.sort()
		var total : float = 0.0
		for t : float in times:
			total += t
		var worst : float = 0.0
		var worst_count : int = maxi(1, times.size() / 20)
		for t : float in times.slice(times.size() - worst_count):
			worst += t
		report.append("%-36s average %.2f ms   slowest 5%% %.2f ms   (%d frames)" % [config, total / times.size(), worst / worst_count, times.size()])
	FileAccess.open("%s/bench.txt" % folder, FileAccess.WRITE).store_string("\n".join(report) + "\n")
	print("\n".join(report))
