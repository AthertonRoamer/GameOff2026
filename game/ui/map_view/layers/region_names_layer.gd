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


##A zone's name tag: what the zone is and, for who may see it, its power.
func icon_label(world : Vector2) -> String:
	if source == null or source.view == null or facility() == null:
		return ""
	var tags : Dictionary = source.name_tags(self)
	for id : String in tags:
		if (tags[id] as Rect2).has_point(world):
			var zone : String = String(facility().regions[id]["name"])
			if source.show_power and source.grid != null:
				return "%s power zone: %d of %d pts/s free (its generators power its rooms' doors, lights, cameras and turrets)" % [zone, floori(source.grid.available(id)), roundi(source.grid.capacity(id))]
			return "%s power zone: its rooms share its generators" % zone
	return ""
