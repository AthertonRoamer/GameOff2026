class_name Flashlight
extends Node2D

##A flashlight: a soft cone of warm light, 11 m long and 56 degrees wide, that walls and closed gates stop, plus a small glow around the carrier so
##the character stays visible. It lives under the player's torso (see player_skin.tscn), which already turns to face the aim, so the beam comes out of
##the front of the torso with nothing else to steer. Only its on/off state is a decision; set `on`.
##The beam points along the node's local +X, so the node is turned -90 degrees under the torso, whose "forward" is up in the sprite sheet.

@export var on : bool = false : set = set_on
@export var range_m : float = 11.0
@export var cone_energy : float = 1.3
@export var halo_radius_m : float = 1.6
@export var halo_energy : float = 0.45
@export var color : Color = Color("#fff3c4")

const WORLD_PX_PER_M : float = 44.0
const CONE_WIDTH : int = 512
const CONE_HEIGHT : int = 256
const CONE_HALF_ANGLE : float = deg_to_rad(28.0)

static var _cone_texture : ImageTexture
static var _halo_texture : GradientTexture2D

var _cone : PointLight2D
var _halo : PointLight2D


func _ready() -> void:
	#the node sits under a scaled sprite, so the lights are sized against the scale they inherit
	var inherited : float = global_transform.get_scale().x
	_cone = PointLight2D.new()
	_cone.texture = _get_cone_texture()
	_cone.texture_scale = range_m * WORLD_PX_PER_M / CONE_WIDTH / inherited
	#the texture's left edge has to be the light's origin. The offset is not scaled with the texture, so it is worked out in the scaled size
	_cone.offset = Vector2(CONE_WIDTH / 2.0 * _cone.texture_scale, 0.0)
	_cone.color = color
	_cone.energy = cone_energy
	_cone.shadow_enabled = true
	_cone.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(_cone)
	_halo = PointLight2D.new()
	_halo.texture = _get_halo_texture()
	_halo.texture_scale = halo_radius_m * WORLD_PX_PER_M * 2.0 / _halo.texture.get_width() / inherited
	_halo.color = color
	_halo.energy = halo_energy
	_halo.shadow_enabled = true
	_halo.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(_halo)
	set_on(on)


func set_on(value : bool) -> void:
	on = value
	if _cone != null:
		_cone.enabled = value
		_halo.enabled = value


func toggle() -> void:
	set_on(not on)


##A cone pointing right from the middle of the left edge: brightest at the source, fading with distance, with soft edges.
static func _get_cone_texture() -> ImageTexture:
	if _cone_texture == null:
		var image : Image = Image.create(CONE_WIDTH, CONE_HEIGHT, false, Image.FORMAT_RGBA8)
		var middle : float = (CONE_HEIGHT - 1) / 2.0
		for y in CONE_HEIGHT:
			for x in CONE_WIDTH:
				var distance : float = Vector2(x, y - middle).length() / CONE_WIDTH
				var angle : float = absf(atan2(y - middle, x + 0.001))
				var level : float = 0.0
				if distance < 1.0 and angle <= CONE_HALF_ANGLE:
					level = pow(1.0 - distance, 1.4) * smoothstep(CONE_HALF_ANGLE, CONE_HALF_ANGLE * 0.55, angle)
				image.set_pixel(x, y, Color(level, level, level, 1.0))
		_cone_texture = ImageTexture.create_from_image(image)
	return _cone_texture


static func _get_halo_texture() -> GradientTexture2D:
	if _halo_texture == null:
		var gradient : Gradient = Gradient.new()
		gradient.colors = PackedColorArray([Color.WHITE, Color.BLACK])
		_halo_texture = GradientTexture2D.new()
		_halo_texture.gradient = gradient
		_halo_texture.fill = GradientTexture2D.FILL_RADIAL
		_halo_texture.fill_from = Vector2(0.5, 0.5)
		_halo_texture.fill_to = Vector2(1.0, 0.5)
		_halo_texture.width = 256
		_halo_texture.height = 256
	return _halo_texture
