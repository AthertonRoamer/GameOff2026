class_name NetInput
extends Node

##Base class for the node that holds a player's input in a rollback game.
##Give the player scene a child of this type (named "Input" by default, see RollbackPlayerSpawner), list its properties as
##input_properties on the player's RollbackSynchronizer, and override _gather() to fill them from the real input devices.
##_gather() runs once per frame, before the network tick loop, and only on the peer that owns this node.


func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_before_tick_loop)


func _exit_tree() -> void:
	if NetworkTime.before_tick_loop.is_connected(_before_tick_loop):
		NetworkTime.before_tick_loop.disconnect(_before_tick_loop)


func _before_tick_loop() -> void:
	if is_multiplayer_authority():
		_gather()


func _gather() -> void:
	pass
