class_name RegionNamesLayer
extends MapLayer

##The zone names (and, for who may see it, their power), drawn for a RegionsLayer near the top of the map so no icon runs through them. Set `source`.

@export var source : RegionsLayer


func _ready() -> void:
	if source != null:
		source.names_on_top = true


func _draw() -> void:
	if source != null and source.view != null:
		source.draw_names(self)
