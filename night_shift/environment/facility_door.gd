@tool
class_name FacilityDoor
extends StaticBody2D

##A sliding gate, one metre wide (4 cells) and a wall thick, sitting in a wall. Closed and locked doors block movement (physics layer 4) and light.
##This is only the visual and physical door. Who may open it, and what it costs the generator, is game logic: call set_state().
##It is a scene (facility_door.tscn): place instances under the map's Doors node and drag them into a wall (position snaps to the cell grid by itself).
##Turn `horizontal` off for a gate in a vertical wall; the collision shape, light occluder and art follow. Which two rooms it joins and whether it leads
##outside are worked out by the map from what is on each side, and set on room_a, room_b and exterior when it is built.

signal state_changed(new_state : State)

enum State { OPEN, CLOSED, LOCKED }

const ART_DIR : String = "res://night_shift/environment/art/"
const LENGTH_PX : float = 44.0 #a gate is one metre long and one wall (a quarter metre) thick

@export var horizontal : bool = true : set = set_horizontal #true: the gate sits in a horizontal wall and is 4 cells wide, false: vertical wall, 4 cells tall
@export var state : State = State.CLOSED : set = set_state
@export var exterior : bool = false : set = set_exterior #heavier door with hazard stripes, leads outside (the map sets it from the rooms)

var door_index : int = -1 #its place among the Doors children, set by the map. Every peer loads the same scene, so the index names the same door everywhere
var room_a : String = "" #the room to the north (horizontal) or west (vertical), set by the map
var room_b : String = ""

@onready var _sprite : Sprite2D = $Sprite
@onready var _shape : CollisionShape2D = $Shape
@onready var _occluder : LightOccluder2D = $Occluder


func _ready() -> void:
	_apply_orientation()
	_apply()


func set_horizontal(value : bool) -> void:
	horizontal = value
	if is_node_ready():
		_apply_orientation()
		_apply()


func set_exterior(value : bool) -> void:
	exterior = value
	if is_node_ready():
		_apply()


func set_state(new_state : State) -> void:
	if state == new_state and is_node_ready():
		return
	state = new_state
	if is_node_ready():
		_apply()
		state_changed.emit(state)


func is_blocking() -> bool:
	return state != State.OPEN


##The cells the gate covers, in the map's cell grid (the map passes itself, whose origin the cells count from).
func cell_rect(space : Node2D) -> Rect2i:
	var cells : Vector2i = Vector2i(4, 1) if horizontal else Vector2i(1, 4)
	var top_left : Vector2 = space.to_local(global_position) - Vector2(cells * FacilityTileSet.TILE) / 2.0
	return Rect2i(roundi(top_left.x / FacilityTileSet.TILE), roundi(top_left.y / FacilityTileSet.TILE), cells.x, cells.y)


##Puts the gate's cells on the grid.
func snap_to_grid() -> void:
	var cells : Vector2 = Vector2(4, 1) if horizontal else Vector2(1, 4)
	var tile : float = FacilityTileSet.TILE
	var top_left : Vector2 = ((position - cells * tile / 2.0) / tile).round() * tile
	if not position.is_equal_approx(top_left + cells * tile / 2.0):
		position = top_left + cells * tile / 2.0


func _apply_orientation() -> void:
	var size : Vector2 = Vector2(LENGTH_PX, FacilityTileSet.TILE) if horizontal else Vector2(FacilityTileSet.TILE, LENGTH_PX)
	(_shape.shape as RectangleShape2D).size = size
	_occluder.occluder.polygon = PackedVector2Array([-size / 2.0, Vector2(size.x, -size.y) / 2.0, size / 2.0, Vector2(-size.x, size.y) / 2.0])


func _apply() -> void:
	var state_name : String = ["open", "closed", "locked"][state]
	_sprite.texture = load("%sdoor_%s_%s_%s.png" % [ART_DIR, "exterior" if exterior else "interior", state_name, "h" if horizontal else "v"])
	_shape.set_deferred("disabled", state == State.OPEN)
	_occluder.visible = state != State.OPEN