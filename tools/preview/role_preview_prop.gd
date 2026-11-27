extends Node2D

## A prop for role_preview.gd: the panel a role works, or the vent it slips into. Plain shapes; they only say what the pose is for.

var kind : String = ""


func _draw() -> void:
	match kind:
		"panel":
			draw_rect(Rect2(-22, -52, 44, 18), Color("#2b343d"))
			draw_rect(Rect2(-18, -49, 36, 9), Color("#3fa7c9"))
			draw_rect(Rect2(-18, -37, 36, 2), Color("#0d1114"))
		"vent":
			draw_rect(Rect2(-20, -34, 40, 28), Color("#2b343d"))
			for i in 5:
				draw_rect(Rect2(-17, -31 + i * 5.5, 34, 2.5), Color("#0d1114"))
