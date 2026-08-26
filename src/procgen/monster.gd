class_name Monster
extends RefCounted
## Corrupted-data creatures ("ノイズ体").
##
## One parametric generator drives three archetypes. They share a spine-driven
## body plan — the same way real tetrapods do — so proportions alone produce
## silhouettes that read as different animals rather than as recolours:
##
##   STALKER  fast digitigrade quadruped, long skull, whip tail
##   BRUTE    heavy front-loaded quadruped that walks on its knuckles
##   SWARMER  small, low, quick, oversized jaw
##
## Creature space: Y up, the creature faces +Z, +X is its LEFT.

enum Kind { STALKER, BRUTE, SWARMER }

const PROFILES := {
	Kind.STALKER: {
		"name": "Stalker",
		"scale": 1.0,
		"body_length": 1.75,
		"shoulder_height": 1.42,
		"hip_height": 1.36,
		"girth": 0.30,
		"neck_length": 0.62,
		"head_size": 0.30,
		"front_thickness": 0.085,
		"rear_thickness": 0.105,
		"tail_segments": 6,
		"tail_length": 1.55,
		"crest": 0.11,
		"horns": 2,
		"jaw_length": 0.30,
		"health": 120.0,
		"speed": 6.4,
	},
	Kind.BRUTE: {
		"name": "Brute",
		"scale": 1.35,
		"body_length": 1.55,
		"shoulder_height": 1.62,
		"hip_height": 1.25,
		"girth": 0.44,
		"neck_length": 0.36,
		"head_size": 0.30,
		"front_thickness": 0.145,
		"rear_thickness": 0.115,
		"tail_segments": 3,
		"tail_length": 0.65,
		"crest": 0.20,
		"horns": 4,
		"jaw_length": 0.24,
		"health": 340.0,
		"speed": 3.6,
	},
	Kind.SWARMER: {
		"name": "Swarmer",
		"scale": 0.62,
		"body_length": 1.30,
		"shoulder_height": 0.86,
		"hip_height": 0.88,
		"girth": 0.20,
		"neck_length": 0.34,
		"head_size": 0.29,
		"front_thickness": 0.055,
		"rear_thickness": 0.070,
		"tail_segments": 5,
		"tail_length": 1.05,
		"crest": 0.06,
		"horns": 0,
		"jaw_length": 0.30,
		"health": 45.0,
		"speed": 8.2,
	},
}

# ---------------------------------------------------------------- skeleton --

static func bone_table(kind: Kind) -> Array:
	var p: Dictionary = PROFILES[kind]
	var bones: Array = []
	var add := func(n: String, parent: String, pos: Vector3) -> void:
		bones.append({"name": n, "parent": parent, "pos": pos})

	var hip_h := float(p["hip_height"])
	var sho_h := float(p["shoulder_height"])
	var half := float(p["body_length"]) * 0.5

	add.call("Root", "", Vector3.ZERO)
	add.call("Hips", "Root", Vector3(0, hip_h, -half))
	add.call("Spine1", "Hips", Vector3(0, lerpf(hip_h, sho_h, 0.30) + 0.03, -half * 0.42))
	add.call("Spine2", "Spine1", Vector3(0, lerpf(hip_h, sho_h, 0.62) + 0.04, half * 0.10))
	add.call("Chest", "Spine2", Vector3(0, sho_h, half * 0.62))

	var neck := float(p["neck_length"])
	add.call("Neck1", "Chest", Vector3(0, sho_h + neck * 0.30, half * 0.62 + neck * 0.42))
	add.call("Neck2", "Neck1", Vector3(0, sho_h + neck * 0.48, half * 0.62 + neck * 0.85))
	var head_pos := Vector3(0, sho_h + neck * 0.52, half * 0.62 + neck * 1.18)
	add.call("Head", "Neck2", head_pos)
	add.call("Jaw", "Head", head_pos + Vector3(0, -float(p["head_size"]) * 0.30, float(p["head_size"]) * 0.18))
	add.call("HeadEnd", "Head", head_pos + Vector3(0, 0.02, float(p["jaw_length"]) + float(p["head_size"]) * 0.5))

	# tail: an even chain that droops slightly
	var segs := int(p["tail_segments"])
	var seg_len := float(p["tail_length"]) / float(maxi(segs, 1))
	var parent := "Hips"
	var pos := Vector3(0, hip_h, -half)
	for i in segs:
		pos += Vector3(0, -seg_len * 0.16 * float(i) / float(segs), -seg_len)
		var n := "Tail%d" % (i + 1)
		add.call(n, parent, pos)
		parent = n

	for side in [1, -1]:
		var s := "L" if side > 0 else "R"
		var x := float(side)
		# --- front (digitigrade, elbow back, wrist forward) ---
		var fx := x * (float(p["girth"]) * 0.85)
		var fz := half * 0.55
		add.call("FrontShoulder." + s, "Chest", Vector3(fx * 0.8, sho_h - 0.04, fz))
		add.call("FrontUpper." + s, "FrontShoulder." + s, Vector3(fx, sho_h - 0.10, fz - 0.02))
		add.call("FrontLower." + s, "FrontUpper." + s, Vector3(fx * 1.05, sho_h * 0.58, fz - 0.10))
		add.call("FrontAnkle." + s, "FrontLower." + s, Vector3(fx * 1.08, sho_h * 0.26, fz + 0.06))
		add.call("FrontFoot." + s, "FrontAnkle." + s, Vector3(fx * 1.08, 0.045, fz + 0.10))
		add.call("FrontToe." + s, "FrontFoot." + s, Vector3(fx * 1.08, 0.02, fz + 0.26))
		# --- rear (strong hock, knee forward) ---
		var rx := x * (float(p["girth"]) * 0.95)
		var rz := -half * 0.62
		add.call("RearHip." + s, "Hips", Vector3(rx * 0.8, hip_h - 0.03, rz + 0.04))
		add.call("RearUpper." + s, "RearHip." + s, Vector3(rx, hip_h - 0.12, rz - 0.02))
		add.call("RearLower." + s, "RearUpper." + s, Vector3(rx * 1.05, hip_h * 0.62, rz + 0.16))
		add.call("RearAnkle." + s, "RearLower." + s, Vector3(rx * 1.05, hip_h * 0.28, rz - 0.10))
		add.call("RearFoot." + s, "RearAnkle." + s, Vector3(rx * 1.05, 0.045, rz - 0.02))
		add.call("RearToe." + s, "RearFoot." + s, Vector3(rx * 1.05, 0.02, rz + 0.14))
	return bones

const BONE_RADIUS := {
	"Hips": 0.34, "Spine": 0.36, "Chest": 0.38, "Neck": 0.22, "Head": 0.26, "Jaw": 0.18, "HeadEnd": 0.16,
	"Tail": 0.14,
	"FrontShoulder": 0.20, "FrontUpper": 0.15, "FrontLower": 0.13, "FrontAnkle": 0.11, "FrontFoot": 0.11, "FrontToe": 0.10,
	"RearHip": 0.22, "RearUpper": 0.18, "RearLower": 0.15, "RearAnkle": 0.12, "RearFoot": 0.12, "RearToe": 0.10,
}

static func skinning_segments(bones: Array, scale: float) -> Array:
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
		var kids: Array = children.get(name, [])
		var tip := a
		if kids.is_empty():
			var parent_pos: Vector3 = bones[int(index_of[b["parent"]])]["pos"]
			tip = a + (a - parent_pos).normalized() * 0.08
		else:
			var sum := Vector3.ZERO
			for k in kids:
				sum += k["pos"]
			tip = sum / float(kids.size())
		var base := name.split(".")[0]
		var radius := 0.16
		for key in BONE_RADIUS.keys():
			if base.begins_with(key):
				radius = float(BONE_RADIUS[key])
				break
		segments.append(Skinning.segment(i, a, tip, radius * scale, 2.2, 1.3 if base.begins_with("Jaw") else 1.0))
	return segments

# ---------------------------------------------------------------- geometry --

static func _pos_map(bones: Array) -> Dictionary:
	var map := {}
	for b in bones:
		map[b["name"]] = b["pos"]
	return map

static func body(bones: Array, p: Dictionary) -> Array:
	var m := _pos_map(bones)
	var g := float(p["girth"])
	var control := PackedVector3Array([
		m["Tail1"],
		m["Hips"],
		m["Spine1"],
		m["Spine2"],
		m["Chest"],
		m["Neck1"],
		m["Neck2"],
		m["Head"],
	])
	var keys := [
		[0.00, g * 0.55, g * 0.55, 2.30],   # tail root
		[0.14, g * 0.92, g * 0.86, 2.35],   # haunches
		[0.34, g * 0.86, g * 0.90, 2.25],   # lumbar
		[0.52, g * 0.94, g * 1.02, 2.35],   # ribcage
		[0.68, g * 1.00, g * 1.06, 2.45],   # chest
		[0.80, g * 0.56, g * 0.60, 2.25],   # neck base
		[0.92, g * 0.44, g * 0.48, 2.20],   # neck
		[1.00, g * 0.46, g * 0.50, 2.20],   # skull base
	]
	var a := MeshLib.tube(control, keys, 32, 6, PackedFloat32Array(), true, false, 1.4)

	# scapulae, haunch muscle, ribs, sunken flank
	a = Sculpt.blob(a, m["Chest"] + Vector3(g * 0.75, 0.06, -0.02), Vector3(g * 0.55, g * 0.70, g * 0.75), g * 0.14, Vector3(1, 0.2, 0).normalized(), 1.1, true)
	a = Sculpt.blob(a, m["Hips"] + Vector3(g * 0.70, 0.02, -0.02), Vector3(g * 0.60, g * 0.75, g * 0.80), g * 0.16, Vector3(1, 0, 0), 1.1, true)
	a = Sculpt.blob(a, (m["Spine1"] + m["Spine2"]) * 0.5 + Vector3(0, -g * 0.5, 0), Vector3(g * 1.1, g * 0.55, g * 1.4), -g * 0.12, Vector3.ZERO, 1.2)
	for i in 5:
		var t := 0.35 + float(i) * 0.09
		var rib := (m["Spine2"] as Vector3).lerp(m["Chest"], t - 0.35) + Vector3(g * 0.85, -g * 0.15, 0)
		a = Sculpt.crease(a, rib, Vector3(0, 0, 1), 0.022, g * 0.05, rib, Vector3(g * 0.5, g * 0.9, 0.05))

	# dorsal crest of spines
	var crest := float(p["crest"])
	if crest > 0.001:
		for i in 7:
			var t := float(i) / 6.0
			var base: Vector3 = (m["Hips"] as Vector3).lerp(m["Neck1"], t)
			var height := crest * sin(PI * clampf(t * 1.1, 0.0, 1.0)) + crest * 0.35
			a = Sculpt.blob(a, base + Vector3(0, g * 0.9 + height * 0.4, 0),
				Vector3(crest * 0.5, height, crest * 0.9), height * 0.9, Vector3(0, 1, -0.25).normalized(), 1.4)
	return a

static func head(bones: Array, p: Dictionary) -> Array:
	var m := _pos_map(bones)
	var origin: Vector3 = m["Head"]
	var size := float(p["head_size"])
	var jaw := float(p["jaw_length"])

	var skull := Sculpt.uv_sphere(Vector3(size * 0.52, size * 0.50, size * 0.66), 26, 34)
	skull = Sculpt.project_uv_spherical(skull, Vector3.ZERO)
	var a := Sculpt.merge(MeshLib.empty_arrays(), skull, Transform3D(Basis(), origin))

	# muzzle: pulled forward and tapered
	a = Sculpt.blob(a, origin + Vector3(0, -size * 0.10, size * 0.55), Vector3(size * 0.42, size * 0.40, size * 0.55), jaw * 0.95, Vector3(0, -0.12, 1).normalized(), 1.0)
	a = Sculpt.scale_region(a, origin + Vector3(0, -size * 0.08, size * 0.55 + jaw * 0.5), Vector3(size * 0.6, size * 0.6, jaw), Vector3(0.68, 0.72, 1.0), 0.9)
	# brow ridge and sunken eye pits
	a = Sculpt.blob(a, origin + Vector3(size * 0.30, size * 0.20, size * 0.34), Vector3(size * 0.30, size * 0.20, size * 0.30), size * 0.10, Vector3(0.3, 0.6, 0.6).normalized(), 1.2, true)
	a = Sculpt.blob(a, origin + Vector3(size * 0.34, size * 0.05, size * 0.32), Vector3(size * 0.22, size * 0.20, size * 0.24), -size * 0.11, Vector3.ZERO, 1.3, true)
	# cheek / jaw muscle
	a = Sculpt.blob(a, origin + Vector3(size * 0.36, -size * 0.16, size * 0.10), Vector3(size * 0.30, size * 0.30, size * 0.36), size * 0.10, Vector3(1, -0.2, 0).normalized(), 1.1, true)
	# occipital shelf
	a = Sculpt.blob(a, origin + Vector3(0, size * 0.24, -size * 0.42), Vector3(size * 0.50, size * 0.26, size * 0.30), size * 0.14, Vector3(0, 0.6, -1).normalized(), 1.1)
	# lower jaw as its own volume so the Jaw bone can open it
	var mandible := MeshLib.tube(
		PackedVector3Array([
			origin + Vector3(0, -size * 0.30, -size * 0.10),
			origin + Vector3(0, -size * 0.34, size * 0.30),
			origin + Vector3(0, -size * 0.32, size * 0.55 + jaw * 0.55),
			origin + Vector3(0, -size * 0.28, size * 0.55 + jaw * 0.95),
		]),
		[
			[0.00, size * 0.34, size * 0.22, 2.4],
			[0.45, size * 0.28, size * 0.18, 2.3],
			[0.85, size * 0.16, size * 0.13, 2.3],
			[1.00, size * 0.10, size * 0.09, 2.3],
		], 18, 5, PackedFloat32Array(), true, true, 3.0)
	a = Sculpt.merge(a, mandible)

	# teeth: two rows of small cones fused into the jaws
	var tooth_count := 7
	for i in tooth_count:
		var t := float(i) / float(tooth_count - 1)
		var z := size * 0.30 + jaw * 0.75 * t
		var x := size * (0.26 - 0.12 * t)
		var upper := origin + Vector3(x, -size * 0.24, z)
		var lower := origin + Vector3(x, -size * 0.30, z)
		var length := size * (0.16 if i < 2 else 0.10)
		a = Sculpt.blob(a, upper, Vector3(size * 0.07, length, size * 0.07), -length * 0.9, Vector3(0, -1, 0), 1.7, true)
		a = Sculpt.blob(a, lower, Vector3(size * 0.06, length * 0.8, size * 0.06), length * 0.75, Vector3(0, 1, 0), 1.7, true)

	# horns
	var horns := int(p["horns"])
	for i in horns:
		var side := 1.0 if i % 2 == 0 else -1.0
		var row := float(i / 2)
		var root := origin + Vector3(side * size * (0.30 + row * 0.08), size * (0.34 - row * 0.10), -size * (0.10 + row * 0.24))
		var tip := root + Vector3(side * size * 0.30, size * (0.55 - row * 0.14), -size * (0.30 + row * 0.10))
		var horn := MeshLib.tube(
			PackedVector3Array([root, root.lerp(tip, 0.45) + Vector3(0, size * 0.05, 0), tip]),
			[[0.0, size * 0.11, size * 0.11, 2.3], [0.5, size * 0.07, size * 0.07, 2.2], [1.0, size * 0.012, size * 0.012, 2.2]],
			12, 5, PackedFloat32Array(), true, true, 3.0)
		a = Sculpt.merge(a, horn)
	return a

static func limb(bones: Array, p: Dictionary, prefix: String, side: String) -> Array:
	var m := _pos_map(bones)
	var thickness := float(p["front_thickness"] if prefix.begins_with("Front") else p["rear_thickness"])
	var names := ["Shoulder", "Upper", "Lower", "Ankle", "Foot", "Toe"] if prefix.begins_with("Front") \
		else ["Hip", "Upper", "Lower", "Ankle", "Foot", "Toe"]
	var control := PackedVector3Array()
	for n in names:
		control.append(m["%s%s.%s" % [prefix, n, side]])
	var keys := [
		[0.00, thickness * 1.90, thickness * 1.90, 2.30],   # shoulder mass
		[0.20, thickness * 1.45, thickness * 1.50, 2.20],   # upper limb
		[0.42, thickness * 1.05, thickness * 1.15, 2.15],   # joint
		[0.62, thickness * 1.15, thickness * 1.20, 2.15],   # lower muscle
		[0.80, thickness * 0.70, thickness * 0.72, 2.15],   # ankle
		[0.92, thickness * 0.78, thickness * 0.80, 2.25],   # foot
		[1.00, thickness * 0.55, thickness * 0.58, 2.30],   # toe
	]
	var a := MeshLib.tube(control, keys, 20, 6, PackedFloat32Array(), true, true, 2.5)

	# joint caps hide the intersections with the torso and each other
	a = Sculpt.blob(a, control[0], Vector3(thickness * 2.3, thickness * 2.3, thickness * 2.3), thickness * 0.25, Vector3.ZERO, 1.1)
	a = Sculpt.blob(a, control[2], Vector3(thickness * 1.6, thickness * 1.6, thickness * 1.6), thickness * 0.16, Vector3.ZERO, 1.2)
	a = Sculpt.blob(a, control[3], Vector3(thickness * 1.3, thickness * 1.3, thickness * 1.3), thickness * 0.14, Vector3.ZERO, 1.2)

	# claws
	var toe: Vector3 = control[5]
	var ankle: Vector3 = control[4]
	var forward := (toe - ankle).normalized()
	for c in 3:
		var spread := (float(c) - 1.0) * thickness * 0.85
		var root := toe + Vector3(spread, thickness * 0.1, 0)
		var tip := root + forward * thickness * 1.5 + Vector3(0, -thickness * 0.45, 0)
		var claw := MeshLib.tube(
			PackedVector3Array([root, root.lerp(tip, 0.5) + Vector3(0, thickness * 0.08, 0), tip]),
			[[0.0, thickness * 0.30, thickness * 0.30, 2.2], [0.5, thickness * 0.20, thickness * 0.20, 2.1], [1.0, thickness * 0.03, thickness * 0.03, 2.1]],
			10, 4, PackedFloat32Array(), true, true, 4.0)
		a = Sculpt.merge(a, claw)
	return a

static func tail(bones: Array, p: Dictionary) -> Array:
	var m := _pos_map(bones)
	var segs := int(p["tail_segments"])
	var control := PackedVector3Array([m["Hips"]])
	for i in segs:
		control.append(m["Tail%d" % (i + 1)])
	var g := float(p["girth"])
	var keys := [
		[0.00, g * 0.60, g * 0.62, 2.30],
		[0.25, g * 0.42, g * 0.44, 2.20],
		[0.60, g * 0.24, g * 0.26, 2.15],
		[0.85, g * 0.12, g * 0.13, 2.15],
		[1.00, g * 0.03, g * 0.035, 2.15],
	]
	var a := MeshLib.tube(control, keys, 18, 6, PackedFloat32Array(), false, true, 2.0)
	# a row of small fins along the last third
	for i in 5:
		var t := 0.55 + float(i) * 0.10
		var idx := int(clampf(t * float(control.size() - 1), 0.0, float(control.size() - 1)))
		var at: Vector3 = control[idx]
		a = Sculpt.blob(a, at + Vector3(0, g * 0.20, 0), Vector3(g * 0.05, g * 0.20, g * 0.10), g * 0.16, Vector3(0, 1, 0), 1.4)
	return a

# ------------------------------------------------------------------- build --

static func build(kind: Kind, cfg: Dictionary = {}) -> Dictionary:
	var p: Dictionary = (PROFILES[kind] as Dictionary).duplicate()
	var seed_value := int(cfg.get("seed", 4242))
	var quality := float(cfg.get("quality", 1.0))
	var scale := float(p["scale"])

	var bones := bone_table(kind)
	var segments := skinning_segments(bones, 1.0)

	var flesh := body(bones, p)
	flesh = Sculpt.merge(flesh, tail(bones, p))
	flesh = Sculpt.merge(flesh, head(bones, p))
	for prefix in ["Front", "Rear"]:
		var left := limb(bones, p, prefix, "L")
		flesh = Sculpt.merge(flesh, left)
		flesh = Sculpt.merge(flesh, MeshLib.mirror_x(left))

	if quality > 0.85:
		flesh = MeshLib.subdivide(flesh)
		flesh = MeshLib.relax(flesh, 1, 0.24)
	flesh = Sculpt.project_uv_spherical(flesh, Vector3(0, float(p["shoulder_height"]) * 0.6, 0), 3.0)
	# two displacement octaves: broad lumps of muscle, then hide-scale grain
	flesh = MeshLib.displace(flesh, MeshLib.make_noise(seed_value, 6.5, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.5), 0.012)
	flesh = MeshLib.displace(flesh, MeshLib.ridged_noise(seed_value + 3, 26.0, 4), 0.004)
	flesh = MeshLib.bake_cavity(flesh, 1.0, 0.06)
	flesh = MeshLib.with_tangents(flesh)

	# The core is a separate emissive volume floating inside the ribcage — the
	# weak point the player aims for.
	var m := _pos_map(bones)
	var core_center: Vector3 = (m["Chest"] as Vector3).lerp(m["Spine2"], 0.4) + Vector3(0, -float(p["girth"]) * 0.25, 0)
	var core := Sculpt.uv_sphere(Vector3(0.10, 0.10, 0.10) * scale, 16, 22)
	core = Sculpt.project_uv_spherical(core, Vector3.ZERO)
	core = MeshLib.translate(core, core_center)
	# Glowing eyes on the skull front: without them a dark carapace head has no
	# readable facing at combat distance.
	var head_origin: Vector3 = m["Head"]
	var head_size := float(p["head_size"])
	for side in [1.0, -1.0]:
		var eye := Sculpt.uv_sphere(Vector3(head_size * 0.12, head_size * 0.10, head_size * 0.10), 10, 14)
		eye = Sculpt.project_uv_spherical(eye, Vector3.ZERO)
		core = Sculpt.merge(core, eye,
			Transform3D(Basis(), head_origin + Vector3(side * head_size * 0.315, head_size * 0.08, head_size * 0.44)))
	core = MeshLib.with_tangents(core)

	return {
		"kind": kind,
		"profile": p,
		"bones": bones,
		"segments": segments,
		"core_center": core_center,
		"groups": {"flesh": flesh, "core": core},
		"stats": {
			"flesh_tris": MeshLib.tri_count(flesh),
			"bones": bones.size(),
		},
	}

static func create_node(kind: Kind, cfg: Dictionary = {}) -> Node3D:
	var p: Dictionary = PROFILES[kind]
	var root := Node3D.new()
	root.name = "Monster%s" % p["name"]

	var bones := bone_table(kind)
	var skeleton := DigiHariMan.build_skeleton(bones)
	root.add_child(skeleton)

	var state := {"built": null}
	var meshes := {}
	for group in ["flesh", "core"]:
		var key := "monster_%s_%s" % [String(p["name"]).to_lower(), group]
		var mesh := BuildCache.mesh(key, func() -> Mesh:
			if state["built"] == null:
				state["built"] = build(kind, cfg)
			var built: Dictionary = state["built"]
			var arrays: Array = (built["groups"] as Dictionary)[group]
			var skinned := Skinning.skin_arrays(arrays, built["segments"])
			return Skinning.commit_skinned(skinned, null, group))
		if mesh != null:
			meshes[group] = mesh

	var skin_resource := skeleton.create_skin_from_rest_transforms()
	var materials := {
		"flesh": Materials.carapace(0.0),
		"core": Materials.energy(Materials.ORANGE_EMISSIVE, 14.0),
	}
	for group in meshes.keys():
		var mi := MeshInstance3D.new()
		mi.name = group.capitalize()
		mi.mesh = meshes[group]
		mi.skeleton = NodePath("..")
		mi.skin = skin_resource
		mi.material_override = materials[group]
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		mi.custom_aabb = AABB(Vector3(-3, -0.5, -3), Vector3(6, 4, 6))
		skeleton.add_child(mi)

	root.scale = Vector3.ONE * float(p["scale"])
	return root
