class_name MapIntel
extends Node

##What every map shows, in one place, so the minimap, the full map, the door console, the vent map and the spawn map never disagree. Game holds one (the
##MapIntel node in game.tscn) and fills in where to look; each FacilityMapView that is on screen asks it to feed its layers (apply). To give a map another
##kind of icon, add the layer to that map's scene: it is fed from here. What the door panel runs (which doors are open, the lights, the cameras) is on its map
##only. Who may see what is decided here too: the power numbers are for guards, the target exit for intruders. It also keeps the pings (ChatRelay brings them) and passes on a map's request to place one (PingControl).

signal ping_requested(at : Vector2, screen_position : Vector2) #a map was middle clicked: a world position, and where on the screen the click was

const GROUP : StringName = &"map_intel"

@export_range(2.0, 60.0, 0.5, "suffix:s") var ping_seconds : float = 12.0 ## how long a ping stays up
@export_range(1, 10) var pings_per_player : int = 3 ## a player's older pings go when they place more

var viewer : Callable = Callable() ## () -> this peer's own Player, or null (set by Game, with the rest)
var power : PowerGrid
var control : FacilityControl
var abilities : AbilityControl
var exit_chooser : DesignatedExitChooser
var relic_rooms : Array[String] = []
var pings : Array[Dictionary] = [] #oldest first: {"channel", "sender", "at" (world), "label", "born" (msec)}


func _ready() -> void:
	add_to_group(GROUP)


func add_ping(channel : int, sender : String, at : Vector2, label : String) -> void:
	var own : Array[Dictionary] = pings.filter(func(p : Dictionary) -> bool: return p["sender"] == sender and p["channel"] == channel)
	while own.size() >= pings_per_player:
		pings.erase(own.pop_front())
	pings.append({"channel": channel, "sender": sender, "at": at, "label": label, "born": Time.get_ticks_msec()})


func request_ping(at : Vector2, screen_position : Vector2) -> void:
	ping_requested.emit(at, screen_position)


func _process(_delta : float) -> void:
	var oldest : int = Time.get_ticks_msec() - int(ping_seconds * 1000.0)
	while not pings.is_empty() and pings[0]["born"] < oldest:
		pings.pop_front()


## Feeds a map's layers. Only what a screen does not run itself is set: a layer that takes clicks (interactive doors, lights, cameras, vents) belongs to its screen.
func apply(view : FacilityMapView) -> void:
	var player : Variant = viewer.call() if viewer.is_valid() else null
	if not is_instance_valid(player):
		player = null
	var guard : bool = player != null and PowerReadout.shows_power_to(player)
	var intruder : bool = player is Player and (player as Player).role != null and (player as Player).role.is_intruder()
	for layer : MapLayer in view.layers():
		if layer is RegionsLayer:
			var regions : RegionsLayer = layer
			regions.grid = power
			if not regions.power_for_everyone:
				regions.show_power = guard
		elif layer is GeneratorsLayer:
			(layer as GeneratorsLayer).grid = power #(where they are is everyone's to see: only the power numbers are the guards')
		elif layer is ExitsLayer:
			var exits : ExitsLayer = layer
			if not exits.show_all: #(the spawn map shows every exit and picks out the target itself)
				var target : String = exit_chooser.designated if intruder and exit_chooser != null else ""
				if exits.highlighted != target:
					exits.highlighted = target
		elif layer is RelicRoomsLayer:
			if (layer as RelicRoomsLayer).rooms != relic_rooms:
				(layer as RelicRoomsLayer).rooms = relic_rooms
		elif layer is VentsLayer:
			if not (layer as VentsLayer).interactive and abilities != null:
				(layer as VentsLayer).vents = abilities.vents
		elif layer is PingsLayer:
			(layer as PingsLayer).pings = pings
