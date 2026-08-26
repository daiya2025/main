class_name MonsterAgent
extends CharacterBody3D
## Enemy behaviour and animation driver.
##
## Deliberately telegraphed: every attack has a visible wind-up during which the
## creature's veins flare, so a hit is always something the player could have
## dodged. Steering is direct pursuit with whisker-ray avoidance rather than a
## navmesh — the district is open enough that a navmesh would cost more than it
## returns, and whiskers keep the movement looking like an animal picking a line.

signal died(agent: MonsterAgent)

enum State { SPAWN, IDLE, PURSUE, CIRCLE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD }

const ATTACK_RANGE := 3.1
const CIRCLE_RANGE := 7.5
const LOSE_RANGE := 60.0

var kind: Monster.Kind = Monster.Kind.STALKER
var profile: Dictionary = {}
var health: float = 100.0
var max_health: float = 100.0
var target: Node3D = null

var state: State = State.SPAWN
var _state_time: float = 0.0
var _model: Node3D
var _skeleton: Skeleton3D
var _animator: MonsterAnimator
var _flesh_material: ShaderMaterial
var _core_light: OmniLight3D
var _facing: float = 0.0
var _turn_rate: float = 0.0
var _strike_done: bool = false
var _circle_sign: float = 1.0
var _rage: float = 0.0
var _spawn_scale: float = 0.0

func setup(monster_kind: Monster.Kind) -> void:
	kind = monster_kind
	profile = Monster.PROFILES[kind]

func _ready() -> void:
	if profile.is_empty():
		profile = Monster.PROFILES[kind]
	add_to_group("enemy")
	collision_layer = 1 << 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.5

	max_health = float(profile["health"])
	health = max_health

	var scale_factor := float(profile["scale"])
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.55 * scale_factor
	capsule.height = 1.5 * scale_factor
	shape.shape = capsule
	shape.position = Vector3(0, 0.78 * scale_factor, 0)
	add_child(shape)

	_model = Monster.create_node(kind, {"quality": 1.0})
	add_child(_model)
	_skeleton = _model.get_child(0) as Skeleton3D

	_animator = MonsterAnimator.new(_skeleton)
	_animator.stride_scale = scale_factor
	add_child(_animator)

	for child in _skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		if mi.name == "Flesh":
			_flesh_material = (mi.material_override as ShaderMaterial).duplicate()
			mi.material_override = _flesh_material
		elif mi.name == "Core":
			_core_light = OmniLight3D.new()
			_core_light.light_color = Materials.ORANGE_EMISSIVE
			_core_light.light_energy = 4.0
			_core_light.omni_range = 8.0 * scale_factor
			_core_light.light_volumetric_fog_energy = 2.5
			_core_light.position = mi.get_aabb().get_center()
			mi.add_child(_core_light)

	_model.scale = Vector3.ZERO
	Signals.enemy_spawned.emit(self)

func is_alive() -> bool:
	return state != State.DEAD

# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_state_time += delta
	if target == null or not is_instance_valid(target):
		target = Game.alive_player()

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 22.0) * delta
	else:
		velocity.y = maxf(velocity.y, -0.1)

	match state:
		State.SPAWN: _tick_spawn(delta)
		State.IDLE: _tick_idle(delta)
		State.PURSUE: _tick_pursue(delta)
		State.CIRCLE: _tick_circle(delta)
		State.WINDUP: _tick_windup(delta)
		State.STRIKE: _tick_strike(delta)
		State.RECOVER: _tick_recover(delta)
		State.STAGGER: _tick_stagger(delta)
		State.DEAD: _tick_dead(delta)

	move_and_slide()
	_update_animation(delta)

func _change_state(next: State) -> void:
	state = next
	_state_time = 0.0
	_strike_done = false

func _distance_to_target() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return global_position.distance_to(target.global_position)

## Direct pursuit plus two whisker rays; the creature slides along obstacles
## instead of grinding into them.
func _steer(desired: Vector3) -> Vector3:
	if desired.length_squared() < 0.0001:
		return Vector3.ZERO
	var dir := desired.normalized()
	var space := get_world_3d().direct_space_state
	if space == null:
		return dir
	var origin := global_position + Vector3(0, 0.9, 0)
	for angle in [-0.45, 0.45]:
		var whisker := dir.rotated(Vector3.UP, angle)
		var params := PhysicsRayQueryParameters3D.create(origin, origin + whisker * 3.4)
		params.collision_mask = 1
		params.exclude = [get_rid()]
		var hit := space.intersect_ray(params)
		if not hit.is_empty():
			var normal: Vector3 = hit["normal"]
			dir = (dir + Vector3(normal.x, 0, normal.z).normalized() * 0.9).normalized()
	return dir

func _move_towards(dir: Vector3, speed: float, delta: float) -> void:
	var planar := Vector3(velocity.x, 0, velocity.z)
	planar = planar.move_toward(dir * speed, 22.0 * delta)
	velocity.x = planar.x
	velocity.z = planar.z

func _brake(delta: float) -> void:
	var planar := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.x = planar.x
	velocity.z = planar.z

# ------------------------------------------------------------------ states --

func _tick_spawn(delta: float) -> void:
	_spawn_scale = minf(1.0, _spawn_scale + delta * 1.8)
	var eased := 1.0 - pow(1.0 - _spawn_scale, 3.0)
	_model.scale = Vector3.ONE * float(profile["scale"]) * eased
	_brake(delta)
	if _spawn_scale >= 1.0:
		_change_state(State.PURSUE)

func _tick_idle(delta: float) -> void:
	_brake(delta)
	if _distance_to_target() < LOSE_RANGE:
		_change_state(State.PURSUE)

func _tick_pursue(delta: float) -> void:
	var distance := _distance_to_target()
	if distance > LOSE_RANGE:
		_change_state(State.IDLE)
		return
	if distance < ATTACK_RANGE:
		_change_state(State.WINDUP)
		return
	if distance < CIRCLE_RANGE and randf() < delta * 0.6:
		_circle_sign = 1.0 if randf() < 0.5 else -1.0
		_change_state(State.CIRCLE)
		return
	var to_target := target.global_position - global_position
	_move_towards(_steer(Vector3(to_target.x, 0, to_target.z)), float(profile["speed"]), delta)

func _tick_circle(delta: float) -> void:
	var distance := _distance_to_target()
	if distance > CIRCLE_RANGE * 1.5 or _state_time > 2.4:
		_change_state(State.PURSUE)
		return
	if distance < ATTACK_RANGE:
		_change_state(State.WINDUP)
		return
	var to_target := (target.global_position - global_position)
	var flat := Vector3(to_target.x, 0, to_target.z).normalized()
	var tangent := flat.rotated(Vector3.UP, PI * 0.5 * _circle_sign)
	# Spiral inwards while strafing so circling closes the distance.
	_move_towards(_steer((tangent * 0.85 + flat * 0.35).normalized()), float(profile["speed"]) * 0.7, delta)

func _tick_windup(delta: float) -> void:
	_brake(delta)
	if _state_time <= delta:
		# First tick of the wind-up: the audible telegraph, matching the visual.
		Signals.sfx_requested.emit("growl", global_position)
	_rage = minf(1.0, _rage + delta * 3.0)
	if _distance_to_target() > ATTACK_RANGE * 2.2:
		_change_state(State.PURSUE)
		return
	if _state_time > _windup_duration():
		_change_state(State.STRIKE)

func _windup_duration() -> float:
	match kind:
		Monster.Kind.BRUTE: return 0.85
		Monster.Kind.SWARMER: return 0.35
		_: return 0.55

func _tick_strike(delta: float) -> void:
	var lunge := float(profile["speed"]) * 1.6
	if target != null and is_instance_valid(target):
		var to_target := target.global_position - global_position
		_move_towards(Vector3(to_target.x, 0, to_target.z).normalized(), lunge, delta)
	if not _strike_done and _state_time > 0.10:
		_strike_done = true
		_resolve_strike()
	if _state_time > 0.32:
		_change_state(State.RECOVER)

func _resolve_strike() -> void:
	var reach := ATTACK_RANGE * float(profile["scale"])
	var centre := global_position + Vector3(0, 1.0, 0) - global_transform.basis.z * reach * 0.55
	var damage := 9.0 + max_health * 0.045
	if target != null and is_instance_valid(target) and target.has_method("take_damage"):
		if centre.distance_to(target.global_position + Vector3(0, 0.9, 0)) < reach:
			target.call("take_damage", damage, global_position, -global_transform.basis.z, false)
	VFX.impact(get_parent(), centre, -global_transform.basis.z, Color(1.0, 0.32, 0.10), float(profile["scale"]))
	Signals.camera_shake_requested.emit(0.12 * float(profile["scale"]), 0.2)

func _tick_recover(delta: float) -> void:
	_brake(delta)
	_rage = maxf(0.0, _rage - delta * 1.5)
	if _state_time > (0.7 if kind == Monster.Kind.BRUTE else 0.42):
		_change_state(State.PURSUE)

func _tick_stagger(delta: float) -> void:
	_brake(delta * 0.5)
	if _state_time > 0.36:
		_change_state(State.PURSUE)

func _tick_dead(delta: float) -> void:
	_brake(delta * 2.0)
	var t := clampf(1.0 - _state_time / 0.9, 0.0, 1.0)
	_model.scale = Vector3.ONE * float(profile["scale"]) * t
	if _core_light != null:
		_core_light.light_energy = 4.0 * t
	if _state_time > 1.0:
		queue_free()

# ------------------------------------------------------------------ damage --

func take_damage(amount: float, from_position: Vector3, direction: Vector3, crit: bool) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_rage = 1.0
	Signals.enemy_damaged.emit(self, amount, crit, from_position)
	VFX.impact(get_parent(), from_position, -direction, Materials.ORANGE_EMISSIVE, 0.8 + (0.6 if crit else 0.0))

	var knock := Vector3(direction.x, 0, direction.z).normalized() * (amount * 0.10 / maxf(float(profile["scale"]), 0.3))
	velocity += knock
	if health <= 0.0:
		_die()
	elif crit or amount > max_health * 0.22:
		_change_state(State.STAGGER)

func _die() -> void:
	_change_state(State.DEAD)
	collision_layer = 0
	VFX.dissolve(get_parent(), global_position + Vector3(0, 1.0, 0), float(profile["scale"]))
	Signals.sfx_requested.emit("enemy_die", global_position)
	Signals.enemy_died.emit(self, global_position)
	Signals.hit_stop_requested.emit(0.10, 0.05)
	Signals.camera_shake_requested.emit(0.35, 0.3)
	died.emit(self)

# --------------------------------------------------------------- animation --

func _update_animation(delta: float) -> void:
	var planar := Vector3(velocity.x, 0, velocity.z)
	var speed := planar.length()
	var desired := _facing
	if target != null and is_instance_valid(target) and state in [State.WINDUP, State.STRIKE, State.CIRCLE]:
		var to_target := target.global_position - global_position
		desired = atan2(-to_target.x, -to_target.z)
	elif speed > 0.3:
		desired = atan2(-planar.x, -planar.z)
	var previous := _facing
	_facing = lerp_angle(_facing, desired, 1.0 - pow(0.0006, delta))
	_turn_rate = lerpf(_turn_rate, wrapf(_facing - previous, -PI, PI) / maxf(delta, 0.001) * 0.25, 0.2)
	rotation.y = _facing

	if _animator == null:
		return
	var local_basis := global_transform.basis.inverse()
	_animator.speed = speed
	_animator.move_local = local_basis * planar.normalized() if speed > 0.05 else Vector3.ZERO
	_animator.grounded = is_on_floor()
	_animator.turn_rate = clampf(_turn_rate, -1.0, 1.0)
	_animator.stagger = 1.0 if state == State.STAGGER else 0.0
	_animator.jaw_open = 0.0
	_animator.rear_up = 0.0
	match state:
		State.WINDUP:
			var u := clampf(_state_time / _windup_duration(), 0.0, 1.0)
			_animator.jaw_open = u
			_animator.rear_up = u * (0.8 if kind == Monster.Kind.BRUTE else 0.45)
		State.STRIKE:
			_animator.jaw_open = 1.0
			_animator.rear_up = maxf(0.0, 0.5 - _state_time * 2.5)
		State.DEAD:
			_animator.jaw_open = 0.6
	if target != null and is_instance_valid(target):
		_animator.look_target = target.global_position + Vector3.UP
	else:
		_animator.look_target = Vector3.INF
	_animator.update(delta)

	_rage = maxf(0.0, _rage - delta * 0.8)
	var health_ratio := 1.0 - clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	if _flesh_material != null:
		_flesh_material.set_shader_parameter("rage", clampf(_rage * 0.6 + health_ratio * 0.7, 0.0, 1.0))
	if _core_light != null and state != State.DEAD:
		_core_light.light_energy = 3.0 + _rage * 9.0 + health_ratio * 4.0
