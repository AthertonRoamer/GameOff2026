class_name LightLayers
extends RefCounted

##How tall things are, for light. A shadow falls over something only when what throws it is taller: a chair's shadow lies on the floor but not on the table beside it, a
##rack's shadow lies on the table, a wall's on everything. Godot's 2D lights have no height, so heights are done with its light layers:
##
##  Pictures (CanvasItem.light_mask: which lights light it, and take shadows on it):
##    FLOOR  the floor, the walls and doors, players, blood, and flat pieces (a pallet): everything that is not furniture with a height
##    LOW    furniture below 0.6 m   (chairs, bins, totes, boxes)
##    MID    furniture below 1.5 m   (tables, desks, counters, crates, barrels, cabinets)
##    TALL   furniture 1.5 m and up  (racks, lockers, fridges, vending machines). Its top takes only TALL_TOP_LIGHT of a light, it being out of the beam's reach
##  Occluders (LightOccluder2D.occluder_light_mask: which lights it throws a shadow in):
##    FLOOR  walls and doors (the default layer, so every wall is a wall to every light)
##    CAST_LOW, CAST_MID, CAST_TALL   furniture of that height
##
##The flashlight is four lights, one for each layer of pictures (Light2D.range_item_cull_mask): the one that lights the floor takes the shadows of everything, the one that
##lights low furniture those of mid and tall furniture and walls, and so on up. Each picture is lit by one of them only, so lighting costs no more than with one light; only the
##shadows are worked out four times (each time of fewer things). A room's ceiling lamp lights every layer and takes only the walls' shadows (make_ceiling). Every other light (the glow round a player, a muzzle flash, a console's screen) has no height: it lights
##every layer of pictures and takes every shadow (make_heightless).
##
##Godot applies a light's shadows (shadow_item_cull_mask) to a picture only if the picture's layer is in that mask too, and takes them from the occluders whose layer is in it.
##So a light's mask has its own pictures' layer (to have shadows at all), the walls' layer, and the CAST layers of what is taller; the CAST layers are separate from the
##picture layers so that a piece's own layer in the mask does not make pieces of its height shade each other.

const FLOOR : int = 1 << 0
const LOW : int = 1 << 1
const MID : int = 1 << 2
const TALL : int = 1 << 3
const CAST_LOW : int = 1 << 4
const CAST_MID : int = 1 << 5
const CAST_TALL : int = 1 << 6
const ALL_PICTURES : int = FLOOR | LOW | MID | TALL
const ALL : int = ALL_PICTURES | CAST_LOW | CAST_MID | CAST_TALL

const LOW_BELOW : float = 0.6 #metres
const MID_BELOW : float = 1.5
const TALL_TOP_LIGHT : float = 0.35 #how much of a light the top of a TALL piece takes

enum Tier { FLAT, LOW, MID, TALL } ## FLAT: lies on the floor, no height (is on the FLOOR layer and throws no shadow)


## The tier a piece of this height is in (a piece with no footprint is flat whatever its height).
static func tier_of(height : float, solid : bool = true) -> Tier:
	if not solid or height <= 0.05:
		return Tier.FLAT
	if height < LOW_BELOW:
		return Tier.LOW
	if height < MID_BELOW:
		return Tier.MID
	return Tier.TALL


## The layer pictures of this tier are on (CanvasItem.light_mask), which the light for this tier lights.
static func receiver_layer(tier : int) -> int:
	return [FLOOR, LOW, MID, TALL][tier]


## The layer an occluder of this tier is on (occluder_light_mask). A flat piece throws no shadow.
static func caster_layer(tier : int) -> int:
	return [0, CAST_LOW, CAST_MID, CAST_TALL][tier]


## What the light for this tier's pictures has as shadow_item_cull_mask: those pictures' layer, the walls, and everything taller than the tier.
static func shadow_layers(tier : int) -> int:
	var mask : int = receiver_layer(tier) | FLOOR
	for higher in range(tier + 1, Tier.TALL + 1):
		mask |= caster_layer(higher)
	return mask


## Turns a flashlight's cone light into one cone for each tier: `cone` becomes the one for the floor, and one more is made for each of the other tiers (same place, same
## look, as siblings after it). Returns all four, floor first.
static func add_height_cones(cone : PointLight2D) -> Array[PointLight2D]:
	var cones : Array[PointLight2D] = [cone]
	cone.range_item_cull_mask = receiver_layer(Tier.FLAT)
	cone.shadow_item_cull_mask = shadow_layers(Tier.FLAT)
	var parent : Node = cone.get_parent()
	for tier in range(Tier.LOW, Tier.TALL + 1):
		var extra : PointLight2D = cone.duplicate() as PointLight2D
		extra.name = "%s%s" % [cone.name, Tier.keys()[tier].capitalize()]
		extra.range_item_cull_mask = receiver_layer(tier)
		extra.shadow_item_cull_mask = shadow_layers(tier)
		parent.add_child(extra)
		cones.append(extra)
	return cones


## A ceiling light (a room's lamp): it is above everything, so it lights every layer of pictures and takes the shadows of walls and doors only (FLOOR), never of
## furniture, generators or consoles (their occluders are on the CAST layers, which are left out).
static func make_ceiling(light : Light2D) -> void:
	light.range_item_cull_mask = ALL_PICTURES
	light.shadow_item_cull_mask = ALL_PICTURES #(each picture layer, so walls shade pictures of every height; occluders are on FLOOR for walls only)


## A light with no height of its own: lights every layer of pictures and takes every shadow.
static func make_heightless(light : Light2D) -> void:
	light.range_item_cull_mask = ALL_PICTURES
	light.shadow_item_cull_mask = ALL
