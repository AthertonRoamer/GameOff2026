@tool
class_name SpawnRoomMarker
extends Marker2D

##Makes the room it stands on a spawn room: players of its kind may choose to start there (see SpawnSelectPhase). Use the two kinds, GuardSpawn and
##IntruderSpawn: drag one onto a room in the map's 2D view. Only its position matters, not where it is in the scene tree (keep them under the map's
##Spawns node); it is also where players who pick that room appear, side by side around it. The map finds the room under it whenever it builds, and
##the room shows a badge in the editor. A marker on a wall, in the void or on an exit zone does nothing and gets a warning.
##Guards (defenders and secretly attacking guards alike) start in guard rooms; intruders in intruder rooms.

enum Kind { GUARD, INTRUDER }

const KIND_NAMES : Array[String] = ["guard", "intruder"]
const COLOURS : Array[Color] = [Color("#4f8ff0"), Color("#e5484d")] #guard blue, intruder red
const LETTERS : Array[String] = ["G", "I"]
const ICON_RADIUS : float = 16.0

var kind : Kind = Kind.GUARD #set by GuardSpawn / IntruderSpawn
var room_id : String = "" #the room under it, set by the map when it builds
var problem : String = "" #set by the map when it is not on a room, shown as a warning in the editor


##Which kind of spawn room a player with this role starts in. A secretly attacking guard is a guard, so it starts where guards do.
static func kind_for(role : Role) -> Kind:
	return Kind.INTRUDER if role != null and role.is_intruder() else Kind.GUARD


static func colour_of(spawn_kind : int) -> Color:
	return COLOURS[spawn_kind]


static func name_of(spawn_kind : int) -> String:
	return KIND_NAMES[spawn_kind]


func set_problem(text : String) -> void:
	if text != problem:
		problem = text
		update_configuration_warnings()
		queue_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray([problem]) if problem != "" else PackedStringArray()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint(): #only shown while editing the map
		return
	var colour : Color = Palette.METAL if problem != "" else colour_of(kind) #grey when misplaced (red is the intruder colour)
	draw_circle(Vector2.ZERO, ICON_RADIUS, Color(Palette.VOID, 0.85))
	draw_arc(Vector2.ZERO, ICON_RADIUS, 0.0, TAU, 32, colour, 2.5)
	draw_string(ThemeDB.fallback_font, Vector2(-ICON_RADIUS, 6.0), "!" if problem != "" else LETTERS[kind], HORIZONTAL_ALIGNMENT_CENTER, ICON_RADIUS * 2.0, 18, colour)
