class_name Flashlight
extends Node2D

##A flashlight: a soft cone of warm light, 11 m long and 56 degrees wide, that walls and closed gates stop, plus a small glow around the carrier so
##the character stays visible. It lives under the player's torso (see player_skin.tscn), which already turns to face the aim, so the beam comes out of
##the front of the torso with nothing else to steer. Only its on/off state is a decision; set `on`.
##The beam points along the node's local +X, so the node is turned -90 degrees under the torso, whose "forward" is up in the sprite sheet.
##
##The lights are real nodes, so everything about how it looks is set in the editor on the two PointLight2D children: Cone and Halo (colour,
##energy, shadows, size). This script only switches them on and off. Two numbers are worked out for the scene as it is built, not by the script:
##  Cone  texture_scale = range in metres * 44 px per metre / CONE_WIDTH / the Skin's scale (0.25)   -> 11 m gives 3.78125
##        offset        = CONE_WIDTH / 2 * texture_scale (the cone texture's left edge has to sit on the light's origin; Light2D's offset is
##                        not scaled with the texture)                                              -> (968, 0)
##  Halo  texture_scale = radius in metres * 44 * 2 / texture width / the Skin's scale             -> 1.6 m gives 2.2
##Change the cone's size or shape (CONE_HALF_ANGLE, build_cone_image) and run bake_cone() to rewrite flashlight_cone.png.

@export var on : bool = false : set = set_on

const CONE_WIDTH : int = 512
const CONE_HEIGHT : int = 256
const CONE_HALF_ANGLE : float = deg_to_rad(28.0)

const CONE_PATH : String = "res://game/player/flashlight/flashlight_cone.png"

static var _cone_texture : Texture2D

@onready var cone : PointLight2D = $Cone
@onready var halo : PointLight2D = $Halo


func _ready() -> void:
	set_on(on)


func set_on(value : bool) -> void:
	on = value
	if is_node_ready():
		cone.enabled = value
		halo.enabled = value


func toggle() -> void:
	set_on(not on)

##The beam's light texture, loaded from CONE_PATH (baked by bake_cone(); building it here costs about 45 ms, too much while a game loads).
##If the file is missing it is built in code instead.
static func _get_cone_texture() -> Texture2D:
	if _cone_texture == null:
		_cone_texture = load(CONE_PATH) if ResourceLoader.exists(CONE_PATH) else ImageTexture.create_from_image(build_cone_image())
	return _cone_texture


##Saves the cone to CONE_PATH. Run it again after changing build_cone_image() or the cone constants, for example from a scratch scene:
##    Flashlight.bake_cone()
static func bake_cone() -> Error:
	return build_cone_image().save_png(ProjectSettings.globalize_path(CONE_PATH))


##A cone pointing right from the middle of the left edge: brightest at the source, fading with distance, with soft edges.
static func build_cone_image() -> Image:
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
	return image
