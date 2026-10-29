class_name RollbackDiagnostics
extends CanvasLayer

##Small on-screen readout of netfox timing and rollback cost. Toggle with F3.
##RollbackGameManager adds one automatically on non-lobby peers when Configuration.rollback_diagnostics is true.

var label : Label


func _ready() -> void:
	layer = 100
	label = Label.new()
	label.position = Vector2(8, 8)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)


func _unhandled_key_input(event : InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		label.visible = not label.visible


func _process(_delta : float) -> void:
	if not label.visible:
		return
	var lines : Array[String] = []
	lines.append("tick %d  (%d/s)" % [NetworkTime.tick, NetworkTime.tickrate])
	lines.append("rtt %.0f ms  offset %.1f ms  stretch %.2f" % [NetworkTime.remote_rtt * 1000.0, NetworkTime.clock_offset * 1000.0, NetworkTime.clock_stretch_factor])
	if NetworkPerformance.is_enabled():
		lines.append("rollback ticks/frame %d  nodes/tick %.1f" % [NetworkPerformance.get_rollback_ticks(), NetworkPerformance.get_rollback_nodes_simulated_per_tick()])
		lines.append("rollback loop %.2f ms  tick %.2f ms" % [NetworkPerformance.get_rollback_loop_duration_ms(), NetworkPerformance.get_rollback_tick_duration_ms()])
		lines.append("state props sent %d/%d" % [NetworkPerformance.get_sent_state_props_count(), NetworkPerformance.get_full_state_props_count()])
	label.text = "\n".join(lines)
