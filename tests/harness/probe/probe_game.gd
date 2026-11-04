extends Node2D

# Minimal game used only by the smoke harness to exercise RollbackGameManager and RollbackPlayerSpawner.

@onready var spawner : RollbackPlayerSpawner = $Spawner

var started_at_tick : int = -1


func _ready() -> void:
	if get_parent() is GameManager:
		spawner.setup(get_parent().lobby)
		spawner.spawn_all()


func start() -> void:
	started_at_tick = NetworkTime.tick


func end() -> void:
	queue_free()


func describe() -> String:
	var info : Array = []
	for id in spawner.players:
		var p : Node = spawner.players[id]
		info.append("%s(body_auth=%d input_auth=%d)" % [p.name, p.get_multiplayer_authority(), p.get_node("Input").get_multiplayer_authority()])
	return "scheduled_tick=%d started_at_tick=%d tickrate=%d players=%s" % [get_parent().start_tick, started_at_tick, NetworkTime.tickrate, str(info)]
