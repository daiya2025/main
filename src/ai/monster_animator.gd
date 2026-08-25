class_name MonsterAnimator
extends Node
## Procedural quadruped animation.
##
## Gait is a trot: diagonal pairs move together, which is what a four-legged
## predator actually does at speed and reads instantly as "animal" rather than
## "table walking". On top of that sit the spine wave, the head that leads the
## turn, and a tail that lags behind everything as a chain of springs.

const STANCE_RATIO := 0.55
const BASE_STRIDE := 1.05

var skeleton: Skeleton3D
var stride_scale: float = 1.0
var body_height: float = 1.4

# --- inputs ---------------------------------------------------------------
var speed: float = 0.0
var move_local := Vector3.ZERO
var turn_rate: float = 0.0
var grounded: bool = true
var look_target: Vector3 = Vector3.INF
var jaw_open: float = 0.0
var rear_up: float = 0.0
var stagger: float = 0.0

var _phase: float = 0.0
var _breath: float = 0.0
var _tail_offsets: Array[float] = []
var _tail_velocity: Array[float] = []
var _b := {}
var _tail_bones: PackedInt32Array = PackedInt32Array()
var _bones_cached: bool = false

const LEGS := [
	{"prefix": "Front", "side": "L", "phase": 0.0, "root": "Shoulder"},
	{"prefix": "Front", "side": "R", "phase": 0.5, "root": "Shoulder"},
	{"prefix": "Rear", "side": "L", "phase": 0.5, "root": "Hip"},
	{"prefix": "Rear", "side": "R", "phase": 0.0, "root": "Hip"},
]

func _init(target_skeleton: Skeleton3D) -> void:
	name = "MonsterAnimator"
	skeleton = target_skeleton

func _ready() -> void:
	_cache_bones()

## Idempotent, and also called lazily from update() so an animator driven
## before it enters the tree still poses.
func _cache_bones() -> void:
	if skeleton == null:
		return
	_bones_cached = true
	_tail_bones = PackedInt32Array()
	_tail_offsets.clear()
	_tail_velocity.clear()
	for n in ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "Jaw", "HeadEnd"]:
		_b[n] = skeleton.find_bone(n)
	for leg in LEGS:
		for joint in ["Shoulder", "Hip", "Upper", "Lower", "Ankle", "Foot", "Toe"]:
			var key := "%s%s.%s" % [leg["prefix"], joint, leg["side"]]
			_b[key] = skeleton.find_bone(key)
	var i := 1
	while true:
		var idx := skeleton.find_bone("Tail%d" % i)
		if idx < 0:
			break
		_tail_bones.append(idx)
		_tail_offsets.append(0.0)
		_tail_velocity.append(0.0)
		i += 1

func bone(name: String) -> int:
	return int(_b.get(name, -1))

func update(delta: float) -> void:
	if skeleton == null:
		return
	if not _bones_cached:
		_cache_bones()
	PoseKit.reset(skeleton)

	var stride := clampf(BASE_STRIDE * stride_scale * sqrt(maxf(speed, 0.0)), 0.5, 3.4)
	_phase = fposmod(_phase + (speed / maxf(stride, 0.001)) * delta, 1.0)
	_breath = fposmod(_breath + delta * 0.45, 1.0)

	_spine(delta)
	_legs(stride)
	_head(delta)
	_tail(delta)

func _spine(_delta: float) -> void:
	var walk := clampf(speed / 6.0, 0.0, 1.0)
	# A travelling wave down the spine, plus the roll that a trot produces.
	var segments := [["Hips", 0.0], ["Spine1", 0.22], ["Spine2", 0.44], ["Chest", 0.66]]
	for seg in segments:
		var idx := bone(seg[0])
		if idx < 0:
			continue
		var offset := float(seg[1])
		var yaw := sin((_phase - offset) * TAU) * 0.075 * walk
		var roll := cos((_phase - offset) * TAU) * 0.055 * walk
		var pitch := sin(_breath * TAU) * 0.012 - rear_up * 0.35 + stagger * 0.20
		yaw += turn_rate * 0.10 * (1.0 - offset)
		skeleton.set_bone_pose_rotation(idx,
			Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.FORWARD, roll) * Quaternion(Vector3.RIGHT, pitch))

	var hips := bone("Hips")
	if hips >= 0:
		var rest := skeleton.get_bone_rest(hips).origin
		var bob := (-cos(_phase * TAU * 2.0) * 0.5 + 0.5) * clampf(speed * 0.016, 0.0, 0.09)
		skeleton.set_bone_pose_position(hips, rest + Vector3(0, -bob - stagger * 0.15, 0))

func _legs(stride: float) -> void:
	var walking := speed > 0.2
	for leg in LEGS:
		var prefix: String = leg["prefix"]
		var side: String = leg["side"]
		var root := bone("%s%s.%s" % [prefix, leg["root"], side])
		var upper := bone("%sUpper.%s" % [prefix, side])
		var lower := bone("%sLower.%s" % [prefix, side])
		var ankle := bone("%sAnkle.%s" % [prefix, side])
		var foot := bone("%sFoot.%s" % [prefix, side])
		var toe := bone("%sToe.%s" % [prefix, side])
		if upper < 0 or lower < 0 or ankle < 0:
			continue

		var rest_ankle := _rest_global(ankle)
		var t := fposmod(_phase + float(leg["phase"]), 1.0)
		var target := rest_ankle
		if walking:
			var direction := move_local
			if direction.length_squared() < 0.0001:
				direction = Vector3.FORWARD
			direction = Vector3(direction.x, 0.0, direction.z).normalized()
			var offset := 0.0
			var lift := 0.0
			if t < STANCE_RATIO:
				offset = lerpf(stride * 0.5, -stride * 0.5, t / STANCE_RATIO)
			else:
				var u := (t - STANCE_RATIO) / (1.0 - STANCE_RATIO)
				var eased := u * u * (3.0 - 2.0 * u)
				offset = lerpf(-stride * 0.5, stride * 0.5, eased)
				lift = sin(PI * u) * clampf(0.12 + speed * 0.035, 0.12, 0.55)
			target = rest_ankle + direction * offset + Vector3(0, lift, 0)
		if prefix == "Front":
			target.y += rear_up * 1.1
			target += Vector3(0, 0, rear_up * 0.35)

		# Front knees fold backwards, rear hocks forwards — the difference is
		# the single clearest cue that this is a quadruped and not a mirror.
		var pole_z := 1.0 if prefix == "Front" else -1.0
		var side_sign := 1.0 if side == "L" else -1.0
		var pole := Vector3(side_sign * 0.3, 0.0, pole_z).normalized()
		PoseKit.two_bone(skeleton, upper, lower, ankle, target, pole)
		if root >= 0:
			# Keep the shoulder/hip attachment aimed at the limb it carries.
			PoseKit.aim(skeleton, root, upper, skeleton.get_bone_global_pose(upper).origin - _rest_global(root))
		if foot >= 0:
			PoseKit.aim(skeleton, ankle, foot, Vector3(0, -1.0, 0.35).normalized())
		if toe >= 0 and foot >= 0:
			var toe_pitch := 0.35 if (walking and t > STANCE_RATIO - 0.14 and t < STANCE_RATIO) else 0.0
			PoseKit.aim(skeleton, foot, toe, Vector3(0, -sin(toe_pitch) - 0.15, cos(toe_pitch)).normalized())

func _rest_global(bone_index: int) -> Vector3:
	# Walk the rest chain, since get_bone_global_pose reflects the *current*
	# pose and we want the neutral stance position.
	var transform := Transform3D.IDENTITY
	var chain: Array[int] = []
	var idx := bone_index
	while idx >= 0:
		chain.push_front(idx)
		idx = skeleton.get_bone_parent(idx)
	for b in chain:
		transform = transform * skeleton.get_bone_rest(b)
	return transform.origin

func _head(_delta: float) -> void:
	var walk := clampf(speed / 6.0, 0.0, 1.0)
	for pair in [["Neck1", 0.5], ["Neck2", 0.5]]:
		var idx := bone(pair[0])
		if idx < 0:
			continue
		var w := float(pair[1])
		var bob := sin(_phase * TAU * 2.0) * 0.045 * walk
		skeleton.set_bone_pose_rotation(idx,
			Quaternion(Vector3.RIGHT, bob + rear_up * -0.30 * w)
			* Quaternion(Vector3.UP, -turn_rate * 0.22 * w))

	var head := bone("Head")
	if head >= 0 and look_target.x != INF:
		var head_pos := skeleton.get_global_transform() * skeleton.get_bone_global_pose(head).origin
		var local_dir := skeleton.get_global_transform().affine_inverse().basis * (look_target - head_pos).normalized()
		var rest_dir := PoseKit.rest_direction(skeleton, bone("HeadEnd"))
		PoseKit.aim(skeleton, head, bone("HeadEnd"), rest_dir.slerp(local_dir, 0.6))

	var jaw := bone("Jaw")
	if jaw >= 0:
		skeleton.set_bone_pose_rotation(jaw, Quaternion(Vector3.RIGHT, jaw_open * 0.75))

func _tail(delta: float) -> void:
	# Each segment chases the previous one through a spring, so the tail whips
	# on a turn and settles with a lag.
	var drive := sin(_phase * TAU) * clampf(speed * 0.06, 0.0, 0.30) - turn_rate * 0.35
	for i in _tail_bones.size():
		var target := drive if i == 0 else _tail_offsets[i - 1]
		var result := PoseKit.spring(_tail_offsets[i], target, _tail_velocity[i], 120.0 - float(i) * 9.0, 11.0, delta)
		_tail_offsets[i] = clampf(result[0], -0.7, 0.7)
		_tail_velocity[i] = result[1]
		var droop := 0.10 + float(i) * 0.02 - rear_up * 0.12
		skeleton.set_bone_pose_rotation(_tail_bones[i],
			Quaternion(Vector3.UP, _tail_offsets[i]) * Quaternion(Vector3.RIGHT, droop))
