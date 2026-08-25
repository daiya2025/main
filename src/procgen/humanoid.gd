class_name Humanoid
extends RefCounted
## Anatomy-driven humanoid generator.
##
## World space: Y up, character faces +Z, +X is the character's LEFT.
## Everything on the left half of the body is built in world space and then
## mirrored, which keeps the maths readable and guarantees symmetry.
##
## Output is a Dictionary with the bone table, the skinning capsules and one
## array-mesh per material group (skin / bodysuit / eyes / hair).

const HEIGHT := 1.80          # metres, head-to-heel
const HEAD_CENTER := Vector3(0.0, 1.655, 0.004)

# ---------------------------------------------------------------- skeleton --

## name -> [parent name, global rest position]. Order matters: a parent must be
## declared before its children.
static func bone_table() -> Array:
	var bones: Array = []
	var add := func(n: String, parent: String, pos: Vector3) -> void:
		bones.append({"name": n, "parent": parent, "pos": pos})

	add.call("Root", "", Vector3(0, 0, 0))
	add.call("Hips", "Root", Vector3(0, 0.980, 0.000))
	add.call("Spine", "Hips", Vector3(0, 1.090, 0.006))
	add.call("Chest", "Spine", Vector3(0, 1.208, 0.008))
	add.call("UpperChest", "Chest", Vector3(0, 1.336, 0.000))
	add.call("Neck", "UpperChest", Vector3(0, 1.478, -0.010))
	add.call("Head", "Neck", Vector3(0, 1.566, 0.002))
	add.call("HeadTop", "Head", Vector3(0, 1.775, 0.004))

	for side in [1, -1]:
		var s := "L" if side > 0 else "R"
		var x := float(side)
		add.call("Shoulder." + s, "UpperChest", Vector3(x * 0.045, 1.412, 0.004))
		add.call("UpperArm." + s, "Shoulder." + s, Vector3(x * 0.180, 1.398, 0.002))
		add.call("LowerArm." + s, "UpperArm." + s, Vector3(x * 0.202, 1.118, -0.006))
		add.call("Hand." + s, "LowerArm." + s, Vector3(x * 0.214, 0.856, 0.006))
		_add_fingers(bones, s, x)
		add.call("UpperLeg." + s, "Hips", Vector3(x * 0.094, 0.942, 0.002))
		add.call("LowerLeg." + s, "UpperLeg." + s, Vector3(x * 0.100, 0.520, 0.010))
		add.call("Foot." + s, "LowerLeg." + s, Vector3(x * 0.100, 0.092, -0.018))
		add.call("Toe." + s, "Foot." + s, Vector3(x * 0.100, 0.026, 0.108))
	return bones

const FINGER_LAYOUT := {
	#  name      spread(x)  forward(z)  lengths (proximal, middle, distal)
	"Thumb": [0.030, 0.028, [0.038, 0.032, 0.026]],
	"Index": [0.030, 0.006, [0.042, 0.026, 0.020]],
	"Middle": [0.011, 0.008, [0.046, 0.029, 0.021]],
	"Ring": [-0.010, 0.005, [0.042, 0.027, 0.020]],
	"Pinky": [-0.030, -0.002, [0.034, 0.021, 0.017]],
}

static func _add_fingers(bones: Array, s: String, x: float) -> void:
	var wrist := Vector3(x * 0.214, 0.856, 0.006)
	for finger in FINGER_LAYOUT.keys():
		var layout: Array = FINGER_LAYOUT[finger]
		var spread := float(layout[0])
		var forward := float(layout[1])
		var lengths: Array = layout[2]
		# The thumb starts at the base of the palm, the others at the knuckles.
		var start := wrist + Vector3(x * spread, -0.020 if finger == "Thumb" else -0.082, forward)
		var parent := "Hand." + s
		var pos := start
		for j in lengths.size():
			var bone_name := "%s%d.%s" % [finger, j + 1, s]
			bones.append({"name": bone_name, "parent": parent, "pos": pos})
			var dir := Vector3(x * 0.18, -1.0, 0.10).normalized() if finger != "Thumb" \
				else Vector3(x * 0.55, -0.72, 0.42).normalized()
			pos = pos + dir * float(lengths[j])
			parent = bone_name
		bones.append({"name": "%sEnd.%s" % [finger, s], "parent": parent, "pos": pos})

## Radius of influence per bone prefix, used to derive skinning capsules.
const BONE_RADIUS := {
	"Hips": 0.20, "Spine": 0.20, "Chest": 0.21, "UpperChest": 0.22,
	"Neck": 0.11, "Head": 0.16, "HeadTop": 0.14,
	"Shoulder": 0.13, "UpperArm": 0.11, "LowerArm": 0.09, "Hand": 0.065,
	"UpperLeg": 0.16, "LowerLeg": 0.13, "Foot": 0.10, "Toe": 0.08,
	"Thumb": 0.022, "Index": 0.020, "Middle": 0.020, "Ring": 0.019, "Pinky": 0.017,
}

static func _radius_for(bone_name: String) -> float:
	var base := bone_name.split(".")[0]
	for key in BONE_RADIUS.keys():
		if base.begins_with(key):
			return float(BONE_RADIUS[key])
	return 0.09

## Builds the capsule list the skinning solver consumes.
static func skinning_segments(bones: Array) -> Array:
	var index_of := {}
	for i in bones.size():
		index_of[bones[i]["name"]] = i
	var children := {}
	for b in bones:
		var parent: String = b["parent"]
		if parent.is_empty():
			continue
		if not children.has(parent):
			children[parent] = []
		(children[parent] as Array).append(b)

	var segments: Array = []
	for i in bones.size():
		var b: Dictionary = bones[i]
		var name: String = b["name"]
		if name == "Root":
			continue
		var a: Vector3 = b["pos"]
		var tip := a
		var kids: Array = children.get(name, [])
		if kids.is_empty():
			# leaf: extend a little along the parent's direction
			var parent_pos: Vector3 = bones[index_of[b["parent"]]]["pos"]
			tip = a + (a - parent_pos).normalized() * 0.04
		else:
			var sum := Vector3.ZERO
			for k in kids:
				sum += k["pos"]
			tip = sum / float(kids.size())
		var radius := _radius_for(name)
		var sharpness := 2.2
		var gain := 1.0
		# Hands and fingers must not be captured by the forearm capsule.
		if name.begins_with("Hand") or _is_finger(name):
			sharpness = 3.2
			gain = 1.6
		elif name.begins_with("Head") or name == "Neck":
			gain = 1.25
		segments.append(Skinning.segment(i, a, tip, radius, sharpness, gain))
	return segments

static func _is_finger(bone_name: String) -> bool:
	for f in FINGER_LAYOUT.keys():
		if bone_name.begins_with(f):
			return true
	return false

# -------------------------------------------------------------- geometry ----

## Lofts a tube along control points. `keys` are [t, radius_x, radius_z, n]
## with t in 0..1 measured along the resampled path.
static func tube(control: PackedVector3Array, keys: Array, segments: int, samples_per_span: int,
		lobes: PackedFloat32Array = PackedFloat32Array(), cap_start: bool = true, cap_end: bool = true,
		v_scale: float = 1.0) -> Array:
	var path := MeshLib.catmull_rom(control, samples_per_span)
	var frames := MeshLib.rmf_frames(path, Vector3.FORWARD)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: Array = []
	var vs := PackedFloat32Array()
	var arc := 0.0
	for i in path.size():
		var t := float(i) / float(maxi(path.size() - 1, 1))
		var rk := _sample_keys(keys, t)
		var ring := MeshLib.lobed_ring(rk.x, rk.y, segments, lobes, rk.z)
		rings.append(MeshLib.place_ring(ring, path[i], frames[i]))
		if i > 0:
			arc += path[i].distance_to(path[i - 1])
		vs.append(arc * v_scale)
	MeshLib.stitch(st, rings, vs, 1.0, 0)
	if cap_start:
		MeshLib.cap_ring(st, rings[0], path[0] - (path[1] - path[0]).normalized() * 0.004, vs[0], true, 0)
	if cap_end:
		var last := rings.size() - 1
		MeshLib.cap_ring(st, rings[last], path[last] + (path[last] - path[last - 1]).normalized() * 0.004, vs[last], false, 0)
	st.generate_normals()
	st.index()
	var mesh: ArrayMesh = st.commit()
	return MeshLib.weld(mesh.surface_get_arrays(0), 0.0006)

## Linear interpolation between radius keys -> Vector3(rx, rz, n).
static func _sample_keys(keys: Array, t: float) -> Vector3:
	if keys.is_empty():
		return Vector3(0.1, 0.1, 2.0)
	if t <= float(keys[0][0]):
		return Vector3(keys[0][1], keys[0][2], keys[0][3])
	for i in range(keys.size() - 1):
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if t <= float(k1[0]):
			var span := maxf(float(k1[0]) - float(k0[0]), 0.00001)
			var f := (t - float(k0[0])) / span
			f = f * f * (3.0 - 2.0 * f)
			return Vector3(
				lerpf(k0[1], k1[1], f),
				lerpf(k0[2], k1[2], f),
				lerpf(k0[3], k1[3], f))
	var last: Array = keys[keys.size() - 1]
	return Vector3(last[1], last[2], last[3])

static func mirror_x(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var out_verts := PackedVector3Array()
	out_verts.resize(verts.size())
	for i in verts.size():
		var p: Vector3 = verts[i]
		out_verts[i] = Vector3(-p.x, p.y, p.z)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out_idx := PackedInt32Array()
	out_idx.resize(idx.size())
	var tri_count := idx.size() / 3
	for t in tri_count:
		out_idx[t * 3 + 0] = idx[t * 3 + 0]
		out_idx[t * 3 + 1] = idx[t * 3 + 2]   # flip winding
		out_idx[t * 3 + 2] = idx[t * 3 + 1]
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = out_verts
	out[Mesh.ARRAY_INDEX] = out_idx
	out[Mesh.ARRAY_NORMAL] = null
	out[Mesh.ARRAY_TANGENT] = null
	return MeshLib.recompute_normals(out)

# ------------------------------------------------------------------ parts ----

## The trunk: pelvis -> lumbar -> ribcage -> shoulder girdle, with the
## superellipse exponent rising towards the chest so the section goes from oval
## (waist) to the broad, flattened box of the thorax.
static func torso(build_factor: float = 1.0) -> Array:
	var b := build_factor
	var control := PackedVector3Array([
		Vector3(0, 0.870, 0.010),
		Vector3(0, 0.960, 0.006),
		Vector3(0, 1.075, 0.018),
		Vector3(0, 1.195, 0.012),
		Vector3(0, 1.320, -0.004),
		Vector3(0, 1.418, -0.012),
		Vector3(0, 1.470, -0.014),
	])
	var keys := [
		[0.00, 0.150 * b, 0.118 * b, 2.30],   # pelvic floor
		[0.14, 0.168 * b, 0.128 * b, 2.35],   # hips / iliac crest
		[0.32, 0.139 * b, 0.108 * b, 2.15],   # waist
		[0.52, 0.163 * b, 0.122 * b, 2.30],   # lower ribs
		[0.72, 0.189 * b, 0.131 * b, 2.55],   # chest
		[0.88, 0.203 * b, 0.121 * b, 2.75],   # shoulder girdle
		[1.00, 0.150 * b, 0.104 * b, 2.50],   # neck base
	]
	var a := tube(control, keys, 40, 7, PackedFloat32Array(), true, true, 1.6)

	# ---- musculature ------------------------------------------------------
	# pectorals
	a = Sculpt.blob(a, Vector3(0.070, 1.315, 0.108), Vector3(0.085, 0.070, 0.060), 0.021 * b, Vector3(0, -0.15, 1).normalized(), 1.1, true)
	a = Sculpt.crease(a, Vector3(0, 1.300, 0.120), Vector3(1, 0, 0), 0.014, 0.010,
		Vector3(0, 1.300, 0.115), Vector3(0.030, 0.075, 0.070))
	# rectus abdominis + linea alba
	a = Sculpt.blob(a, Vector3(0.030, 1.185, 0.110), Vector3(0.052, 0.075, 0.055), 0.010 * b, Vector3(0, 0, 1), 1.2, true)
	a = Sculpt.crease(a, Vector3(0, 1.160, 0.118), Vector3(1, 0, 0), 0.010, 0.005,
		Vector3(0, 1.160, 0.112), Vector3(0.024, 0.095, 0.060))
	for y in [1.230, 1.180, 1.130]:
		a = Sculpt.crease(a, Vector3(0, y, 0.115), Vector3(0, 1, 0), 0.009, 0.004,
			Vector3(0, y, 0.108), Vector3(0.075, 0.016, 0.055))
	# latissimus flare and serratus
	a = Sculpt.blob(a, Vector3(0.150, 1.255, -0.010), Vector3(0.075, 0.115, 0.085), 0.016 * b, Vector3(1, 0.1, 0).normalized(), 1.0, true)
	a = Sculpt.blob(a, Vector3(0.125, 1.215, 0.070), Vector3(0.045, 0.055, 0.045), 0.007 * b, Vector3.ZERO, 1.4, true)
	# trapezius ramp into the neck
	a = Sculpt.blob(a, Vector3(0.070, 1.412, -0.030), Vector3(0.110, 0.070, 0.090), 0.020 * b, Vector3(0, 1, -0.25).normalized(), 1.0, true)
	# scapula ridge + spinal furrow
	a = Sculpt.blob(a, Vector3(0.085, 1.320, -0.090), Vector3(0.060, 0.075, 0.045), 0.009 * b, Vector3(0, 0, -1), 1.3, true)
	a = Sculpt.crease(a, Vector3(0, 1.260, -0.110), Vector3(1, 0, 0), 0.016, 0.011,
		Vector3(0, 1.230, -0.105), Vector3(0.030, 0.185, 0.070))
	# clavicles
	a = Sculpt.blob(a, Vector3(0.085, 1.400, 0.060), Vector3(0.090, 0.022, 0.045), 0.008, Vector3(0, 0.5, 1).normalized(), 1.5, true)
	# gluteal mass and hip flare
	a = Sculpt.blob(a, Vector3(0.075, 0.930, -0.075), Vector3(0.085, 0.090, 0.070), 0.024 * b, Vector3(0, -0.1, -1).normalized(), 1.0, true)
	a = Sculpt.blob(a, Vector3(0.155, 0.985, 0.000), Vector3(0.060, 0.080, 0.090), 0.010 * b, Vector3(1, 0, 0), 1.2, true)
	return a

static func neck() -> Array:
	var control := PackedVector3Array([
		Vector3(0, 1.412, -0.006),
		Vector3(0, 1.478, -0.008),
		Vector3(0, 1.545, -0.002),
		Vector3(0, 1.595, 0.004),
	])
	var keys := [
		[0.00, 0.083, 0.086, 2.30],
		[0.35, 0.062, 0.070, 2.10],
		[0.75, 0.058, 0.066, 2.05],
		[1.00, 0.066, 0.074, 2.10],
	]
	var a := tube(control, keys, 28, 8, PackedFloat32Array(), false, false, 2.0)
	# sternocleidomastoid pair + laryngeal prominence
	a = Sculpt.blob(a, Vector3(0.028, 1.470, 0.052), Vector3(0.030, 0.070, 0.035), 0.007, Vector3(0.3, 0, 1).normalized(), 1.2, true)
	a = Sculpt.blob(a, Vector3(0, 1.505, 0.062), Vector3(0.016, 0.024, 0.020), 0.004, Vector3(0, 0, 1), 1.5)
	return a

## Left arm in world space (mirrored later for the right).
static func arm(build_factor: float = 1.0) -> Array:
	var b := build_factor
	var control := PackedVector3Array([
		Vector3(0.150, 1.418, 0.004),
		Vector3(0.186, 1.386, 0.002),
		Vector3(0.196, 1.250, -0.002),
		Vector3(0.203, 1.120, -0.006),
		Vector3(0.208, 0.985, 0.000),
		Vector3(0.214, 0.868, 0.006),
	])
	var keys := [
		[0.00, 0.088 * b, 0.086 * b, 2.20],   # deltoid root
		[0.12, 0.075 * b, 0.074 * b, 2.15],   # deltoid
		[0.35, 0.059 * b, 0.058 * b, 2.05],   # mid humerus
		[0.52, 0.052 * b, 0.053 * b, 2.10],   # elbow
		[0.68, 0.058 * b, 0.056 * b, 2.05],   # forearm belly
		[0.90, 0.036 * b, 0.032 * b, 2.05],   # wrist
		[1.00, 0.034 * b, 0.030 * b, 2.05],
	]
	var a := tube(control, keys, 26, 7, PackedFloat32Array(), true, false, 2.0)
	# deltoid cap — also the piece that hides the torso/arm intersection
	a = Sculpt.blob(a, Vector3(0.183, 1.393, 0.000), Vector3(0.072, 0.078, 0.078), 0.014 * b, Vector3.ZERO, 1.1)
	# biceps / triceps
	a = Sculpt.blob(a, Vector3(0.192, 1.268, 0.030), Vector3(0.048, 0.078, 0.046), 0.010 * b, Vector3(0, 0, 1), 1.2)
	a = Sculpt.blob(a, Vector3(0.196, 1.262, -0.038), Vector3(0.046, 0.085, 0.044), 0.008 * b, Vector3(0, 0, -1), 1.2)
	# olecranon
	a = Sculpt.blob(a, Vector3(0.205, 1.118, -0.038), Vector3(0.036, 0.036, 0.030), 0.006, Vector3(0, -0.2, -1).normalized(), 1.5)
	# brachioradialis
	a = Sculpt.blob(a, Vector3(0.206, 1.045, 0.030), Vector3(0.044, 0.070, 0.040), 0.007 * b, Vector3(0, 0, 1), 1.3)
	# ulnar styloid
	a = Sculpt.blob(a, Vector3(0.226, 0.874, 0.000), Vector3(0.020, 0.022, 0.024), 0.004, Vector3(1, 0, 0), 1.6)
	return a

## Left hand: palm block plus five sculpted fingers, built from the same bone
## positions the skinning uses so the weights land where the knuckles are.
static func hand(bones: Array) -> Array:
	var by_name := {}
	for b in bones:
		by_name[b["name"]] = b["pos"]
	var wrist: Vector3 = by_name["Hand.L"]

	var palm := Sculpt.rounded_box(Vector3(0.094, 0.036, 0.098), 0.016, 3)
	palm = Sculpt.project_uv_spherical(palm, Vector3.ZERO)
	var palm_xform := Transform3D(Basis(), wrist + Vector3(0.004, -0.048, 0.004))
	var a := Sculpt.merge(_empty(), palm, palm_xform)
	# thenar eminence and knuckle ridge
	a = Sculpt.blob(a, wrist + Vector3(0.030, -0.038, 0.020), Vector3(0.026, 0.036, 0.030), 0.007, Vector3(0.6, 0, 1).normalized(), 1.2)
	a = Sculpt.blob(a, wrist + Vector3(0.000, -0.082, 0.006), Vector3(0.050, 0.016, 0.036), 0.005, Vector3(0, -1, 0), 1.4)
	a = Sculpt.blob(a, wrist + Vector3(-0.034, -0.040, 0.000), Vector3(0.022, 0.030, 0.030), 0.005, Vector3(-1, 0, 0.2).normalized(), 1.3)

	for finger in FINGER_LAYOUT.keys():
		var joints := PackedVector3Array()
		for j in range(1, 4):
			joints.append(by_name["%s%d.L" % [finger, j]])
		joints.append(by_name["%sEnd.L" % finger])
		var thickness := 0.0105 if finger != "Thumb" else 0.0135
		if finger == "Pinky":
			thickness = 0.0088
		var keys := [
			[0.00, thickness * 1.10, thickness * 1.00, 2.20],
			[0.32, thickness * 0.98, thickness * 0.92, 2.15],
			[0.62, thickness * 0.90, thickness * 0.86, 2.15],
			[0.88, thickness * 0.82, thickness * 0.80, 2.20],
			[1.00, thickness * 0.62, thickness * 0.60, 2.30],
		]
		var digit := tube(joints, keys, 14, 5, PackedFloat32Array(), true, true, 4.0)
		# knuckle swellings at each joint
		for j in range(joints.size() - 1):
			digit = Sculpt.blob(digit, joints[j], Vector3(thickness * 1.5, thickness * 1.5, thickness * 1.5), thickness * 0.16, Vector3.ZERO, 1.2)
		a = Sculpt.merge(a, digit)
	return a

## Left leg in world space.
static func leg(build_factor: float = 1.0) -> Array:
	var b := build_factor
	var control := PackedVector3Array([
		Vector3(0.092, 0.995, 0.004),
		Vector3(0.094, 0.900, 0.006),
		Vector3(0.098, 0.700, 0.010),
		Vector3(0.100, 0.525, 0.012),
		Vector3(0.100, 0.360, 0.004),
		Vector3(0.100, 0.180, -0.008),
		Vector3(0.100, 0.100, -0.014),
	])
	var keys := [
		[0.00, 0.118 * b, 0.118 * b, 2.20],   # hip joint
		[0.16, 0.107 * b, 0.110 * b, 2.15],   # upper thigh
		[0.42, 0.088 * b, 0.092 * b, 2.10],   # mid thigh
		[0.60, 0.070 * b, 0.074 * b, 2.15],   # knee
		[0.72, 0.079 * b, 0.082 * b, 2.10],   # calf belly
		[0.90, 0.048 * b, 0.052 * b, 2.10],   # lower calf
		[1.00, 0.040 * b, 0.045 * b, 2.10],   # ankle
	]
	var a := tube(control, keys, 26, 7, PackedFloat32Array(), true, false, 2.0)
	# quadriceps sweep + vastus medialis teardrop
	a = Sculpt.blob(a, Vector3(0.095, 0.760, 0.070), Vector3(0.070, 0.150, 0.055), 0.012 * b, Vector3(0, 0, 1), 1.1)
	a = Sculpt.blob(a, Vector3(0.072, 0.590, 0.050), Vector3(0.042, 0.060, 0.050), 0.009 * b, Vector3(-0.4, 0, 1).normalized(), 1.3)
	# hamstring
	a = Sculpt.blob(a, Vector3(0.098, 0.740, -0.062), Vector3(0.065, 0.140, 0.050), 0.009 * b, Vector3(0, 0, -1), 1.1)
	# patella
	a = Sculpt.blob(a, Vector3(0.099, 0.522, 0.062), Vector3(0.040, 0.048, 0.032), 0.006, Vector3(0, 0, 1), 1.4)
	# gastrocnemius heads
	a = Sculpt.blob(a, Vector3(0.088, 0.400, -0.060), Vector3(0.048, 0.100, 0.048), 0.012 * b, Vector3(-0.2, 0, -1).normalized(), 1.1)
	a = Sculpt.blob(a, Vector3(0.115, 0.415, -0.055), Vector3(0.040, 0.090, 0.045), 0.009 * b, Vector3(0.3, 0, -1).normalized(), 1.2)
	# tibial crest + malleoli
	a = Sculpt.blob(a, Vector3(0.086, 0.330, 0.048), Vector3(0.016, 0.150, 0.028), 0.004, Vector3(0, 0, 1), 1.6)
	a = Sculpt.blob(a, Vector3(0.078, 0.108, -0.006), Vector3(0.020, 0.024, 0.026), 0.005, Vector3(-1, 0, 0), 1.5)
	a = Sculpt.blob(a, Vector3(0.122, 0.100, -0.006), Vector3(0.018, 0.022, 0.024), 0.004, Vector3(1, 0, 0), 1.5)
	return a

## Left foot: a wedge with an arch, a heel and toes — flat-bottomed so it plants
## convincingly on the ground.
static func foot() -> Array:
	var block := Sculpt.rounded_box(Vector3(0.098, 0.086, 0.255), 0.030, 3)
	block = Sculpt.project_uv_spherical(block, Vector3.ZERO)
	var a := Sculpt.merge(_empty(), block, Transform3D(Basis(), Vector3(0.100, 0.056, 0.024)))
	a = Sculpt.blob(a, Vector3(0.100, 0.062, -0.075), Vector3(0.055, 0.060, 0.050), 0.010, Vector3(0, 0.1, -1).normalized(), 1.1)  # heel
	a = Sculpt.blob(a, Vector3(0.100, 0.100, -0.010), Vector3(0.055, 0.045, 0.075), 0.012, Vector3(0, 1, 0), 1.1)                  # instep
	a = Sculpt.blob(a, Vector3(0.078, 0.040, 0.010), Vector3(0.030, 0.040, 0.090), -0.014, Vector3.ZERO, 1.2)                      # medial arch
	a = Sculpt.scale_region(a, Vector3(0.100, 0.040, 0.130), Vector3(0.090, 0.060, 0.070), Vector3(0.94, 0.62, 1.0), 1.0)          # toe box
	a = Sculpt.flatten_below(a, 0.012, 0.030)
	return a

static func _empty() -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	out[Mesh.ARRAY_INDEX] = PackedInt32Array()
	out[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	return out

# ------------------------------------------------------------------ build ----

## Assembles the whole figure.
##   cfg: { build: 0.9..1.15, quality: 0.6..1.4, seed: int, bare_hands: bool }
static func build(cfg: Dictionary = {}) -> Dictionary:
	var build_factor := float(cfg.get("build", 1.06))
	var quality := float(cfg.get("quality", 1.0))
	var seed_value := int(cfg.get("seed", 20250825))

	var bones := bone_table()
	var segments := skinning_segments(bones)

	# --- body (bodysuit surface) ---
	var body := torso(build_factor)
	body = Sculpt.merge(body, neck())
	var left_arm := arm(build_factor)
	var left_leg := leg(build_factor)
	var left_foot := foot()
	body = Sculpt.merge(body, left_arm)
	body = Sculpt.merge(body, mirror_x(left_arm))
	body = Sculpt.merge(body, left_leg)
	body = Sculpt.merge(body, mirror_x(left_leg))
	body = Sculpt.merge(body, left_foot)
	body = Sculpt.merge(body, mirror_x(left_foot))

	if quality > 0.85:
		body = MeshLib.subdivide(body)
		body = MeshLib.relax(body, 1, 0.22)
	body = Sculpt.project_uv_spherical(body, Vector3(0, 1.15, 0), 3.0)
	body = MeshLib.displace(body, MeshLib.make_noise(seed_value + 5, 34.0, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.45), 0.0018)
	body = MeshLib.bake_cavity(body, 0.9, 0.05)
	body = MeshLib.with_tangents(body)

	# --- hands (skin surface) ---
	var left_hand := hand(bones)
	var hands := Sculpt.merge(left_hand, mirror_x(left_hand))
	hands = MeshLib.relax(hands, 1, 0.2)
	hands = Sculpt.project_uv_spherical(hands, Vector3(0, 0.86, 0), 3.0)
	hands = MeshLib.displace(hands, MeshLib.make_noise(seed_value + 9, 120.0, 3), 0.0006)
	hands = MeshLib.bake_cavity(hands, 0.8, 0.02)
	hands = MeshLib.with_tangents(hands)

	# --- head (skin surface) ---
	var head_parts := HeadBuilder.build(seed_value, quality)
	var head: Array = _translate(head_parts["head"], HEAD_CENTER)
	var eyes: Array = _translate(head_parts["eyes"], HEAD_CENTER)
	var skin := Sculpt.merge(head, hands)
	skin = MeshLib.with_tangents(skin)

	return {
		"bones": bones,
		"segments": segments,
		"skin": skin,
		"eyes": eyes,
		"body": body,
		"head_center": HEAD_CENTER,
		"stats": {
			"body_tris": MeshLib.tri_count(body),
			"skin_tris": MeshLib.tri_count(skin),
			"bones": bones.size(),
		},
	}

static func _translate(arrays: Array, delta: Vector3) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		moved[i] = verts[i] + delta
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = moved
	return out
