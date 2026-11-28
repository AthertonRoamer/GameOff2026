@tool
class_name TurretSettings
extends Resource

##Every number of a turret, in one place (turret_settings.tres, shared by every turret). To tune one turret on its own, give it its own copy: in its inspector,
##right-click `settings` and Make Unique. What it costs to keep on is PowerSettings.turret_cost. See Turret and TurretSystem.

@export_group("Seeing")
@export_range(10.0, 360.0, 1.0, "suffix:°") var fov_degrees : float = 110.0 ## the cone it sees and turns in, centred on the turret's facing. Outside it (behind it) it sees nothing
@export_range(50.0, 3000.0, 10.0, "suffix:px") var range_px : float = 640.0 ## how far it sees and shoots (44 px a metre)
@export_range(0.0, 10.0, 0.05, "suffix:s") var lock_on_seconds : float = 0.8 ## aimed at an intruder this long (its laser showing) before the first shot: the warning
@export_range(1.0, 5.0, 0.05, "suffix:×") var silent_lock_multiplier : float = 1.5 ## the lock-on takes this much longer on an intruder whose role walks silently (Role.silent_walk)
@export_range(0.0, 10.0, 0.05, "suffix:s") var lose_target_seconds : float = 1.0 ## how long it keeps aiming where a target went out of sight before it gives up and turns back
@export_range(0.0, 30.0, 0.1, "suffix:s") var warmup_seconds : float = 1.5 ## after being switched on, how long before it starts watching (silent)

@export_group("Turning")
@export_range(5.0, 1080.0, 5.0, "suffix:°/s") var turn_speed_degrees : float = 100.0 ## how fast it turns: a player crossing it quickly can outrun it
@export_range(0.5, 45.0, 0.5, "suffix:°") var aim_tolerance_degrees : float = 4.0 ## how close to the target it has to point to lock on and to fire

@export_group("Firing")
@export_range(0.0, 200.0, 0.5) var damage : float = 5.0 ## per shot (players start with about 50 health; a pistol does 10)
@export_range(0.1, 30.0, 0.1, "suffix:shots/s") var shots_per_second : float = 3.5 ## while a burst lasts
@export_range(1, 100) var burst_shots : int = 6 ## shots in a burst, before it pauses
@export_range(0.0, 10.0, 0.05, "suffix:s") var burst_pause_seconds : float = 0.6 ## the gap between bursts: a moment to move between cover
@export_range(0.0, 45.0, 0.1, "suffix:°") var spread_start_degrees : float = 1.0 ## how far a burst's first shot can stray, either side
@export_range(0.0, 45.0, 0.1, "suffix:°") var spread_per_shot_degrees : float = 1.2 ## how much more each shot in a burst can stray than the one before
@export_range(0.0, 45.0, 0.1, "suffix:°") var spread_max_degrees : float = 8.0 ## the most a shot can stray
@export var friendly_fire : bool = false ## its shots hit a guard standing in the way. Off: they pass through guards (it never aims at one either way)
@export var bullet_color : Color = Color("#ff6a5c")

@export_group("Health")
@export_range(1.0, 2000.0, 1.0) var max_health : float = 120.0 ## damage it takes to go down (a pistol does 10 a shot)
@export_range(0.1, 60.0, 0.1, "suffix:s") var repair_seconds : float = 6.0 ## how long a guard holds E to repair a shot-down turret (it comes back at full health, switched off)
@export_range(0.3, 5.0, 0.1, "suffix:m") var reach_m : float = 1.3 ## how close a player has to be to repair it or (a technician) switch it, from its middle

@export_group("Network")
@export_range(1.0, 60.0, 1.0, "suffix:Hz") var sync_hz : float = 15.0 ## how often the lobby tells the other peers where a moving turret points


func fov_radians() -> float:
	return deg_to_rad(fov_degrees)


func turn_speed_radians() -> float:
	return deg_to_rad(turn_speed_degrees)


func aim_tolerance_radians() -> float:
	return deg_to_rad(aim_tolerance_degrees)


func shot_interval() -> float:
	return 1.0 / maxf(shots_per_second, 0.01)


##How far the n-th shot of a burst (0 first) can stray, in radians, either side.
func spread_radians(shot_in_burst : int) -> float:
	return deg_to_rad(minf(spread_max_degrees, spread_start_degrees + spread_per_shot_degrees * shot_in_burst))
