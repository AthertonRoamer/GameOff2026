class_name Gun
extends Item

##Fires a rollback-safe projectile via the user's ProjectileManager, aimed at the user's recorded aim input.

@export var damage : float = 10.0
@export var bullet_speed : float = 600.0
@export var bullet_color : Color = Color.WHITE
@export var hitscan : bool = false ## an instant shot (HitscanManager) instead of a bullet that flies (ProjectileManager)
@export var range_px : float = 700.0 ## how far an instant shot reaches, in world pixels
@export var shot_sound : SoundDef ## the bang, played on every peer for every shot (see game/audio)
@export var reload_sound : SoundDef ## played when a reload starts, on every peer
@export var magazine_size : int = 12 ## rounds in a full magazine; a reload fills it from the supply (see Inventory)
@export var reload_seconds : float = 1.6
@export var pellets : int = 1 ## an instant shot sends this many rays, each doing `damage` (a shotgun)
@export_range(0.0, 45.0, 0.5, "suffix:°") var spread_degrees : float = 0.0 ## half the width of the cone the pellets are spread over


func reload_ticks() -> int:
	return maxi(NetworkTime.seconds_to_ticks(reload_seconds), 1)


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
		if user.hitscan_manager.fire(user, user.input.get_multiplayer_authority(), origin, direction, tick, damage, range_px, user.input.view_lag, bullet_color, pellets, spread_degrees):
			user.shot_fired.emit()
		return
	#spawn() is false for a repeat of a shot (a resimulated tick), so the shot animation plays once per shot
	if user.projectile_manager.spawn(user, user.get_multiplayer_authority(), origin, direction, tick, damage, bullet_speed, bullet_color):
		user.shot_fired.emit()
