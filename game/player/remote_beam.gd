class_name RemoteBeam
extends Node2D

## One drawn light of another player's flashlight (its beam, or its glow), see PlayerSight. It draws the polygons it is given with remote_beam.gdshader, which does the
## shading (falloff, soft sides, the view's fade) pixel by pixel. Each one has a material of its own, since each has its own origin and direction.

const SHADER : Shader = preload("res://game/player/remote_beam.gdshader")

var polygons : Array[PackedVector2Array] = []
var shader_material : ShaderMaterial


func _init() -> void:
	shader_material = ShaderMaterial.new()
	shader_material.shader = SHADER
	material = shader_material


func _process(_delta : float) -> void:
	queue_redraw()


func _draw() -> void:
	for polygon : PackedVector2Array in polygons:
		if polygon.size() >= 3:
			draw_colored_polygon(polygon, Color.WHITE)
