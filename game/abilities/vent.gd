class_name Vent
extends Node2D

##A vent of the facility: an interactable (see PlayerInteractor) only a ventrat can use. In reach, E opens the vent map to pick another vent to come out of
##(AbilityControl decides and moves them). Made by AbilityControl.build() for every marker under the map's Vents node: put a vent in the map by adding a Marker2D there.

@export var reach_m : float = 1.2

const ART : Texture2D = preload("res://game/abilities/art/vent.png") #drawn by tools/art/make_vent.py

const ART_Z : int = -12 #(Furniture.FLAT_Z)

var index : int = -1 #the place in AbilityControl.vents, the same on every peer
var control : AbilityControl


func _ready() -> void:
	add_to_group(PlayerInteractor.GROUP)
	var art : Sprite2D = Sprite2D.new()
	art.name = "Art"
	art.texture = ART
	art.scale = Vector2.ONE * FacilityTileSet.ART_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.position = Vector2.ONE * FacilityTileSet.TILE #(the middle of the 2 x 2 cell grille)
	art.z_as_relative = false
	art.z_index = ART_Z #flat on the floor, like flat furniture: under players and fallen bodies
	art.light_mask = LightLayers.receiver_layer(LightLayers.Tier.FLAT)
	add_child(art)


func can_interact(player : Player) -> bool:
	return player.role != null and player.role.can_vent and player.is_alive() and control != null and control.vents.size() > 1


## The middle of its grille (the node stands on the grille's top left corner, as the map's marker does).
func centre() -> Vector2:
	return global_position + Vector2.ONE * FacilityTileSet.TILE


func is_in_reach(world_position : Vector2, slack : float = 1.0) -> bool:
	return global_position.distance_to(world_position) <= reach_m * Acoustics.PX_PER_METRE * slack


func get_prompt() -> String:
	return "E   climb into the vent"


func interact(player : Player) -> Control:
	control.vent_screen.open(player, self)
	return control.vent_screen
