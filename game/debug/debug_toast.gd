class_name DebugToast
extends CanvasLayer

##A line of text in the corner of the screen that fades by itself, for debug keys to say what they just changed:
##    DebugToast.say(self, "Rings: on")
##One shared node, made the first time it is used (under the root, so it outlives any scene change), so debug keys do not each build their own label.
##It is only ever created by a debug key, so with the keys gone (see DebugRemover) it never exists. Delete this file together with them.

const HOLD_TIME : float = 2.5
const FADE_TIME : float = 0.6
const POSITION : Vector2 = Vector2(16.0, 88.0) #under the controls hint

var _label : Label = Label.new()
var _tween : Tween


static func say(from : Node, text : String) -> void:
	var root : Window = from.get_tree().root
	var toast : DebugToast = root.get_node_or_null("DebugToast") as DebugToast
	if toast == null:
		toast = DebugToast.new()
		toast.name = "DebugToast"
		root.add_child.call_deferred(toast) #a key can be pressed while the tree is busy
	toast._show.call_deferred(text)


func _init() -> void:
	layer = 60 #above the HUD, below the pixel art pass


func _ready() -> void:
	_label.position = POSITION
	_label.modulate.a = 0.0
	add_child(_label)


func _show(text : String) -> void:
	_label.text = text
	_label.modulate.a = 1.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_TIME)
