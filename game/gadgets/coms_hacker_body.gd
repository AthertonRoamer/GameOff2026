class_name ComsHackerBody
extends StaticBody2D

##The part of a coms hacker a shot hits (see ComsHackerVisual). The game deals a shot's damage with take_damage on the lobby; any hit breaks it.

var visual : ComsHackerVisual


func take_damage(_damage : float, _direction : Vector2 = Vector2.ZERO) -> void:
	if is_instance_valid(visual):
		visual.struck()
