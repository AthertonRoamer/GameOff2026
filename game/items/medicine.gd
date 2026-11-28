class_name Medicine
extends Item

##A dose of medicine. While it is chosen in the inventory and the player is hurt, the HUD says "Hold E to heal"; holding E for hold_seconds fills a progress bar (see ItemUse),
##and then the medicine is gone from the inventory and the player gets back a share of their full health (heal_fraction), never more than full. At full health it can't be
##used. The lobby heals them (the health is what it syncs) and checks again that they are hurt. Medics make one now and then (Role.medicine_seconds).

@export_range(0.05, 1.0, 0.05) var heal_fraction : float = 0.5 ## of the player's full health


func _init() -> void:
	click_use = ClickUse.CONSUME


func hold_prompt() -> String:
	return "Hold E to heal"


func can_consume(user : Player) -> bool:
	return user.is_alive() and user.health < user.starting_health


func consume_on(user : Player) -> void:
	user.health = minf(user.starting_health, user.health + user.starting_health * heal_fraction)
