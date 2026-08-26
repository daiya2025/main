class_name DigiHariMan
extends RefCounted
## The hero: DIGIHARIMAN (デジハリマン).
##
## An anatomically generated human in a matte technical under-suit, plated with
## orange composite armour. The armour is lofted along the *same* control paths
## as the limbs underneath, so every plate conforms to the body instead of
## floating near it, and it is skinned with the same capsules — plates follow
## the bones without a separate attachment rig.

const CACHE_KEY := "digihariman"

# ------------------------------------------------------------------ armour --

## A closed plate wrapped around part of a limb path.
static func _wrap(control: PackedVector3Array, keys: Array, segments: int = 24, samples: int = 6, v_scale: float = 2.0) -> Array:
	return Humanoid.tube(control, keys, segments, samples, PackedFloat32Array(), true, true, v_scale)

static func chest_plate(b: float) -> Array:
	var control := PackedVector3Array([
		Vector3(0, 1.170, 0.010),
		Vector3(0, 1.240, 0.012),
		Vector3(0, 1.320, -0.002),
		Vector3(0, 1.398, -0.010),
		Vector3(0, 1.432, -0.012),
	])
	var keys := [
		[0.00, 0.158 * b, 0.124 * b, 2.45],
		[0.30, 0.174 * b, 0.136 * b, 2.60],
		[0.62, 0.185 * b, 0.141 * b, 2.75],
		[0.88, 0.188 * b, 0.130 * b, 2.90],
		[1.00, 0.162 * b, 0.112 * b, 2.70],
	]
	var a := _wrap(control, keys, 34, 6)
	# sternum ridge and pectoral shells
	a = Sculpt.blob(a, Vector3(0, 1.300, 0.150), Vector3(0.022, 0.110, 0.060), 0.012, Vector3(0, 0, 1), 1.4)
	a = Sculpt.blob(a, Vector3(0.082, 1.318, 0.126), Vector3(0.080, 0.070, 0.060), 0.014, Vector3(0, 0, 1), 1.1, true)
	a = Sculpt.crease(a, Vector3(0, 1.318, 0.150), Vector3(1, 0, 0), 0.012, 0.008,
		Vector3(0, 1.310, 0.140), Vector3(0.026, 0.080, 0.070))
	# collar ring and back vent
	a = Sculpt.blob(a, Vector3(0, 1.424, 0.030), Vector3(0.120, 0.030, 0.110), 0.010, Vector3(0, 1, 0), 1.2)
	a = Sculpt.blob(a, Vector3(0, 1.300, -0.140), Vector3(0.090, 0.080, 0.040), -0.008, Vector3.ZERO, 1.3)
	a = Sculpt.flatten_below(a, 1.170, 0.02)
	return a

static func pauldron(b: float) -> Array:
	# Left shoulder. A shell that sweeps from the collar out over the deltoid.
	var shell := Sculpt.uv_sphere(Vector3(0.092 * b, 0.082 * b, 0.096 * b), 22, 30)
	shell = Sculpt.project_uv_spherical(shell, Vector3.ZERO)
	var a := Sculpt.merge(Humanoid._empty(), shell, Transform3D(Basis(), Vector3(0.198, 1.408, 0.000)))
	a = Sculpt.scale_region(a, Vector3(0.198, 1.350, 0.0), Vector3(0.17, 0.10, 0.17), Vector3(1.0, 0.55, 1.0), 0.8)
	a = Sculpt.blob(a, Vector3(0.240, 1.388, 0.000), Vector3(0.062, 0.062, 0.075), 0.014, Vector3(1, -0.15, 0).normalized(), 1.1)
	# layered lames along the lower edge
	for i in 3:
		var y := 1.372 - float(i) * 0.024
		a = Sculpt.crease(a, Vector3(0.21, y, 0.0), Vector3(0, 1, 0), 0.007, 0.005,
			Vector3(0.212, y, 0.0), Vector3(0.11, 0.018, 0.11))
	a = Sculpt.flatten_below(a, 1.330, 0.02)
	return a

static func gauntlet(b: float) -> Array:
	var control := PackedVector3Array([
		Vector3(0.204, 1.100, -0.006),
		Vector3(0.208, 1.010, -0.002),
		Vector3(0.211, 0.930, 0.002),
		Vector3(0.214, 0.862, 0.006),
	])
	var keys := [
		[0.00, 0.072 * b, 0.070 * b, 2.60],
		[0.35, 0.068 * b, 0.066 * b, 2.55],
		[0.75, 0.052 * b, 0.048 * b, 2.50],
		[1.00, 0.046 * b, 0.042 * b, 2.55],
	]
	var a := _wrap(control, keys, 22, 6, 3.0)
	# dorsal ridge and a wrist emitter housing
	a = Sculpt.blob(a, Vector3(0.240, 1.010, 0.000), Vector3(0.030, 0.090, 0.045), 0.010, Vector3(1, 0, 0), 1.3)
	a = Sculpt.blob(a, Vector3(0.214, 0.905, 0.040), Vector3(0.045, 0.045, 0.030), 0.012, Vector3(0, 0, 1), 1.2)
	return a

static func thigh_guard(b: float) -> Array:
	var control := PackedVector3Array([
		Vector3(0.094, 0.905, 0.006),
		Vector3(0.096, 0.800, 0.010),
		Vector3(0.098, 0.690, 0.012),
		Vector3(0.099, 0.600, 0.012),
	])
	var keys := [
		[0.00, 0.116 * b, 0.116 * b, 2.55],
		[0.40, 0.107 * b, 0.109 * b, 2.50],
		[0.80, 0.094 * b, 0.098 * b, 2.45],
		[1.00, 0.086 * b, 0.090 * b, 2.45],
	]
	var a := _wrap(control, keys, 24, 6)
	a = Sculpt.blob(a, Vector3(0.098, 0.760, 0.100), Vector3(0.060, 0.100, 0.040), 0.010, Vector3(0, 0, 1), 1.2)
	a = Sculpt.crease(a, Vector3(0.098, 0.720, 0.100), Vector3(0, 1, 0), 0.008, 0.005,
		Vector3(0.098, 0.720, 0.080), Vector3(0.11, 0.020, 0.10))
	return a

static func shin_guard(b: float) -> Array:
	var control := PackedVector3Array([
		Vector3(0.100, 0.500, 0.010),
		Vector3(0.100, 0.400, 0.004),
		Vector3(0.100, 0.280, -0.004),
		Vector3(0.100, 0.170, -0.012),
	])
	var keys := [
		[0.00, 0.082 * b, 0.084 * b, 2.55],
		[0.30, 0.086 * b, 0.088 * b, 2.50],
		[0.75, 0.063 * b, 0.067 * b, 2.45],
		[1.00, 0.056 * b, 0.060 * b, 2.45],
	]
	var a := _wrap(control, keys, 22, 6)
	a = Sculpt.blob(a, Vector3(0.100, 0.500, 0.070), Vector3(0.055, 0.050, 0.040), 0.012, Vector3(0, 0.3, 1).normalized(), 1.2)  # knee cop
	a = Sculpt.blob(a, Vector3(0.088, 0.330, 0.060), Vector3(0.020, 0.140, 0.030), 0.006, Vector3(0, 0, 1), 1.4)                 # tibia ridge
	return a

static func boot() -> Array:
	var block := Sculpt.rounded_box(Vector3(0.118, 0.115, 0.278), 0.034, 3)
	block = Sculpt.project_uv_spherical(block, Vector3.ZERO)
	var a := Sculpt.merge(Humanoid._empty(), block, Transform3D(Basis(), Vector3(0.100, 0.072, 0.026)))
	a = Sculpt.blob(a, Vector3(0.100, 0.130, -0.010), Vector3(0.065, 0.055, 0.085), 0.014, Vector3(0, 1, 0), 1.1)
	a = Sculpt.blob(a, Vector3(0.100, 0.075, -0.085), Vector3(0.060, 0.065, 0.055), 0.012, Vector3(0, 0, -1), 1.1)
	a = Sculpt.scale_region(a, Vector3(0.100, 0.050, 0.140), Vector3(0.10, 0.07, 0.08), Vector3(0.92, 0.66, 1.0), 1.0)
	# sole slab
	a = Sculpt.blob(a, Vector3(0.100, 0.020, 0.020), Vector3(0.075, 0.030, 0.150), 0.008, Vector3(0, -1, 0), 1.2)
	a = Sculpt.flatten_below(a, 0.008, 0.024)
	return a

static func belt(b: float) -> Array:
	var control := PackedVector3Array([
		Vector3(0, 0.955, 0.004),
		Vector3(0, 0.990, 0.006),
		Vector3(0, 1.028, 0.008),
	])
	var keys := [
		[0.00, 0.163 * b, 0.130 * b, 2.60],
		[0.5, 0.168 * b, 0.135 * b, 2.65],
		[1.00, 0.159 * b, 0.126 * b, 2.60],
	]
	var a := _wrap(control, keys, 30, 6, 3.0)
	a = Sculpt.blob(a, Vector3(0, 0.992, 0.150), Vector3(0.055, 0.040, 0.040), 0.016, Vector3(0, 0, 1), 1.2)   # buckle
	a = Sculpt.blob(a, Vector3(0.150, 0.985, 0.050), Vector3(0.045, 0.040, 0.060), 0.010, Vector3(1, 0, 0.4).normalized(), 1.2, true)  # hip pods
	return a

static func backpack(b: float) -> Array:
	var core := Sculpt.rounded_box(Vector3(0.230 * b, 0.260 * b, 0.110 * b), 0.030, 3)
	core = Sculpt.project_uv_spherical(core, Vector3.ZERO)
	var a := Sculpt.merge(Humanoid._empty(), core, Transform3D(Basis(), Vector3(0, 1.300, -0.150)))
	# twin thruster housings
	for side in [1.0, -1.0]:
		var pod := Sculpt.uv_sphere(Vector3(0.048, 0.075, 0.048), 16, 20)
		pod = Sculpt.project_uv_spherical(pod, Vector3.ZERO)
		a = Sculpt.merge(a, pod, Transform3D(Basis(), Vector3(side * 0.105, 1.255, -0.195)))
	a = Sculpt.blob(a, Vector3(0, 1.395, -0.150), Vector3(0.110, 0.050, 0.070), 0.010, Vector3(0, 1, 0), 1.2)
	return a

static func helmet(b: float) -> Array:
	# Half-helm: crown, ear guards and a nape plate. The face stays open so the
	# sculpted head reads, which is the whole point of modelling one.
	var center := Humanoid.HEAD_CENTER
	var shell := Sculpt.uv_sphere(Vector3(0.089 * b, 0.110 * b, 0.113 * b), 30, 40)
	shell = Sculpt.project_uv_spherical(shell, Vector3.ZERO)
	var a := Sculpt.merge(Humanoid._empty(), shell, Transform3D(Basis(), center + Vector3(0, 0.006, -0.004)))
	# Cut the face opening and the neck hole out of the shell. These must be
	# real holes — a negative blob only dents a closed surface, which is how an
	# earlier revision ended up with the sculpted face sealed inside the helmet.
	a = Sculpt.remove_region(a, center + Vector3(0, -0.012, 0.112), Vector3(0.068, 0.082, 0.052))
	a = Sculpt.remove_region(a, center + Vector3(0, -0.118, 0.005), Vector3(0.062, 0.045, 0.070))
	# Roll the cut edge slightly inward so it reads as a rimmed opening rather
	# than a paper-thin shell.
	a = Sculpt.blob(a, center + Vector3(0, -0.010, 0.100), Vector3(0.075, 0.090, 0.045), -0.006, Vector3.ZERO, 1.4)
	# crest and ear guards
	a = Sculpt.blob(a, center + Vector3(0, 0.098, -0.010), Vector3(0.022, 0.045, 0.120), 0.018, Vector3(0, 1, 0), 1.3)
	a = Sculpt.blob(a, center + Vector3(0.086, -0.012, -0.020), Vector3(0.035, 0.055, 0.055), 0.014, Vector3(1, 0, 0), 1.2, true)
	# nape plate
	a = Sculpt.blob(a, center + Vector3(0, -0.070, -0.090), Vector3(0.075, 0.055, 0.055), 0.014, Vector3(0, -0.4, -1).normalized(), 1.1)
	return a

static func visor() -> Array:
	# The face marker: a bold band across the brow, proud of the helmet. Big
	# enough to read at gameplay distance — this is how you tell the front.
	var center := Humanoid.HEAD_CENTER
	var band := Sculpt.uv_sphere(Vector3(0.090, 0.026, 0.080), 14, 34)
	band = Sculpt.project_uv_spherical(band, Vector3.ZERO)
	var a := Sculpt.merge(Humanoid._empty(), band, Transform3D(Basis(), center + Vector3(0, 0.050, 0.054)))
	a = Sculpt.remove_region(a, center + Vector3(0, 0.050, -0.048), Vector3(0.12, 0.06, 0.080))
	return a

static func chest_emblem() -> Array:
	# The DIGIHARI core: a glowing lens set into the sternum.
	var lens := Sculpt.uv_sphere(Vector3(0.062, 0.062, 0.034), 16, 26)
	lens = Sculpt.project_uv_spherical(lens, Vector3.ZERO)
	# Proud of the chest plate (which reaches ~z 0.16 over the sternum ridge).
	return Sculpt.merge(Humanoid._empty(), lens, Transform3D(Basis(), Vector3(0, 1.300, 0.176)))

## Twin thruster lenses on the backpack: the glowing pair that says "this is
## the back", mirroring the visor's "this is the front".
static func thrusters() -> Array:
	var a := Humanoid._empty()
	for side in [1.0, -1.0]:
		var lens := Sculpt.uv_sphere(Vector3(0.036, 0.048, 0.022), 14, 20)
		lens = Sculpt.project_uv_spherical(lens, Vector3.ZERO)
		a = Sculpt.merge(a, lens, Transform3D(Basis(), Vector3(side * 0.105, 1.255, -0.248)))
	return a

# ------------------------------------------------------------------- build --

## Generates every mesh group. Returns a Dictionary of arrays keyed by
## material group, plus the bone table and skinning capsules.
static func build(cfg: Dictionary = {}) -> Dictionary:
	var b := float(cfg.get("build", 1.06))
	var figure := Humanoid.build(cfg)
	var bones: Array = figure["bones"]
	var segments: Array = figure["segments"]

	var left_pieces := [pauldron(b), gauntlet(b), thigh_guard(b), shin_guard(b), boot()]
	var armour := chest_plate(b)
	for piece in left_pieces:
		armour = Sculpt.merge(armour, piece)
		armour = Sculpt.merge(armour, Humanoid.mirror_x(piece))
	armour = Sculpt.merge(armour, belt(b))
	armour = Sculpt.merge(armour, backpack(b))
	armour = Sculpt.merge(armour, helmet(b))
	armour = Sculpt.project_uv_spherical(armour, Vector3(0, 1.2, 0), 3.0)
	armour = MeshLib.relax(armour, 1, 0.16)
	armour = MeshLib.displace(armour, MeshLib.make_noise(int(cfg.get("seed", 1)) + 41, 55.0, 3), 0.0009)
	armour = MeshLib.bake_cavity(armour, 1.0, 0.04)
	armour = MeshLib.with_tangents(armour)

	var trim := chest_emblem()
	trim = Sculpt.merge(trim, thrusters())
	trim = Sculpt.project_uv_spherical(trim, Vector3(0, 1.4, 0), 3.0)
	trim = MeshLib.bake_cavity(trim, 0.8, 0.03)
	trim = MeshLib.with_tangents(trim)

	var visor_band := visor()
	visor_band = Sculpt.project_uv_spherical(visor_band, Humanoid.HEAD_CENTER, 3.0)
	visor_band = MeshLib.with_tangents(visor_band)

	return {
		"bones": bones,
		"segments": segments,
		"groups": {
			"body": figure["body"],
			"skin": figure["skin"],
			"eyes": figure["eyes"],
			"armor": armour,
			"trim": trim,
			"visor": visor_band,
		},
		"stats": {
			"body_tris": MeshLib.tri_count(figure["body"]),
			"skin_tris": MeshLib.tri_count(figure["skin"]),
			"armor_tris": MeshLib.tri_count(armour),
			"trim_tris": MeshLib.tri_count(trim),
			"visor_tris": MeshLib.tri_count(visor_band),
			"bones": bones.size(),
		},
	}

## Instantiates the finished character: Skeleton3D + one MeshInstance3D per
## material group, all skinned to the same rig.
static func create_node(cfg: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "DigiHariMan"

	var bones: Array = Humanoid.bone_table()
	var skeleton := build_skeleton(bones)
	root.add_child(skeleton)

	# Shared box so the (by-value captured) lambda can memoise the expensive
	# sculpt across all five material groups.
	var state := {"built": null}
	var groups := {}
	var cache_ok := true
	for group in ["body", "skin", "eyes", "armor", "trim", "visor"]:
		var key := "%s_%s" % [CACHE_KEY, group]
		var mesh := BuildCache.mesh(key, func() -> Mesh:
			if state["built"] == null:
				state["built"] = build(cfg)
			var built: Dictionary = state["built"]
			var segments: Array = built["segments"]
			var arrays: Array = (built["groups"] as Dictionary)[group]
			var skinned := Skinning.skin_arrays(arrays, segments)
			return Skinning.commit_skinned(skinned, null, group))
		if mesh == null:
			cache_ok = false
			continue
		groups[group] = mesh

	if not cache_ok:
		push_warning("DigiHariMan: one or more mesh groups failed to build.")

	var materials := {
		"body": Materials.suit(0.55),
		"skin": Materials.skin(),
		"eyes": Materials.eye(),
		"armor": Materials.armor("primary"),
		"trim": Materials.energy(Materials.ORANGE_EMISSIVE, 9.0),
		"visor": Materials.energy(Materials.VISOR_COLOR, 13.0),
	}

	var skin_resource := skeleton.create_skin_from_rest_transforms()
	for group in groups.keys():
		var mi := MeshInstance3D.new()
		mi.name = group.capitalize()
		mi.mesh = groups[group]
		mi.skeleton = NodePath("..")
		mi.skin = skin_resource
		mi.material_override = materials[group]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		# A generous custom AABB stops the character popping out of view when
		# animation pushes vertices past the rest-pose bounds.
		mi.custom_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 2.6, 2.4))
		skeleton.add_child(mi)

	return root

static func build_skeleton(bones: Array) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	var index_of := {}
	for i in bones.size():
		var b: Dictionary = bones[i]
		skeleton.add_bone(String(b["name"]))
		index_of[b["name"]] = i
	for i in bones.size():
		var b: Dictionary = bones[i]
		var parent: String = b["parent"]
		if not parent.is_empty():
			skeleton.set_bone_parent(i, int(index_of[parent]))
	# Rest transforms are pure translations relative to the parent: every bone
	# shares the character's axes, which keeps the procedural animation maths
	# free of per-bone correction matrices.
	for i in bones.size():
		var b: Dictionary = bones[i]
		var pos: Vector3 = b["pos"]
		var parent: String = b["parent"]
		var local := pos
		if not parent.is_empty():
			local = pos - (bones[int(index_of[parent])]["pos"] as Vector3)
		skeleton.set_bone_rest(i, Transform3D(Basis(), local))
		skeleton.set_bone_pose_position(i, local)
		skeleton.set_bone_pose_rotation(i, Quaternion.IDENTITY)
		skeleton.set_bone_pose_scale(i, Vector3.ONE)
	return skeleton
