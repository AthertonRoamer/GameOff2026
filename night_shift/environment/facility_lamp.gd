class_name FacilityLamp
extends PointLight2D

##A ceiling lamp running on the backup generator. Warm amber, hard banded edge (the light texture has 4 flat steps, matching the
##sprites' cel shading). Shadows are on, so a lamp never lights the next room through the wall. Call set_powered() from the utility
##rooms' light control.

const TEXTURE_PATH : String = "res://night_shift/environment/art/light_radial.png"
const TEXTURE_RADIUS_PX : float = 128.0 #radius of the generated texture

@export var radius_m : float = 6.0
@export var powered : bool = true : set = set_powered
@export var flicker : bool = false #a failing lamp

var _base_energy : float = 1.3
var _time : float = 0.0


func _ready() -> void:
	texture = load(TEXTURE_PATH)
	texture_scale = radius_m * 44.0 / TEXTURE_RADIUS_PX
	color = Color("#f2b544") if color == Color.WHITE else color
	energy = _base_energy
	shadow_enabled = true
	shadow_filter = SHADOW_FILTER_NONE #crisp shadow edges, the pixel look
	set_powered(powered)


func set_powered(on : bool) -> void:
	powered = on
	enabled = on


func _process(delta : float) -> void:
	if not flicker or not powered:
		return
	_time += delta
	energy = _base_energy * (0.35 if fmod(_time * 7.0, 1.0) > 0.8 or sin(_time * 31.0) > 0.92 else 1.0)
