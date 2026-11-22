class_name Gun
extends Item

##Fires a rollback-safe projectile via the user's ProjectileManager, aimed at the user's recorded aim input.

@export var damage : float = 10.0
@export var bullet_speed : float = 600.0
@export var bullet_color : Color = Color.WHITE
@export var hitscan : bool = false ## an instant shot (HitscanManager) instead of a bullet that flies (ProjectileManager)
@export var range_px : float = 700.0 ## how far an instant shot reaches, in world pixels


func _init() -> void:
	drawable = true


func use(user : Player, tick : int) -> void:
	if (user.hitscan_manager if hitscan else user.projectile_manager) == null:
		return
	var direction : Vector2 = (user.input.aim - user.global_position).normalized()
	if direction.is_zero_approx():
		return
	if user.is_barrel_blocked(direction): #a wall or closed door right in front: the gun is lowered, nothing is fired through it
		return
	var origin : Vector2 = user.global_position + direction * user.muzzle_distance #the end of the barrel
	if hitscan: #false for a repeat of a shot, like spawn() below
		if user.hitscan_manager.fire(user, user.get_multiplayer_authority(), origin, direction, tick, damage, range_px, user.input.view_lag, bullet_color):
			user.shot_fired.emit()
		return
	#spawn() is false for a repeat of a shot (a resimulated tick), so the shot animation plays once per shot
	if user.projectile_manager.spawn(user, user.get_multiplayer_authority(), origin, direction, tick, damage, bullet_speed, bullet_color):
		user.shot_fired.emit()
