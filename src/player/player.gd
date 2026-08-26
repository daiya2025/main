class_name Player
extends CharacterBody3D
## DIGIHARIMAN — the player character.
##
## Movement is deliberately "heavy but responsive": high acceleration on the
## ground, low in the air, a dash with real invulnerability frames, and a
## three-hit melee chain whose timing windows (wind-up / active / recovery) are
## the same numbers the animator uses, so what you see is exactly what hits.

signal died()

const WALK_SPEED := 3.4
const RUN_SPEED := 6.6
const SPRINT_SPEED := 9.6
const GROUND_ACCEL := 42.0
const GROUND_FRICTION := 26.0
const AIR_ACCEL := 12.0
const JUMP_VELOCITY := 8.6
const AIR_JUMPS := 1
const DASH_SPEED := 20.0
const DASH_TIME := 0.20
const DASH_COOLDOWN := 0.62
const TURN_RATE := 13.0

const MAX_HEALTH := 100.0
const MAX_ENERGY := 100.0
const ENERGY_REGEN := 14.0
const BOLT_COST := 22.0

## wind-up, active, recovery (seconds) and reach/damage per combo step.
const COMBO := [
	{"pose": "slash_1", "wind": 0.13, "active": 0.10, "recover": 0.20, "reach": 2.5, "radius": 1.5, "damage": 26.0, "lunge": 5.0},
	{"pose": "slash_2", "wind": 0.11, "active": 0.10, "recover": 0.19, "reach": 2.6, "radius": 1.6, "damage": 30.0, "lunge": 5.5},
	{"pose": "smash", "wind": 0.20, "active": 0.14, "recover": 0.36, "reach": 2.9, "radius": 2.1, "damage": 58.0, "lunge": 6.5},
]

var health: float = MAX_HEALTH
var energy: float = MAX_ENERGY
var alive: bool = true

var camera_rig: CameraRig
var lock_on_target: Node3D = null

var _model: Node3D
var _skeleton: Skeleton3D
var _animator: HumanoidAnimator
var _aura: GPUParticles3D
var _dash_trail: GPUParticles3D

var _dash_time: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction := Vector3.FORWARD
var _air_jumps := AIR_JUMPS
var _invulnerable: float = 0.0
var _hurt_time: float = 0.0

var _combo_index: int = -1
var _attack_time: float = 0.0
var _attack_buffered: bool = false
var _attack_hit_done: bool = false
var _cast_time: float = 0.0

var _previous_velocity := Vector3.ZERO
var _facing: float = 0.0

func _ready() -> void:
	add_to_group("player")
	collision_layer = 1 << 1
	collision_mask = 1
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.4
	slide_on_ceiling = true

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.72
	shape.shape = capsule
	shape.position = Vector3(0, 0.90, 0)
	add_child(shape)

	_model = DigiHariMan.create_node({"quality": 1.0})
	add_child(_model)
	_skeleton = _model.get_child(0) as Skeleton3D

	_animator = HumanoidAnimator.new(_skeleton)
	add_child(_animator)
	_animator.footstep.connect(func(_side: String) -> void:
		Signals.sfx_requested.emit("footstep", global_position))

	_aura = VFX.aura(self)
	_aura.position = Vector3(0, 0.95, 0)
	_dash_trail = VFX.dash_trail(self)
	_dash_trail.position = Vector3(0, 0.95, 0)

	Game.player = self
	Signals.player_spawned.emit(self)
	Signals.player_health_changed.emit(health, MAX_HEALTH)
	Signals.player_energy_changed.emit(energy, MAX_ENERGY)

# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		move_and_slide()
		return

	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	_invulnerable = maxf(0.0, _invulnerable - delta)
	_hurt_time = maxf(0.0, _hurt_time - delta)
	if _combo_index < 0 and _cast_time <= 0.0:
		energy = minf(MAX_ENERGY, energy + ENERGY_REGEN * delta)
		Signals.player_energy_changed.emit(energy, MAX_ENERGY)

	var wish := _wish_direction()
	if _dash_time > 0.0:
		_process_dash(delta)
	else:
		_process_move(delta, wish)
	_process_attack(delta)

	_previous_velocity = velocity
	move_and_slide()
	_update_animation(delta, wish)

func _wish_direction() -> Vector3:
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	if input.length() > 1.0:
		input = input.normalized()
	if input.length() < 0.08 or camera_rig == null:
		return Vector3.ZERO
	# Camera-relative, projected onto the ground plane.
	var basis := camera_rig.camera().global_transform.basis
	var forward := -Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return (right * input.x + forward * -input.y).normalized() * input.length()

func _process_move(delta: float, wish: Vector3) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 22.0) * delta
	else:
		_air_jumps = AIR_JUMPS

	var sprinting := Input.is_action_pressed("sprint") and wish.length() > 0.5 and _combo_index < 0
	var top_speed := WALK_SPEED
	if wish.length() > 0.6:
		top_speed = SPRINT_SPEED if sprinting else RUN_SPEED
	elif wish.length() > 0.1:
		top_speed = lerpf(WALK_SPEED, RUN_SPEED, wish.length())
	if _combo_index >= 0:
		top_speed *= 0.35     # attacks root you, but not completely

	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if wish.length() > 0.05:
		planar = planar.move_toward(wish * top_speed, accel * delta)
	else:
		planar = planar.move_toward(Vector3.ZERO, (GROUND_FRICTION if is_on_floor() else 1.5) * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			Signals.camera_fov_kick_requested.emit(1.5, 0.2)
			Signals.sfx_requested.emit("jump", global_position)
		elif _air_jumps > 0:
			_air_jumps -= 1
			velocity.y = JUMP_VELOCITY * 0.88
			VFX.impact(get_parent(), global_position, Vector3.DOWN, Materials.ORANGE_EMISSIVE, 0.7)
			Signals.camera_fov_kick_requested.emit(2.2, 0.2)
			Signals.sfx_requested.emit("jump", global_position)

	if Input.is_action_just_pressed("dash") and _dash_cooldown <= 0.0:
		_start_dash(wish)

	if Input.is_action_just_pressed("special") and energy >= BOLT_COST and _cast_time <= 0.0:
		_cast_bolt()
	_cast_time = maxf(0.0, _cast_time - delta)

	# Landing impact
	if is_on_floor() and _previous_velocity.y < -9.0:
		var force := clampf(-_previous_velocity.y / 26.0, 0.0, 1.0)
		Signals.camera_shake_requested.emit(force * 0.35, 0.2)
		VFX.impact(get_parent(), global_position, Vector3.UP, Color(0.8, 0.75, 0.7), force * 1.4)
		Signals.sfx_requested.emit("land", global_position)

func _start_dash(wish: Vector3) -> void:
	_dash_direction = wish
	if _dash_direction.length() < 0.1:
		_dash_direction = -global_transform.basis.z
	_dash_direction = _dash_direction.normalized()
	_dash_time = DASH_TIME
	_dash_cooldown = DASH_COOLDOWN
	_invulnerable = DASH_TIME + 0.08
	_combo_index = -1
	_dash_trail.emitting = true
	Signals.camera_fov_kick_requested.emit(4.5, 0.25)
	Signals.sfx_requested.emit("dash", global_position)
	Signals.camera_impulse_requested.emit(-_dash_direction, 0.9)

func _process_dash(delta: float) -> void:
	_dash_time -= delta
	velocity = _dash_direction * DASH_SPEED
	velocity.y = 0.0
	if _dash_time <= 0.0:
		_dash_trail.emitting = false
		velocity = _dash_direction * RUN_SPEED

func _cast_bolt() -> void:
	energy -= BOLT_COST
	Signals.player_energy_changed.emit(energy, MAX_ENERGY)
	_cast_time = 0.35
	_combo_index = -1

	var bolt := EnergyBolt.new()
	var origin := global_position + Vector3(0, 1.25, 0) - global_transform.basis.z * 0.7
	var direction := -global_transform.basis.z
	if camera_rig != null:
		direction = -camera_rig.camera().global_transform.basis.z
	if lock_on_target != null and is_instance_valid(lock_on_target):
		direction = (lock_on_target.global_position + Vector3.UP - origin).normalized()
		bolt.homing_target = lock_on_target
	bolt.velocity = direction * 44.0
	get_parent().add_child(bolt)
	bolt.global_position = origin

	VFX.impact(get_parent(), origin, direction, Materials.ORANGE_EMISSIVE, 0.6)
	Signals.sfx_requested.emit("bolt_fire", origin)
	Signals.camera_impulse_requested.emit(-direction, 0.35)
	Signals.camera_shake_requested.emit(0.10, 0.1)

# ------------------------------------------------------------------ combat --

func _process_attack(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		if _combo_index < 0 and _dash_time <= 0.0:
			_begin_attack(0)
		else:
			_attack_buffered = true

	if _combo_index < 0:
		return

	var step: Dictionary = COMBO[_combo_index]
	var wind: float = step["wind"]
	var active: float = step["active"]
	var total: float = wind + active + float(step["recover"])
	_attack_time += delta

	# Lunge forward during the wind-up so the swing carries weight.
	if _attack_time < wind:
		var forward := -global_transform.basis.z
		velocity.x = lerpf(velocity.x, forward.x * float(step["lunge"]), delta * 9.0)
		velocity.z = lerpf(velocity.z, forward.z * float(step["lunge"]), delta * 9.0)

	if not _attack_hit_done and _attack_time >= wind and _attack_time <= wind + active:
		_attack_hit_done = true
		_resolve_hit(step)

	if _attack_time >= total:
		if _attack_buffered and _combo_index + 1 < COMBO.size():
			_begin_attack(_combo_index + 1)
		else:
			_combo_index = -1
			_attack_buffered = false

func _begin_attack(index: int) -> void:
	_combo_index = index
	_attack_time = 0.0
	_attack_hit_done = false
	_attack_buffered = false
	var step: Dictionary = COMBO[index]
	# Face the lock-on target (or the camera direction) when the swing starts.
	if lock_on_target != null and is_instance_valid(lock_on_target):
		var to_target := lock_on_target.global_position - global_position
		_facing = atan2(-to_target.x, -to_target.z)
	Signals.camera_fov_kick_requested.emit(1.2 + float(index) * 0.8, 0.2)
	Signals.sfx_requested.emit("slash_%d" % (index + 1), global_position)

func _resolve_hit(step: Dictionary) -> void:
	var forward := -global_transform.basis.z
	var centre := global_position + Vector3(0, 1.05, 0) + forward * float(step["reach"]) * 0.6
	var radius := float(step["radius"])

	VFX.slash_arc(get_parent(),
		Transform3D(Basis(Vector3.UP, _facing) * Basis(Vector3.RIGHT, PI * 0.5), centre),
		radius * 0.95)

	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), centre)
	query.collision_mask = 1 << 2
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hits := space.intersect_shape(query, 12)

	var connected := false
	for hit in hits:
		var node: Node = hit["collider"]
		var victim := node
		if not victim.has_method("take_damage") and victim.get_parent() != null:
			victim = victim.get_parent()
		if victim.has_method("take_damage"):
			var crit := _combo_index == COMBO.size() - 1
			victim.call("take_damage", float(step["damage"]), centre, forward, crit)
			connected = true

	if connected:
		Game.add_combo()
		var heavy := _combo_index == COMBO.size() - 1
		Signals.sfx_requested.emit("impact_heavy" if heavy else "impact", centre)
		Signals.hit_stop_requested.emit(0.09 if heavy else 0.055, 0.06 if heavy else 0.12)
		Signals.camera_shake_requested.emit(0.30 if heavy else 0.16, 0.22)
		Signals.camera_impulse_requested.emit(forward, 0.55 if heavy else 0.3)

func take_damage(amount: float, from_position: Vector3, _direction: Vector3, _crit: bool) -> void:
	if not alive or _invulnerable > 0.0:
		return
	health = maxf(0.0, health - amount)
	_hurt_time = 0.35
	_invulnerable = 0.45
	Signals.player_health_changed.emit(health, MAX_HEALTH)
	Signals.sfx_requested.emit("hurt", global_position)
	Signals.camera_shake_requested.emit(clampf(amount / 40.0, 0.15, 0.6), 0.3)
	Signals.camera_impulse_requested.emit((global_position - from_position).normalized(), 0.7)
	VFX.impact(get_parent(), global_position + Vector3(0, 1.0, 0), (global_position - from_position).normalized(),
		Color(1.0, 0.25, 0.15), 0.9)
	var knock := (global_position - from_position).normalized()
	velocity += Vector3(knock.x, 0.25, knock.z) * 6.0
	if health <= 0.0:
		_die()

func _die() -> void:
	alive = false
	_combo_index = -1
	Signals.player_died.emit()
	died.emit()
	Signals.camera_shake_requested.emit(0.8, 0.9)

func heal(amount: float) -> void:
	health = minf(MAX_HEALTH, health + amount)
	Signals.player_health_changed.emit(health, MAX_HEALTH)

# ----------------------------------------------------------------- lock-on --

func toggle_lock_on() -> void:
	if lock_on_target != null:
		lock_on_target = null
	else:
		lock_on_target = _find_lock_on()
	if camera_rig != null:
		camera_rig.lock_on_target = lock_on_target

func _find_lock_on() -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	var forward := -global_transform.basis.z
	if camera_rig != null:
		forward = -camera_rig.camera().global_transform.basis.z
		forward = Vector3(forward.x, 0, forward.z).normalized()
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_alive") and not enemy.call("is_alive"):
			continue
		var to_enemy := enemy.global_position - global_position
		var distance := to_enemy.length()
		if distance > 42.0:
			continue
		var alignment := forward.dot(Vector3(to_enemy.x, 0, to_enemy.z).normalized())
		if alignment < 0.05:
			continue
		var score := alignment * 2.4 - distance * 0.05
		if score > best_score:
			best_score = score
			best = enemy
	return best

# --------------------------------------------------------------- animation --

func _update_animation(delta: float, wish: Vector3) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var speed := planar.length()

	# Face movement, or the lock-on target when one is held.
	var desired_facing := _facing
	if lock_on_target != null and is_instance_valid(lock_on_target):
		var to_target := lock_on_target.global_position - global_position
		desired_facing = atan2(-to_target.x, -to_target.z)
	elif speed > 0.4:
		desired_facing = atan2(-planar.x, -planar.z)
	_facing = lerp_angle(_facing, desired_facing, 1.0 - pow(0.0001, delta * (TURN_RATE / 12.0)))
	rotation.y = _facing

	var local_basis := global_transform.basis.inverse()
	_animator.speed = speed
	_animator.move_local = local_basis * planar.normalized() if speed > 0.05 else Vector3.ZERO
	_animator.grounded = is_on_floor()
	_animator.vertical_velocity = velocity.y
	_animator.acceleration_local = local_basis * ((velocity - _previous_velocity) / maxf(delta, 0.0001))
	_animator.guard = clampf(_hurt_time * 2.0, 0.0, 0.6)
	_animator.crouch = 0.0
	if lock_on_target != null and is_instance_valid(lock_on_target):
		_animator.look_target = lock_on_target.global_position + Vector3.UP
	elif camera_rig != null:
		_animator.look_target = camera_rig.camera().global_position - camera_rig.camera().global_transform.basis.z * 20.0
	else:
		_animator.look_target = Vector3.INF

	if _combo_index >= 0:
		var step: Dictionary = COMBO[_combo_index]
		var total: float = float(step["wind"]) + float(step["active"]) + float(step["recover"])
		_animator.attack_pose = String(step["pose"])
		_animator.attack_time = clampf(_attack_time / total, 0.0, 1.0)
	elif _cast_time > 0.0:
		_animator.attack_pose = "cast"
		_animator.attack_time = clampf(1.0 - _cast_time / 0.35, 0.0, 1.0)
	else:
		_animator.attack_pose = ""

	_animator.update(delta)

	# Suit charge tracks the energy meter, so the character literally lights up
	# as the player's resource fills.
	var charge := clampf(energy / MAX_ENERGY, 0.0, 1.0)
	if _skeleton != null:
		for child in _skeleton.get_children():
			var mi := child as MeshInstance3D
			if mi == null:
				continue
			var mat := mi.material_override as ShaderMaterial
			if mat != null and mat.shader != null and mat.get_shader_parameter("charge") != null:
				mat.set_shader_parameter("charge", 0.25 + charge * 0.75)
	if _aura != null:
		_aura.amount_ratio = clampf(charge * charge * 0.75, 0.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_on"):
		toggle_lock_on()
