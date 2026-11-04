class_name Gun
extends Item

##Fires a rollback-safe projectile via the user's ProjectileManager, aimed at the user's recorded aim input.

@export var damage : float = 10.0
@export var bullet_speed : float = 600.0
@export var bullet_color : Color = Color.WHITE


func use(user : Player, tick : int) -> void:
	if user.projectile_manager == null:
		return
	var direction : Vector2 = (user.input.aim - user.global_position).normalized()
	if direction.is_zero_approx():
		return
	var origin : Vector2 = user.global_position + direction * user.muzzle_distance #the end of the barrel
	#spawn() is false for a repeat of a shot (a resimulated tick), so the shot animation plays once per shot
	if user.projectile_manager.spawn(user, user.get_multiplayer_authority(), origin, direction, tick, damage, bullet_speed, bullet_color):
		user.shot_fired.emit()
