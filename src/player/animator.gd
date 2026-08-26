class_name HumanoidAnimator
extends Node
## Fully procedural humanoid animation.
##
## There is no imported animation data in this project. Locomotion is a gait
## model — foot targets travelling through stance and swing arcs, solved with
## two-bone IK — with the pelvis, spine, arms and head layered on top as
## physically motivated offsets: the pelvis rises twice per stride, the
## shoulders counter-rotate against the hips, the arms swing out of phase with
## the legs, and the whole torso leans into acceleration.

signal footstep(side: String)

const STANCE_RATIO := 0.62          # fraction of the cycle a foot is planted
const BASE_STRIDE := 0.92           # metres at 1 m/s, scaled by speed
const MAX_STRIDE := 2.35

var skeleton: Skeleton3D
var ground_raycast: bool = true

# --- inputs, written by the owner each frame -------------------------------
var speed: float = 0.0                       # planar speed, m/s
var move_local: Vector3 = Vector3.ZERO        # desired direction in character space
var grounded: bool = true
var vertical_velocity: float = 0.0
var acceleration_local: Vector3 = Vector3.ZERO
var look_target: Vector3 = Vector3.INF        # world space; INF disables head aim
var crouch: float = 0.0
var attack_pose: String = ""
var attack_time: float = 0.0                  # 0..1 through the current attack
var guard: float = 0.0

# --- internal state --------------------------------------------------------
var _phase: float = 0.0
var _bob_velocity: float = 0.0
var _bob: float = 0.0
var _lean := Vector2.ZERO
var _lean_velocity := Vector2.ZERO
var _breath: float = 0.0
var _airborne_time: float = 0.0
var _land_squash: float = 0.0

var _b := {}
var _finger_chains := {"L": [], "R": []}
var _bones_cached: bool = false

func _init(target_skeleton: Skeleton3D) -> void:
	name = "Animator"
	skeleton = target_skeleton

func _ready() -> void:
	_cache_bones()

## Caching is idempotent and also runs lazily from update(), so an animator that
## is driven before it enters the tree still poses instead of silently doing
## nothing.
func _cache_bones() -> void:
	if skeleton == null:
		return
	_bones_cached = true
	for n in ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "HeadTop"]:
		_b[n] = skeleton.find_bone(n)
	for s in ["L", "R"]:
		for n in ["Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toe"]:
			_b["%s.%s" % [n, s]] = skeleton.find_bone("%s.%s" % [n, s])
		var chains: Array = []
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			var chain := PackedInt32Array()
			for j in range(1, 4):
				chain.append(skeleton.find_bone("%s%d.%s" % [finger, j, s]))
			chains.append(chain)
		_finger_chains[s] = chains

func bone(name: String) -> int:
	return int(_b.get(name, -1))

# ---------------------------------------------------------------------------

func update(delta: float) -> void:
	if skeleton == null:
		return
	# The spring integrators explode on the multi-second deltas a loading hitch
	# (or a software rasteriser) can produce — one bad step throws the pelvis
	# kilometres away. Clamping costs nothing at normal frame rates.
	delta = clampf(delta, 0.0001, 1.0 / 20.0)
	if not _bones_cached:
		_cache_bones()
	PoseKit.reset(skeleton)

	var stride := clampf(BASE_STRIDE * sqrt(maxf(speed, 0.0)), 0.55, MAX_STRIDE)
	var cycle_rate := speed / maxf(stride, 0.001)
	_phase = fposmod(_phase + cycle_rate * delta, 1.0)
	_breath = fposmod(_breath + delta * 0.32, 1.0)

	if grounded:
		if _airborne_time > 0.25:
			_land_squash = minf(1.0, _airborne_time * 1.6)
		_airborne_time = 0.0
	else:
		_airborne_time += delta
	_land_squash = maxf(0.0, _land_squash - delta * 3.4)

	# Lean: the torso tips into acceleration and away from braking.
	var lean_target := Vector2(
		clampf(acceleration_local.x * 0.035, -0.30, 0.30),
		clampf(acceleration_local.z * 0.030, -0.26, 0.32))
	var lx := PoseKit.spring(_lean.x, lean_target.x, _lean_velocity.x, 90.0, 13.0, delta)
	var ly := PoseKit.spring(_lean.y, lean_target.y, _lean_velocity.y, 90.0, 13.0, delta)
	_lean = Vector2(lx[0], ly[0])
	_lean_velocity = Vector2(lx[1], ly[1])

	_pelvis(delta, stride)
	_spine()
	if grounded:
		_legs_walk(stride)
	else:
		_legs_air()
	_arms(stride)
	_head()
	_hands()
	if not attack_pose.is_empty():
		_attack_layer()

# ------------------------------------------------------------------ pelvis --

func _pelvis(delta: float, _stride: float) -> void:
	var hips := bone("Hips")
	if hips < 0:
		return
	var rest := skeleton.get_bone_rest(hips).origin

	# Two rises per stride, plus a breathing float when standing still.
	var gait_bob := -cos(_phase * TAU * 2.0) * 0.5 + 0.5
	var walk_amp := clampf(speed * 0.014, 0.0, 0.055)
	var idle_float := sin(_breath * TAU) * 0.006
	var target_bob := -gait_bob * walk_amp + idle_float
	target_bob -= crouch * 0.28
	target_bob -= _land_squash * 0.16
	if not grounded:
		target_bob += clampf(vertical_velocity * 0.006, -0.05, 0.05)
	var b := PoseKit.spring(_bob, target_bob, _bob_velocity, 260.0, 22.0, delta)
	_bob = b[0]
	_bob_velocity = b[1]
	skeleton.set_bone_pose_position(hips, rest + Vector3(0, _bob, 0))

	# The pelvis rotates opposite the shoulders and drops on the swing side.
	var walk_weight := clampf(speed / 5.0, 0.0, 1.0)
	var yaw := sin(_phase * TAU) * 0.16 * walk_weight
	var roll := cos(_phase * TAU) * 0.09 * walk_weight
	var pitch := _lean.y * 0.35 + crouch * 0.18
	skeleton.set_bone_pose_rotation(hips,
		Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.FORWARD, roll + _lean.x * 0.4) * Quaternion(Vector3.RIGHT, pitch))

func _spine() -> void:
	var walk_weight := clampf(speed / 5.0, 0.0, 1.0)
	var counter_yaw := -sin(_phase * TAU) * 0.13 * walk_weight
	var breathe := sin(_breath * TAU) * 0.012
	var lean_pitch := -_lean.y * 0.55 - crouch * 0.30 + _land_squash * 0.12
	var lean_roll := -_lean.x * 0.5

	for pair in [["Spine", 0.34], ["Chest", 0.36], ["UpperChest", 0.30]]:
		var idx := bone(pair[0])
		if idx < 0:
			continue
		var w := float(pair[1])
		skeleton.set_bone_pose_rotation(idx,
			Quaternion(Vector3.UP, counter_yaw * w)
			* Quaternion(Vector3.RIGHT, lean_pitch * w + breathe)
			* Quaternion(Vector3.FORWARD, lean_roll * w))

# -------------------------------------------------------------------- legs --

## Foot position for a leg at cycle position `t`, in character space.
func _foot_target(side: float, t: float, stride: float) -> Vector3:
	var base := Vector3(side * 0.100, 0.092, -0.018)
	var lateral := side * clampf(0.012 + speed * 0.004, 0.0, 0.05)
	var lift := clampf(0.06 + speed * 0.028, 0.06, 0.34)
	var direction := move_local
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD * -1.0    # default: face-forward stance
	direction = Vector3(direction.x, 0.0, direction.z).normalized()

	var offset := 0.0
	var height := 0.0
	if t < STANCE_RATIO:
		# Planted: the foot slides backwards under the body at exactly the
		# speed the body moves forward, which is what stops foot sliding.
		var u := t / STANCE_RATIO
		offset = lerpf(stride * 0.5, -stride * 0.5, u)
		height = 0.0
	else:
		var u := (t - STANCE_RATIO) / (1.0 - STANCE_RATIO)
		# ease-out forward reach with a lifted arc
		var eased := u * u * (3.0 - 2.0 * u)
		offset = lerpf(-stride * 0.5, stride * 0.5, eased)
		height = sin(PI * u) * lift
	var travel := direction * offset
	return base + Vector3(travel.x + lateral, height, travel.z)

var _prev_leg_t := {"L": 0.0, "R": 0.5}

func _legs_walk(stride: float) -> void:
	var walking := speed > 0.15
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var t := fposmod(_phase + (0.0 if side_name == "L" else 0.5), 1.0)
		# Swing -> stance transition = heel strike.
		if walking and float(_prev_leg_t[side_name]) > STANCE_RATIO and t < STANCE_RATIO:
			footstep.emit(side_name)
		_prev_leg_t[side_name] = t
		var target := _foot_target(side, t, stride) if walking else Vector3(side * 0.100, 0.092, -0.018)
		if not walking:
			# idle weight shift so the pose is never perfectly symmetrical
			target += Vector3(side * sin(_breath * TAU) * 0.006, 0.0, cos(_breath * TAU) * 0.004)
		target.y += _bob * 0.35 - crouch * 0.02
		if ground_raycast:
			target.y = maxf(target.y, _ground_height(target))
		var pole := Vector3(side * 0.35, 0.0, 1.0).normalized()
		PoseKit.two_bone(skeleton,
			bone("UpperLeg." + side_name), bone("LowerLeg." + side_name), bone("Foot." + side_name),
			target, pole)
		_orient_foot(side_name, t, walking)

func _legs_air() -> void:
	var tuck := clampf(0.5 - vertical_velocity * 0.05, 0.15, 1.0)
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var lead := 1.0 if side_name == "L" else -1.0
		var target := Vector3(
			side * 0.11,
			0.16 + tuck * 0.30 + lead * 0.05,
			0.10 + tuck * 0.22 * lead)
		var pole := Vector3(side * 0.35, 0.0, 1.0).normalized()
		PoseKit.two_bone(skeleton,
			bone("UpperLeg." + side_name), bone("LowerLeg." + side_name), bone("Foot." + side_name),
			target, pole)
		PoseKit.aim(skeleton, bone("Foot." + side_name), bone("Toe." + side_name), Vector3(0, -0.35, 1).normalized())

func _orient_foot(side_name: String, t: float, walking: bool) -> void:
	var foot := bone("Foot." + side_name)
	var toe := bone("Toe." + side_name)
	if foot < 0 or toe < 0:
		return
	var pitch := 0.0
	if walking:
		if t < 0.12:
			pitch = lerpf(-0.35, 0.0, t / 0.12)              # heel strike
		elif t > STANCE_RATIO - 0.16 and t < STANCE_RATIO:
			pitch = lerpf(0.0, 0.55, (t - (STANCE_RATIO - 0.16)) / 0.16)   # toe-off
		elif t >= STANCE_RATIO:
			var u := (t - STANCE_RATIO) / (1.0 - STANCE_RATIO)
			pitch = lerpf(0.55, -0.30, clampf(u * 1.4, 0.0, 1.0))
	var forward := Vector3(0.0, -sin(pitch), cos(pitch))
	PoseKit.aim(skeleton, foot, toe, forward)

func _ground_height(local_target: Vector3) -> float:
	var world := skeleton.get_global_transform() * local_target
	var space := skeleton.get_world_3d().direct_space_state
	if space == null:
		return local_target.y
	var params := PhysicsRayQueryParameters3D.create(world + Vector3.UP * 0.8, world + Vector3.DOWN * 0.8)
	params.collision_mask = 1
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return local_target.y
	var local_hit := skeleton.get_global_transform().affine_inverse() * (hit["position"] as Vector3)
	return maxf(local_hit.y + 0.085, local_target.y - 0.35)

# -------------------------------------------------------------------- arms --

func _arms(_stride: float) -> void:
	var walk_weight := clampf(speed / 6.0, 0.0, 1.0)
	var swing := 0.55 * walk_weight
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var t := fposmod(_phase + (0.5 if side_name == "L" else 0.0), 1.0)
		var forward := cos(t * TAU) * swing
		var out := 0.14 + walk_weight * 0.08 + guard * 0.25

		# Upper arm hangs down, swings fore/aft, and lifts away from the ribs.
		var upper_dir := Vector3(side * out, -1.0, forward).normalized()
		PoseKit.aim(skeleton, bone("Shoulder." + side_name), bone("UpperArm." + side_name),
			Vector3(side * 1.0, 0.12 + walk_weight * 0.05, 0.0).normalized())
		PoseKit.aim(skeleton, bone("UpperArm." + side_name), bone("LowerArm." + side_name), upper_dir)

		# The elbow is always slightly bent; it bends more at the front of the
		# swing, which is what makes a run read as effortful.
		var bend := 0.30 + walk_weight * 0.55 + maxf(forward, 0.0) * 0.5 + guard * 0.9
		var lower_dir := Vector3(side * out * 0.5, -1.0, forward * 0.5 + bend * 0.55).normalized()
		PoseKit.aim(skeleton, bone("LowerArm." + side_name), bone("Hand." + side_name), lower_dir)

func _head() -> void:
	var head := bone("Head")
	var neck := bone("Neck")
	if head < 0:
		return
	# Counteract the pelvis and torso motion so the eyes stay level — the
	# vestibulo-ocular reflex, and its absence is why naive procedural walks
	# look drunk.
	var walk_weight := clampf(speed / 5.0, 0.0, 1.0)
	var stabilise := Quaternion(Vector3.UP, sin(_phase * TAU) * 0.05 * walk_weight)
	if neck >= 0:
		PoseKit.set_local(skeleton, neck, Quaternion(Vector3.RIGHT, -_lean.y * 0.25) * stabilise, 1.0)

	if look_target.x != INF:
		var head_pos := skeleton.get_global_transform() * skeleton.get_bone_global_pose(head).origin
		var local_dir := skeleton.get_global_transform().affine_inverse().basis * (look_target - head_pos).normalized()
		var rest_dir := PoseKit.rest_direction(skeleton, bone("HeadTop"))
		# Clamp to a human neck's range so the head never spins around.
		var clamped := rest_dir.slerp(local_dir, 0.55)
		PoseKit.aim(skeleton, head, bone("HeadTop"), clamped)
	else:
		PoseKit.set_local(skeleton, head, Quaternion(Vector3.RIGHT, _lean.y * 0.2), 1.0)

func _hands() -> void:
	# A relaxed hand is never flat: the fingers curl progressively from index to
	# little finger, and the thumb opposes.
	var curl := 0.28 + guard * 0.8 + clampf(speed * 0.03, 0.0, 0.25)
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var chains: Array = _finger_chains[side_name]
		for i in chains.size():
			var chain: PackedInt32Array = chains[i]
			var amount := curl * (1.0 + float(i) * 0.10)
			if i == 0:
				PoseKit.curl_chain(skeleton, chain, Vector3(0.0, 0.0, side * -1.0), amount * 0.55, 0.8)
			else:
				PoseKit.curl_chain(skeleton, chain, Vector3(side * 1.0, 0.0, 0.0), amount, 0.86)

# ------------------------------------------------------------------ attack --

const ATTACK_POSES := {
	"slash_1": {
		"wind": 0.22,
		"arm": Vector3(0.85, 0.35, -0.55),
		"arm_end": Vector3(-0.55, -0.35, 0.95),
		"torso_yaw": -0.55,
		"torso_yaw_end": 0.45,
		"side": "R",
	},
	"slash_2": {
		"wind": 0.20,
		"arm": Vector3(-0.85, 0.30, -0.50),
		"arm_end": Vector3(0.60, -0.30, 0.95),
		"torso_yaw": 0.55,
		"torso_yaw_end": -0.42,
		"side": "L",
	},
	"smash": {
		"wind": 0.30,
		"arm": Vector3(0.15, 1.0, -0.35),
		"arm_end": Vector3(0.10, -0.55, 0.95),
		"torso_yaw": -0.15,
		"torso_yaw_end": 0.10,
		"side": "R",
	},
	"cast": {
		"wind": 0.35,
		"arm": Vector3(0.35, 0.15, 0.55),
		"arm_end": Vector3(0.20, 0.05, 1.0),
		"torso_yaw": 0.12,
		"torso_yaw_end": -0.05,
		"side": "R",
	},
}

func _attack_layer() -> void:
	var pose: Dictionary = ATTACK_POSES.get(attack_pose, {})
	if pose.is_empty():
		return
	var side_name: String = pose["side"]
	var side := 1.0 if side_name == "L" else -1.0
	var wind: float = pose["wind"]
	var t := clampf(attack_time, 0.0, 1.0)

	var blend := 0.0
	var dir: Vector3 = pose["arm"]
	var yaw := float(pose["torso_yaw"])
	if t < wind:
		# wind-up: ease in
		var u := t / maxf(wind, 0.001)
		blend = u * u
		dir = (pose["arm"] as Vector3)
		yaw = float(pose["torso_yaw"]) * blend
	else:
		# strike: fast ease-out, then recover
		var u := (t - wind) / maxf(1.0 - wind, 0.001)
		var strike := 1.0 - pow(1.0 - clampf(u * 1.9, 0.0, 1.0), 3.0)
		blend = 1.0 - smoothstep(0.65, 1.0, u)
		dir = (pose["arm"] as Vector3).lerp(pose["arm_end"], strike)
		yaw = lerpf(float(pose["torso_yaw"]), float(pose["torso_yaw_end"]), strike)

	var world_dir := Vector3(dir.x * side, dir.y, dir.z).normalized()
	for bone_pair in [["UpperArm", "LowerArm"], ["LowerArm", "Hand"]]:
		var a := bone("%s.%s" % [bone_pair[0], side_name])
		var c := bone("%s.%s" % [bone_pair[1], side_name])
		if a < 0 or c < 0:
			continue
		var current := skeleton.get_bone_pose_rotation(a)
		PoseKit.aim(skeleton, a, c, world_dir)
		skeleton.set_bone_pose_rotation(a, current.slerp(skeleton.get_bone_pose_rotation(a), blend))

	for pair in [["Spine", 0.3], ["Chest", 0.35], ["UpperChest", 0.35]]:
		var idx := bone(pair[0])
		if idx < 0:
			continue
		PoseKit.add_local(skeleton, idx, Quaternion(Vector3.UP, yaw * float(pair[1])), blend)

	# The striking hand closes into a fist through the swing.
	var chains: Array = _finger_chains[side_name]
	for i in chains.size():
		PoseKit.curl_chain(skeleton, chains[i], Vector3(side * 1.0, 0.0, 0.0), 1.1 * blend, 0.88)
