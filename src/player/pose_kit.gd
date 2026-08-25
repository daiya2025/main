class_name PoseKit
extends RefCounted
## Skeleton posing helpers for the procedural animation system.
##
## Every rig in this project is built with identity rest *bases* — only the
## translations differ — so a bone's "direction" is simply the offset to its
## child. That makes aiming a bone a shortest-arc rotation problem instead of a
## per-bone correction-matrix problem, and it is why the animation code below
## stays readable.

## Clears every pose rotation back to rest.
static func reset(skeleton: Skeleton3D) -> void:
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(i, Quaternion.IDENTITY)
		skeleton.set_bone_pose_position(i, skeleton.get_bone_rest(i).origin)

static func find(skeleton: Skeleton3D, bone_name: String) -> int:
	return skeleton.find_bone(bone_name)

## Rest-space direction from `bone` to `child`, normalised.
static func rest_direction(skeleton: Skeleton3D, child: int) -> Vector3:
	var origin := skeleton.get_bone_rest(child).origin
	return origin.normalized() if origin.length_squared() > 0.000001 else Vector3.UP

## Rotates `bone` so that its child points along `dir` (skeleton space).
## `roll` twists about the resulting axis.
static func aim(skeleton: Skeleton3D, bone: int, child: int, dir: Vector3, roll: float = 0.0) -> void:
	if bone < 0 or child < 0:
		return
	var target := dir.normalized()
	if target.length_squared() < 0.000001:
		return
	var rest_dir := rest_direction(skeleton, child)
	var global_rot := Quaternion(Basis.IDENTITY)
	var parent := skeleton.get_bone_parent(bone)
	if parent >= 0:
		global_rot = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var swing := _shortest_arc(rest_dir, target)
	if absf(roll) > 0.0001:
		swing = Quaternion(target, roll) * swing
	skeleton.set_bone_pose_rotation(bone, global_rot.inverse() * swing)

static func _shortest_arc(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var d := a.dot(b)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		# 180°: any perpendicular axis will do
		var axis := a.cross(Vector3.UP)
		if axis.length_squared() < 0.0001:
			axis = a.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(clampf(d, -1.0, 1.0)))

## Applies an extra local rotation on top of whatever the bone already has.
static func add_local(skeleton: Skeleton3D, bone: int, extra: Quaternion, weight: float = 1.0) -> void:
	if bone < 0:
		return
	var current := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, current * Quaternion.IDENTITY.slerp(extra, clampf(weight, 0.0, 1.0)))

static func set_local(skeleton: Skeleton3D, bone: int, rotation: Quaternion, weight: float = 1.0) -> void:
	if bone < 0:
		return
	var current := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, current.slerp(rotation, clampf(weight, 0.0, 1.0)))

## Analytic two-bone IK (hip -> knee -> ankle, shoulder -> elbow -> wrist).
## `target` and `pole` are in skeleton space. Returns the reached ankle position.
static func two_bone(skeleton: Skeleton3D, root: int, mid: int, tip: int,
		target: Vector3, pole: Vector3, soft_limit: float = 0.995) -> Vector3:
	if root < 0 or mid < 0 or tip < 0:
		return target
	var l1 := skeleton.get_bone_rest(mid).origin.length()
	var l2 := skeleton.get_bone_rest(tip).origin.length()
	var root_pos := skeleton.get_bone_global_pose(root).origin
	var to_target := target - root_pos
	var reach := l1 + l2
	var dist := clampf(to_target.length(), 0.001, reach * soft_limit)
	var dir := to_target.normalized()
	if dir.length_squared() < 0.000001:
		dir = Vector3.DOWN

	# Law of cosines: where along `dir` the knee projects, and how far off-axis.
	var a := clampf((dist * dist + l1 * l1 - l2 * l2) / (2.0 * dist), -l1, l1)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pole_dir := pole - dir * pole.dot(dir)
	if pole_dir.length_squared() < 0.000001:
		pole_dir = dir.cross(Vector3.RIGHT)
		if pole_dir.length_squared() < 0.000001:
			pole_dir = dir.cross(Vector3.FORWARD)
	pole_dir = pole_dir.normalized()
	var knee := root_pos + dir * a + pole_dir * h

	aim(skeleton, root, mid, knee - root_pos)
	# The mid bone's global pose is only valid after the root has been posed.
	var knee_pos := skeleton.get_bone_global_pose(mid).origin
	aim(skeleton, mid, tip, (root_pos + dir * dist) - knee_pos)
	return skeleton.get_bone_global_pose(tip).origin

## Curls a finger (or any chain) by rotating each joint about `axis`.
static func curl_chain(skeleton: Skeleton3D, bones: PackedInt32Array, axis: Vector3, angle: float, falloff: float = 0.85) -> void:
	var a := angle
	for bone in bones:
		if bone < 0:
			continue
		var current := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, current * Quaternion(axis.normalized(), a))
		a *= falloff

## Smooth spring damper used for every "follow but lag behind" value in the
## animation and camera code.
static func spring(current: float, target: float, velocity: float, stiffness: float, damping: float, delta: float) -> Array:
	var force := (target - current) * stiffness - velocity * damping
	var new_velocity := velocity + force * delta
	return [current + new_velocity * delta, new_velocity]
