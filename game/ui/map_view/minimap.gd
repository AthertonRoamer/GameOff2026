class_name Minimap
extends FacilityMapView

##The little map in the corner of the HUD: the rooms round the player, always centred on them. A FacilityMapView that nobody can click, scroll or zoom (see its layers
## in the scene: the rooms and the player's dot). Set `facility` and `tracked`.

@export var background : Color = Color(Palette.SHADOW, 0.72)

var tracked : Node2D

@onready var player_dot : PlayerDotLayer = $Player


func _ready() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_IGNORE #(the view is made to take the mouse)


## Follows this node (the local player) and marks it.
func track(node : Node2D) -> void:
	tracked = node
	player_dot.tracked = node


func _process(delta : float) -> void:
	if is_instance_valid(tracked):
		center_on(tracked.global_position)
	super(delta)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)
