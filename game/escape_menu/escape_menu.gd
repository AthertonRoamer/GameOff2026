extends CanvasLayer

##Opens/closes on the ui_cancel action (Escape by default) and lets the player quit the game.

@onready var panel : Control = $Panel


func _ready() -> void:
	panel.visible = false


func _unhandled_input(event : InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()


func _on_quit_button_pressed() -> void:
	var game : Node = get_parent()
	if game.get_parent().lobby.has_authority:
		game.get_parent().lobby.trigger_request_end_game()
	else:
		Main.mode.leave_lobby()
