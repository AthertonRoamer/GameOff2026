class_name NightVision
extends CanvasLayer

##The night vision helmet, for the local player. While they carry one (NightVisionItem, in any slot), N switches it on and off. On, the screen turns green and
##brighter, and anyone in their view is seen in the dark as if a light were on them (PlayerSight.night_vision). A bright light on their eyes (a lit room, another
##player's flashlight beam: PlayerSight.bright_light_on) whites the screen out and the helmet sees nothing until blind_seconds after the light has gone.
##Only this peer's picture changes: nobody else knows it is on.

const ACTION : StringName = &"item_night_vision"
const GREEN : Color = Color(0.05, 0.24, 0.07) ## added over the picture while it works
const GLARE : Color = Color(0.78, 0.92, 0.78) ## added while it is blinded

@export_range(0.0, 5.0, 0.1, "suffix:s") var blind_seconds : float = 1.2

var gadgets : GadgetSystem
var on : bool = false #switched on (it only works while carried)
var blinded_for : float = 0.0 #seconds of glare left
var _tint : ColorRect
var _label : Label
var _glare : float = 0.0 #how strong the glare is drawn now, 0 to 1


func _ready() -> void:
	layer = 3 #over the world and the drawn lights, under the HUD's own layers only by order of adding (it adds no input)
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add : CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_tint.material = add
	_tint.visible = false
	add_child(_tint)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_label.position = Vector2(16.0, -150.0)
	_label.add_theme_font_size_override("font_size", 14)
	_label.visible = false
	add_child(_label)


## Carried by the local player (who is alive).
func is_carried() -> bool:
	return gadgets != null and GadgetSystem.carries(gadgets.me(), NightVisionItem)


## On, carried and not blinded: it shows the dark.
func is_working() -> bool:
	return on and is_carried() and blinded_for <= 0.0


func toggle() -> void:
	if is_carried():
		on = not on


func _unhandled_input(event : InputEvent) -> void:
	if not InputMap.has_action(ACTION) or not event.is_action_pressed(ACTION) or event.is_echo():
		return
	var me : Player = gadgets.me() if gadgets != null else null
	if me == null or me.input.typing:
		return
	toggle()


func _process(delta : float) -> void:
	var carried : bool = is_carried()
	if not carried:
		on = false
	var me : Player = gadgets.me() if gadgets != null else null
	if on and me != null and gadgets.sight != null and gadgets.sight.bright_light_on(me):
		blinded_for = blind_seconds
	else:
		blinded_for = maxf(blinded_for - delta, 0.0)
	var working : bool = is_working()
	if gadgets != null and gadgets.sight != null:
		gadgets.sight.night_vision = working
	_glare = move_toward(_glare, 1.0 if on and blinded_for > 0.0 else 0.0, delta * 6.0)
	_tint.visible = on
	_tint.color = GREEN.lerp(GLARE, _glare)
	_label.visible = carried
	_label.text = "NIGHT VISION  %s   (N)" % ("BLINDED" if on and blinded_for > 0.0 else "ON" if on else "OFF")
	_label.modulate = Color("#7dff8a") if working else Color(1, 1, 1, 0.75)
