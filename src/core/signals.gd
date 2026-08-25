extends Node
## Global event bus. Autoloaded as `Signals`.
##
## Everything that crosses system boundaries (combat -> UI, world -> camera,
## quality -> renderer) goes through here so no subsystem has to know about
## the node layout of another.

signal player_spawned(player: Node3D)
signal player_health_changed(current: float, maximum: float)
signal player_energy_changed(current: float, maximum: float)
signal player_died()

signal enemy_spawned(enemy: Node3D)
signal enemy_damaged(enemy: Node3D, amount: float, crit: bool, world_pos: Vector3)
signal enemy_died(enemy: Node3D, world_pos: Vector3)

signal combo_changed(count: int, timer: float)
signal wave_changed(index: int, remaining: int)

signal hit_stop_requested(duration: float, time_scale: float)
signal camera_shake_requested(strength: float, duration: float)
signal camera_impulse_requested(direction: Vector3, strength: float)
signal camera_fov_kick_requested(amount: float, duration: float)

signal quality_changed(preset_name: String)
signal photo_mode_toggled(active: bool)
signal toast(text: String, seconds: float)

signal world_build_progress(stage: String, ratio: float)
signal world_build_finished()
