class_name ComsHackerVisual
extends Node2D

##A coms hacker on the floor: a small box with an aerial and, while it listens, a blinking red light. It has a small body a shot can hit (physics layer 7,
##FacilityTileSet.GADGET_LAYER, which only instant shots test: it stops nobody walking and no line of sight), in the shootable group: the shot breaks it.

const RADIUS : float = 7.0

var pickup : Pickup
var listening : bool = false
var body : ComsHackerBody


func _ready() -> void:
	body = ComsHackerBody.new()
	body.name = "Body"
	body.collision_layer = FacilityTileSet.GADGET_LAYER
	body.collision_mask = 0
	body.add_to_group(HitscanManager.SHOOTABLE_GROUP)
	body.visual = self
	var shape : CollisionShape2D = CollisionShape2D.new()
	var circle : CircleShape2D = CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	body.add_child(shape)
	add_child(body)


func _process(_delta : float) -> void:
	if listening:
		queue_redraw()


## Lobby: a shot struck it.
func struck() -> void:
	var gadgets : Node = get_tree().get_first_node_in_group(GadgetSystem.GROUP)
	if gadgets is GadgetSystem and is_instance_valid(pickup):
		(gadgets as GadgetSystem).break_hacker(pickup)


func _draw() -> void:
	draw_rect(Rect2(-8.0, -6.0, 16.0, 12.0), Color("#2a3340"))
	draw_rect(Rect2(-8.0, -6.0, 16.0, 12.0), Color("#5b6b7d"), false, 1.0)
	draw_line(Vector2(4.0, -6.0), Vector2(8.0, -15.0), Color("#8a98a8"), 1.5)
	for i in 3: #grille
		draw_line(Vector2(-5.0, -2.5 + i * 2.5), Vector2(1.0, -2.5 + i * 2.5), Color("#4a5866"), 1.0)
	if listening and (Time.get_ticks_msec() / 450) % 2 == 0:
		draw_circle(Vector2(5.0, 2.0), 2.2, Color("#ff3b3b"))
		draw_circle(Vector2(5.0, 2.0), 4.5, Color(1.0, 0.23, 0.23, 0.25))
