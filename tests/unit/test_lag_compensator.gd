extends Node

# Offline test for LagCompensator. Run as a scene so the project autoloads exist:
#   Godot_console.exe --headless --path . res://tests/unit/test_lag_compensator.tscn

var failures : int = 0


func check(condition : bool, what : String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		print("  FAIL " + what)
		failures += 1


func _ready() -> void:
	var comp : LagCompensator = LagCompensator.new()
	var target : Node2D = Node2D.new()
	var shooter : Node2D = Node2D.new()
	add_child(comp)
	add_child(target)
	add_child(shooter)
	comp.track(target, &"position", 32.0)
	comp.track(shooter, &"position", 32.0)

	# the target walks right 10 px per tick, from x=100 at tick 10 to x=200 at tick 20
	for tick in range(10, 21):
		target.position = Vector2(100 + (tick - 10) * 10, 0)
		shooter.position = Vector2(500, 0)
		comp.record(tick)

	print("history lookups")
	check(comp.get_position_at(target, 10) == Vector2(100, 0), "exact tick returns the recorded position")
	check(comp.get_position_at(target, 15) == Vector2(150, 0), "middle tick returns the recorded position")
	check(comp.get_position_at(target, 5) == Vector2(100, 0), "tick older than history uses the oldest value")
	check(comp.get_position_at(target, 99) == Vector2(200, 0), "tick newer than history uses the current value")

	print("ray against circles")
	check(is_equal_approx(LagCompensator.ray_circle_distance(Vector2.ZERO, Vector2.RIGHT, Vector2(100, 0), 32.0), 68.0), "straight hit enters at distance minus radius")
	check(LagCompensator.ray_circle_distance(Vector2.ZERO, Vector2.RIGHT, Vector2(100, 40), 32.0) < 0.0, "ray passing outside the radius misses")
	check(LagCompensator.ray_circle_distance(Vector2.ZERO, Vector2.LEFT, Vector2(100, 0), 32.0) < 0.0, "circle behind the ray misses")
	check(LagCompensator.ray_circle_distance(Vector2(100, 0), Vector2.RIGHT, Vector2(100, 0), 32.0) == 0.0, "ray starting inside the circle hits at 0")
	check(LagCompensator.ray_circle_distance(Vector2.ZERO, Vector2.ZERO, Vector2(100, 0), 32.0) < 0.0, "zero direction misses")

	print("sweeping circles")
	check(is_equal_approx(LagCompensator.segment_circle_fraction(Vector2.ZERO, Vector2(100, 0), 8.0, Vector2(100, 0), 32.0), 0.6), "sweep touches at distance minus both radii")
	check(LagCompensator.segment_circle_fraction(Vector2.ZERO, Vector2(30, 0), 8.0, Vector2(100, 0), 32.0) < 0.0, "a move that stops short misses")
	check(LagCompensator.segment_circle_fraction(Vector2.ZERO, Vector2(100, 0), 8.0, Vector2(100, 45), 32.0) < 0.0, "passing outside both radii misses")
	check(LagCompensator.segment_circle_fraction(Vector2(100, 0), Vector2(200, 0), 8.0, Vector2(100, 0), 32.0) == 0.0, "a move starting inside hits at 0")
	check(LagCompensator.segment_circle_fraction(Vector2.ZERO, Vector2(-100, 0), 8.0, Vector2(100, 0), 32.0) < 0.0, "moving away misses")
	check(LagCompensator.segment_circle_fraction(Vector2.ZERO, Vector2.ZERO, 8.0, Vector2(100, 0), 32.0) < 0.0, "no movement far away misses")
	var swept : Dictionary = comp.sweep(Vector2.ZERO, Vector2(200, 0), 8.0, 20, shooter)
	check(swept.get("node") == target and is_equal_approx(swept["position"].x, 160.0), "sweep finds the tracked target and reports where it touched (target at x=200)")
	check(comp.sweep(Vector2.ZERO, Vector2(200, 0), 8.0, 20, shooter, func(n : Node) -> bool: return false).is_empty(), "a filter that refuses everything gives no hit")

	print("lag compensated raycast (shooter at x=500 firing left along the row, target now at x=200)")
	var now_hit : Dictionary = comp.raycast(Vector2(500, 0), Vector2.LEFT, 1000.0, 20, shooter)
	check(now_hit.get("node") == target, "shot at the current tick hits the target")
	var rewound : Dictionary = comp.raycast(Vector2(500, 60), Vector2.LEFT, 1000.0, 20, shooter)
	check(rewound.is_empty(), "aim row 60px off misses the target at its current position")
	# the target was at (150, 0) on tick 15: a ray along y=0 that stops short of x=200 only reaches it when rewound
	var short_now : Dictionary = comp.raycast(Vector2(300, 0), Vector2.LEFT, 130.0, 20, shooter)
	var short_rewound : Dictionary = comp.raycast(Vector2(300, 0), Vector2.LEFT, 130.0, 15, shooter)
	check(short_now.get("node") == target, "short ray reaches the target at its current position (x=200, entry at 68)")
	check(short_rewound.get("node") == target, "short ray also reaches it rewound to x=150 (entry at 118)")
	var far_rewound : Dictionary = comp.raycast(Vector2(300, 0), Vector2.LEFT, 100.0, 15, shooter)
	check(far_rewound.is_empty(), "ray too short for the rewound position misses")
	check(now_hit.get("node") != shooter, "the excluded shooter, standing at the ray origin, is not hit")

	print("moving target seen at an old tick")
	# shooter aims where the target was on tick 12 (x=120) with a ray that ends before reaching x=200
	var seen : Dictionary = comp.raycast(Vector2(220, 0), Vector2.LEFT, 80.0, 12, shooter)
	check(seen.get("node") == target, "shot lands on the old position when rewound to tick 12")
	var late : Dictionary = comp.raycast(Vector2(220, 0), Vector2.LEFT, 80.0, 20, shooter)
	check(late.get("node") == target and is_equal_approx(late["distance"], 0.0), "at tick 20 the same ray starts inside the target (x=200), distance 0")

	print("clamping and trimming")
	comp.max_rewind_ticks = 12
	check(comp.clamp_lag(-3) == 0, "negative lag clamps to 0")
	check(comp.clamp_lag(5) == 5, "lag inside the limit is kept")
	check(comp.clamp_lag(500) == 12, "lag beyond the limit is capped")
	comp.trim(16)
	check(comp.get_position_at(target, 12) == Vector2(160, 0), "trimmed ticks fall back to the oldest remaining value")

	print("untracking")
	target.free()
	check(comp.raycast(Vector2(500, 0), Vector2.LEFT, 1000.0, 20, shooter).is_empty(), "a freed target is no longer tracked")

	print("")
	print("RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)
