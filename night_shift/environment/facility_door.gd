class_name FacilityDoor
extends StaticBody2D

##A sliding gate, one metre wide (4 cells) and a wall thick, sitting in a wall. Closed and locked doors block movement (physics layer 4) and light.
##This is only the visual and physical door. Who may open it, and what it costs the generator, is game logic: call set_state().

signal state_changed(new_state : State)

enum State { OPEN, CLOSED, LOCKED }

const ART_DIR : String = "res://night_shift/environment/art/"
const LENGTH_PX : float = 44.0 #a gate is one metre long and one wall (a quarter metre) thick

@export var exterior : bool = false #heavier door with hazard stripes, leads outside
@export var horizontal : bool = true #true: the gate sits in a horizontal wall and is 4 cells wide, false: vertical wall, 4 cells tall
@export var state : State = State.CLOSED : set = set_state

var door_index : int = -1
var room_a : String = ""
var room_b : String = ""

var _sprite : Sprite2D
var _shape : CollisionShape2D
var _occluder : LightOccluder2D


func _ready() -> void:
	collision_layer = FacilityTileSet.DOOR_LAYER
	collision_mask = 0
	var size : Vector2 = Vector2(LENGTH_PX, FacilityTileSet.TILE) if horizontal else Vector2(FacilityTileSet.TILE, LENGTH_PX)
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2.ONE * FacilityTileSet.ART_SCALE #drawn at 176 px per metre, shown at 44
	add_child(_sprite)
	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	(_shape.shape as RectangleShape2D).size = size
	add_child(_shape)
	_occluder = LightOccluder2D.new()
	_occluder.occluder = OccluderPolygon2D.new()
	_occluder.occluder.polygon = PackedVector2Array([-size / 2.0, Vector2(size.x, -size.y) / 2.0, size / 2.0, Vector2(-size.x, size.y) / 2.0])
	add_child(_occluder)
	_apply()


func set_state(new_state : State) -> void:
	if state == new_state and _sprite != null:
		return
	state = new_state
	if _sprite != null:
		_apply()
		state_changed.emit(state)


func is_blocking() -> bool:
	return state != State.OPEN


func _apply() -> void:
	var state_name : String = ["open", "closed", "locked"][state]
	_sprite.texture = load("%sdoor_%s_%s_%s.png" % [ART_DIR, "exterior" if exterior else "interior", state_name, "h" if horizontal else "v"])
	_shape.set_deferred("disabled", state == State.OPEN)
	_occluder.visible = state != State.OPEN
