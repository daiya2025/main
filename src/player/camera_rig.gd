class_name CameraRig
extends Node3D
## Third-person cinematic camera.
##
## A spring arm with collision, plus the layers that separate a camera that
## *works* from one that *feels* right: velocity look-ahead, split horizontal /
## vertical damping so kerbs do not jolt the frame, trauma-based shake with a
## squared falloff, directional impulses on impact, an FOV that breathes with
## speed, and a depth of field that focuses on whatever is under the reticle.

signal focus_distance_changed(distance: float)

const MIN_PITCH := -1.15
const MAX_PITCH := 0.72
const BASE_DISTANCE := 4.35
const BASE_FOV := 68.0

@export var target: Node3D
@export var height_offset: float = 1.45
@export var shoulder_offset: float = 0.55

var yaw: float = 0.0
var pitch: float = -0.12
var distance: float = BASE_DISTANCE
var lock_on_target: Node3D = null
var photo_mode: bool = false

var _pivot: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _attributes: CameraAttributesPractical

var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite
var _impulse := Vector3.ZERO
var _impulse_velocity := Vector3.ZERO
var _fov_kick: float = 0.0
var _fov_kick_velocity: float = 0.0
var _smoothed_position := Vector3.ZERO
var _vertical_position: float = 0.0
var _look_ahead := Vector3.ZERO
var _focus_distance: float = 8.0
var _auto_align_delay: float = 0.0
var _photo_velocity := Vector3.ZERO

func _ready() -> void:
	_shake_noise = MeshLib.make_noise(9182, 1.0, 2)
	_shake_noise.frequency = 2.4

	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	_arm = SpringArm3D.new()
	_arm.name = "SpringArm"
	_arm.spring_length = BASE_DISTANCE
	_arm.margin = 0.35
	_arm.collision_mask = 1
	_pivot.add_child(_arm)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = float(Settings.get_value("fov", BASE_FOV))
	_camera.near = 0.06
	_camera.far = 1200.0
	_camera.current = true

	_attributes = CameraAttributesPractical.new()
	_attributes.dof_blur_far_enabled = true
	_attributes.dof_blur_far_distance = 14.0
	_attributes.dof_blur_far_transition = 22.0
	_attributes.dof_blur_near_enabled = true
	_attributes.dof_blur_near_distance = 0.9
	_attributes.dof_blur_near_transition = 1.4
	_attributes.dof_blur_amount = 0.06
	_attributes.auto_exposure_enabled = bool(Settings.get_value("auto_exposure", true))
	_attributes.auto_exposure_min_sensitivity = 40.0
	_attributes.auto_exposure_max_sensitivity = 700.0
	_attributes.auto_exposure_speed = 0.4
	_attributes.auto_exposure_scale = 0.42
	_camera.attributes = _attributes
	_arm.add_child(_camera)

	Signals.camera_shake_requested.connect(add_trauma)
	Signals.camera_impulse_requested.connect(add_impulse)
	Signals.camera_fov_kick_requested.connect(add_fov_kick)
	Signals.photo_mode_toggled.connect(func(active: bool) -> void: photo_mode = active)

	if target != null:
		_smoothed_position = target.global_position
		_vertical_position = target.global_position.y

func camera() -> Camera3D:
	return _camera

func attributes() -> CameraAttributesPractical:
	return _attributes

# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sensitivity := float(Settings.get_value("mouse_sensitivity", 0.0022))
		var invert := 1.0 if not bool(Settings.get_value("invert_y", false)) else -1.0
		yaw -= motion.relative.x * sensitivity
		pitch -= motion.relative.y * sensitivity * invert
		pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
		_auto_align_delay = 1.6

func _process(delta: float) -> void:
	if photo_mode:
		_process_photo(delta)
		return
	if target == null:
		return

	_gamepad_look(delta)
	_follow(delta)
	_apply_lock_on(delta)
	_apply_shake(delta)
	_apply_fov(delta)
	_apply_focus(delta)

func _gamepad_look(delta: float) -> void:
	var look := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	# Right stick is not in the action map; read it directly so a pad still works.
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.18:
		yaw -= stick.x * 2.6 * delta
		pitch -= stick.y * 1.9 * delta
		pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
		_auto_align_delay = 1.6
	_auto_align_delay = maxf(0.0, _auto_align_delay - delta)
	if look.length() > 0.1:
		pass

func _follow(delta: float) -> void:
	var target_pos := target.global_position

	# Horizontal follows quickly, vertical lags — a kerb or a stair step should
	# not move the horizon.
	var horizontal := Vector3(target_pos.x, _smoothed_position.y, target_pos.z)
	_smoothed_position = _smoothed_position.lerp(horizontal, 1.0 - pow(0.0008, delta))
	_vertical_position = lerpf(_vertical_position, target_pos.y, 1.0 - pow(0.02, delta))

	# Look ahead along the player's velocity so fast movement opens up the frame.
	var velocity := Vector3.ZERO
	if target is CharacterBody3D:
		velocity = (target as CharacterBody3D).velocity
	var ahead := Vector3(velocity.x, 0.0, velocity.z) * 0.16
	if ahead.length() > 2.2:
		ahead = ahead.normalized() * 2.2
	_look_ahead = _look_ahead.lerp(ahead, 1.0 - pow(0.02, delta))

	global_position = Vector3(_smoothed_position.x, _vertical_position, _smoothed_position.z) \
		+ Vector3(0, height_offset, 0) + _look_ahead + _impulse

	# Slowly swing back behind the player when the stick is idle.
	if _auto_align_delay <= 0.0 and lock_on_target == null:
		var planar := Vector3(velocity.x, 0.0, velocity.z)
		if planar.length() > 2.5:
			var desired := atan2(-planar.x, -planar.z)
			yaw = lerp_angle(yaw, desired, 1.0 - pow(0.35, delta))

	_pivot.rotation = Vector3(pitch, yaw, 0.0)

	# Pull in when sprinting so the character stays large in frame, and push out
	# when idle for a wider establishing shot.
	var speed := Vector3(velocity.x, 0, velocity.z).length()
	var desired_distance := BASE_DISTANCE + clampf(speed * 0.09, 0.0, 1.1) - _fov_kick * 0.004
	if lock_on_target != null:
		desired_distance += 0.9
	distance = lerpf(distance, desired_distance, 1.0 - pow(0.01, delta))
	_arm.spring_length = distance
	_camera.position = Vector3(shoulder_offset * (1.0 - clampf(speed / 12.0, 0.0, 0.6)), 0.0, 0.0)

func _apply_lock_on(delta: float) -> void:
	if lock_on_target == null or not is_instance_valid(lock_on_target):
		return
	# Frame the midpoint between hero and target rather than staring at either.
	var to_target := lock_on_target.global_position - global_position
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	var flat := Vector2(to_target.x, to_target.z).length()
	var desired_pitch := clampf(atan2(to_target.y - 0.6, flat) - 0.10, MIN_PITCH, MAX_PITCH)
	yaw = lerp_angle(yaw, desired_yaw, 1.0 - pow(0.008, delta))
	pitch = lerpf(pitch, desired_pitch, 1.0 - pow(0.05, delta))

# ------------------------------------------------------------------- shake --

func add_trauma(strength: float, duration: float) -> void:
	_trauma = clampf(_trauma + strength, 0.0, 1.0)
	_shake_time += duration * 0.0    # duration is folded into the decay rate
	_shake_time = maxf(_shake_time, duration)

func add_impulse(direction: Vector3, strength: float) -> void:
	_impulse_velocity += direction.normalized() * strength

func add_fov_kick(amount: float, _duration: float) -> void:
	_fov_kick_velocity += amount * 12.0

func _apply_shake(delta: float) -> void:
	_shake_time = maxf(0.0, _shake_time - delta)
	# Squared trauma: small hits barely register, big ones dominate. Linear
	# shake reads as camera noise instead of impact.
	var amount := _trauma * _trauma
	if amount > 0.0001:
		var t := Time.get_ticks_msec() * 0.001
		var ox := _shake_noise.get_noise_2d(t * 46.0, 0.0)
		var oy := _shake_noise.get_noise_2d(0.0, t * 46.0)
		var oz := _shake_noise.get_noise_2d(t * 31.0, t * 27.0)
		_pivot.rotation += Vector3(oy * 0.055, ox * 0.055, oz * 0.09) * amount
		_camera.h_offset = ox * 0.10 * amount
		_camera.v_offset = oy * 0.10 * amount
	else:
		_camera.h_offset = lerpf(_camera.h_offset, 0.0, 1.0 - pow(0.01, delta))
		_camera.v_offset = lerpf(_camera.v_offset, 0.0, 1.0 - pow(0.01, delta))
	_trauma = maxf(0.0, _trauma - delta * 1.6)

	# Impulses are a critically damped spring so a hit punches and settles.
	_impulse_velocity -= (_impulse * 90.0 + _impulse_velocity * 15.0) * delta
	_impulse += _impulse_velocity * delta
	if _impulse.length() > 0.8:
		_impulse = _impulse.normalized() * 0.8

func _apply_fov(delta: float) -> void:
	_fov_kick_velocity -= (_fov_kick * 130.0 + _fov_kick_velocity * 17.0) * delta
	_fov_kick += _fov_kick_velocity * delta
	var speed := 0.0
	if target is CharacterBody3D:
		var v := (target as CharacterBody3D).velocity
		speed = Vector3(v.x, 0, v.z).length()
	var base := float(Settings.get_value("fov", BASE_FOV))
	var speed_fov := clampf((speed - 5.0) * 0.75, 0.0, 9.0)
	_camera.fov = lerpf(_camera.fov, base + speed_fov + _fov_kick, 1.0 - pow(0.02, delta))

func _apply_focus(delta: float) -> void:
	# Focus on whatever the reticle is over; fall back to the lock-on target.
	var desired := 14.0
	if lock_on_target != null and is_instance_valid(lock_on_target):
		desired = _camera.global_position.distance_to(lock_on_target.global_position)
	else:
		var space := get_world_3d().direct_space_state
		if space != null:
			var from := _camera.global_position
			var to := from - _camera.global_transform.basis.z * 120.0
			var params := PhysicsRayQueryParameters3D.create(from, to)
			params.collision_mask = 1 | 4
			var hit := space.intersect_ray(params)
			if not hit.is_empty():
				desired = from.distance_to(hit["position"])
	_focus_distance = lerpf(_focus_distance, clampf(desired, 1.2, 90.0), 1.0 - pow(0.02, delta))
	_attributes.dof_blur_far_distance = _focus_distance
	_attributes.dof_blur_far_transition = maxf(_focus_distance * 0.6, 6.0)
	_attributes.dof_blur_near_distance = maxf(_focus_distance * 0.28, 0.6)
	focus_distance_changed.emit(_focus_distance)

# -------------------------------------------------------------- photo mode --

func _process_photo(delta: float) -> void:
	var input := Vector3(
		Input.get_axis("move_left", "move_right"),
		(1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("sprint") else 0.0),
		Input.get_axis("move_forward", "move_back"))
	var basis := _camera.global_transform.basis
	var wish := (basis.x * input.x + Vector3.UP * input.y + basis.z * input.z)
	if wish.length() > 0.001:
		wish = wish.normalized() * (18.0 if Input.is_action_pressed("dash") else 6.0)
	_photo_velocity = _photo_velocity.lerp(wish, 1.0 - pow(0.005, delta))
	global_position += _photo_velocity * delta
	_pivot.rotation = Vector3(pitch, yaw, 0.0)
	_arm.spring_length = 0.0
