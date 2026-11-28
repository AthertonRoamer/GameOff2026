class_name PortableGeneratorVisual
extends Node2D

##A running portable generator on the floor, drawn in code (smaller than the facility's backup generators): a cabinet, a turning fan and a lamp that pulses with the
##engine, and a little warm light round it. Made by PortableGeneratorItem.on_floor; the Pickup it sits on fades it with the local player's view.

const SIZE : Vector2 = Vector2(30.0, 22.0)

var _time : float = 0.0


func _ready() -> void:
	var light : PointLight2D = PointLight2D.new()
	light.name = "Light"
	var gradient : Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color.BLACK])
	var texture : GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	light.texture = texture
	light.texture_scale = 1.0
	light.color = Palette.BACKUP
	light.energy = 0.45
	add_child(light)


func _process(delta : float) -> void:
	_time += delta
	var light : PointLight2D = get_node_or_null("Light")
	if light != null:
		light.energy = 0.42 + 0.06 * sin(_time * 9.0)
	queue_redraw()


func _draw() -> void:
	var body : Rect2 = Rect2(-SIZE / 2.0, SIZE)
	draw_rect(body.grow(2.0), Color(Palette.VOID, 0.5))
	draw_rect(body, Palette.METAL)
	draw_rect(body, Palette.VOID, false, 1.5)
	draw_rect(Rect2(body.position + Vector2(2.0, -4.0), Vector2(SIZE.x - 4.0, 3.0)), Palette.WALL_TOP) #the handle
	var fan : Vector2 = Vector2(-5.0, 1.0)
	draw_circle(fan, 6.5, Palette.VOID)
	for i in 3:
		var blade : Vector2 = Vector2.from_angle(_time * 14.0 + i * TAU / 3.0)
		draw_line(fan + blade * 1.5, fan + blade * 5.5, Color(0.75, 0.8, 0.88, 0.7), 1.4, true)
	var lamp : Color = Palette.BACKUP.lerp(Palette.FLASH, 0.25 + 0.25 * sin(_time * 9.0))
	draw_circle(Vector2(8.5, -3.0), 3.0, Color(lamp, 0.3))
	draw_circle(Vector2(8.5, -3.0), 1.6, lamp)
	draw_rect(Rect2(Vector2(5.0, 3.0), Vector2(7.0, 4.0)), Palette.ITEM)
