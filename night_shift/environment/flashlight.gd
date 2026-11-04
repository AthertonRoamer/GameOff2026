class_name Flashlight
extends Node2D

##The flashlight every player carries: a banded cone of warm white light, 11 m long and 56 degrees wide, that stops at walls and
##closed doors. Add it as a child of a player and rotate it to the aim direction (rotation = aim.angle()), or call aim_at().
##A small halo around the carrier keeps the player's own feet visible. Nothing here knows about the player scene.

const ART_DIR : String = "res://night_shift/environment/art/"

@export var on : bool = true : set = set_on
@export var range_m : float = 11.6 #the cone texture is 512 px long, so this is 512 px at 44 px per metre
@export var cone_energy : float = 1.3
@export var halo_radius_m : float = 1.8

var _cone : PointLight2D
var _halo : PointLight2D


func _ready() -> void:
	_cone = PointLight2D.new()
	_cone.texture = load(ART_DIR + "light_cone.png")
	_cone.offset = Vector2(256.0, 0.0) #the texture's left edge is the light's origin
	_cone.texture_scale = range_m * 44.0 / 512.0
	_cone.color = Color("#fff3c4")
	_cone.energy = cone_energy
	_cone.shadow_enabled = true
	_cone.shadow_filter = Light2D.SHADOW_FILTER_NONE
	add_child(_cone)
	_halo = PointLight2D.new()
	_halo.texture = load(ART_DIR + "light_radial.png")
	_halo.texture_scale = halo_radius_m * 44.0 / 128.0
	_halo.color = Color("#fff3c4")
	_halo.energy = 0.5
	_halo.shadow_enabled = true
	_halo.shadow_filter = Light2D.SHADOW_FILTER_NONE
	add_child(_halo)
	set_on(on)


func aim_at(world_point : Vector2) -> void:
	rotation = (world_point - global_position).angle()


func set_on(value : bool) -> void:
	on = value
	if _cone != null:
		_cone.enabled = value
		_halo.enabled = value
