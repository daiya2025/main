class_name HeadBuilder
extends RefCounted
## Sculpts a human head.
##
## Model space: origin at the head's centre of mass, character faces +Z,
## +X is the character's left. Dimensions follow adult male averages
## (skull ≈ 195 mm tall, 155 mm wide, 200 mm deep) so the proportions read as
## human before a single texture is applied.

const SKULL := Vector3(0.077, 0.098, 0.100)

## `quality` scales the base tessellation: 1.0 -> ~19k tris after subdivision.
static func build(rng_seed: int = 7, quality: float = 1.0) -> Dictionary:
	var rings := int(clampf(40.0 * quality, 16.0, 96.0))
	var segments := int(clampf(56.0 * quality, 24.0, 128.0))
	var head := Sculpt.uv_sphere(SKULL, rings, segments)

	# Densify BEFORE sculpting: at the base tessellation the vertex spacing
	# (~8 mm) is the same order as the features themselves, so a brush peak
	# rarely lands on a vertex and every form comes out blunted.
	head = MeshLib.subdivide(head)

	head = _cranium(head)
	head = _face_planes(head)
	head = _brow_and_eyes(head)
	head = _nose(head)
	head = _mouth_and_chin(head)
	head = _ears(head)
	head = _neck_socket(head)

	# Light relaxation only: Laplacian smoothing eats exactly the
	# centimetre-scale features a face is made of (an earlier 2 x 0.32 pass
	# reduced the whole sculpt to a potato).
	head = MeshLib.relax(head, 1, 0.12)
	head = Sculpt.project_uv_spherical(head, Vector3(0, 0, -0.01))
	var pores := MeshLib.make_noise(rng_seed + 31, 90.0, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.55)
	head = MeshLib.displace(head, pores, 0.0006)
	var wrinkles := MeshLib.ridged_noise(rng_seed + 77, 26.0, 3)
	head = MeshLib.displace(head, wrinkles, 0.0004)
	head = MeshLib.bake_cavity(head, 0.85, 0.02)
	head = MeshLib.with_tangents(head)

	return {
		"head": head,
		"eyes": _eyes(),
		"eye_positions": [Vector3(0.0315, 0.012, 0.072), Vector3(-0.0315, 0.012, 0.072)],
	}

# --------------------------------------------------------------------------

static func _cranium(a: Array) -> Array:
	# Real skulls are not spheres: the occiput projects backwards, the crown is
	# flatter than an ellipsoid, and the temples pinch in above the ears.
	a = Sculpt.scale_region(a, Vector3(0, 0.055, -0.02), Vector3(0.13, 0.10, 0.15), Vector3(0.97, 0.94, 1.05), 1.0)
	a = Sculpt.blob(a, Vector3(0, 0.012, -0.088), Vector3(0.085, 0.095, 0.075), 0.009, Vector3(0, 0, -1), 1.2)
	a = Sculpt.blob(a, Vector3(0.070, 0.048, 0.010), Vector3(0.045, 0.055, 0.070), -0.006, Vector3.ZERO, 1.4, true)
	a = Sculpt.blob(a, Vector3(0, 0.096, 0.010), Vector3(0.075, 0.045, 0.085), -0.004, Vector3.ZERO, 1.0)
	return a

static func _face_planes(a: Array) -> Array:
	# Flatten the face plane, then re-establish the cheekbone and the
	# zygomatic-to-jaw transition that gives a head its structure.
	a = Sculpt.blob(a, Vector3(0, -0.005, 0.098), Vector3(0.085, 0.105, 0.055), -0.010, Vector3(0, 0, 1), 0.8)
	a = Sculpt.blob(a, Vector3(0.055, 0.005, 0.062), Vector3(0.044, 0.038, 0.050), 0.015, Vector3.ZERO, 1.3, true)
	a = Sculpt.scale_region(a, Vector3(0, -0.062, 0.020), Vector3(0.115, 0.062, 0.125), Vector3(0.86, 1.0, 0.94), 0.9)
	a = Sculpt.blob(a, Vector3(0.050, -0.055, 0.045), Vector3(0.040, 0.040, 0.055), 0.005, Vector3.ZERO, 1.2, true)
	# temple / masseter hollow keeps the cheek from reading as inflated
	a = Sculpt.blob(a, Vector3(0.048, -0.030, 0.052), Vector3(0.030, 0.032, 0.038), -0.0045, Vector3.ZERO, 1.5, true)
	return a

static func _brow_and_eyes(a: Array) -> Array:
	a = Sculpt.blob(a, Vector3(0.030, 0.036, 0.082), Vector3(0.042, 0.026, 0.044), 0.014, Vector3(0, 0.25, 1), 1.1, true)
	a = Sculpt.blob(a, Vector3(0, 0.040, 0.090), Vector3(0.018, 0.020, 0.035), 0.0030, Vector3(0, 0, 1), 1.4)   # glabella
	# eye socket: carve, then rebuild the lids around the eyeball
	a = Sculpt.blob(a, Vector3(0.0315, 0.014, 0.076), Vector3(0.031, 0.025, 0.038), -0.024, Vector3.ZERO, 1.25, true)
	a = Sculpt.blob(a, Vector3(0.0315, 0.028, 0.080), Vector3(0.028, 0.012, 0.030), 0.009, Vector3(0, 0, 1), 1.6, true)  # upper lid
	a = Sculpt.blob(a, Vector3(0.0315, -0.002, 0.079), Vector3(0.027, 0.010, 0.028), 0.007, Vector3(0, 0, 1), 1.6, true) # lower lid
	a = Sculpt.crease(a, Vector3(0.0315, 0.021, 0.082), Vector3(0, 1, -0.35).normalized(), 0.0055, 0.0022,
		Vector3(0.0315, 0.021, 0.082), Vector3(0.034, 0.020, 0.030))
	return a

static func _nose(a: Array) -> Array:
	a = Sculpt.blob(a, Vector3(0, 0.020, 0.092), Vector3(0.017, 0.032, 0.032), 0.018, Vector3(0, 0, 1), 1.3)   # bridge
	a = Sculpt.blob(a, Vector3(0, -0.008, 0.098), Vector3(0.020, 0.028, 0.032), 0.034, Vector3(0, -0.1, 1), 1.2) # dorsum
	a = Sculpt.blob(a, Vector3(0, -0.024, 0.104), Vector3(0.018, 0.017, 0.028), 0.020, Vector3(0, -0.2, 1), 1.5) # tip
	a = Sculpt.blob(a, Vector3(0.014, -0.028, 0.096), Vector3(0.013, 0.013, 0.020), 0.013, Vector3(0.4, -0.2, 1).normalized(), 1.4, true) # alae
	a = Sculpt.blob(a, Vector3(0.011, -0.033, 0.098), Vector3(0.007, 0.007, 0.012), -0.005, Vector3.ZERO, 1.8, true)     # nostril
	a = Sculpt.crease(a, Vector3(0.019, -0.030, 0.092), Vector3(1, 0.2, -0.2).normalized(), 0.006, 0.0022,
		Vector3(0.019, -0.030, 0.092), Vector3(0.016, 0.018, 0.022))
	return a

static func _mouth_and_chin(a: Array) -> Array:
	a = Sculpt.blob(a, Vector3(0, -0.048, 0.090), Vector3(0.037, 0.022, 0.032), 0.011, Vector3(0, 0, 1), 1.2)  # muzzle mass
	a = Sculpt.crease(a, Vector3(0, -0.050, 0.095), Vector3(0, 1, 0.15).normalized(), 0.0048, 0.0075,
		Vector3(0, -0.050, 0.095), Vector3(0.038, 0.014, 0.028))                                                # lip line
	a = Sculpt.blob(a, Vector3(0, -0.043, 0.094), Vector3(0.026, 0.010, 0.023), 0.0075, Vector3(0, 0.15, 1), 1.5) # upper lip
	a = Sculpt.blob(a, Vector3(0, -0.058, 0.093), Vector3(0.024, 0.011, 0.023), 0.008, Vector3(0, -0.15, 1), 1.5) # lower lip
	a = Sculpt.blob(a, Vector3(0, -0.036, 0.093), Vector3(0.006, 0.010, 0.014), -0.0022, Vector3.ZERO, 1.6)      # philtrum
	a = Sculpt.blob(a, Vector3(0, -0.070, 0.086), Vector3(0.020, 0.014, 0.026), -0.006, Vector3.ZERO, 1.3)      # mentolabial sulcus
	a = Sculpt.blob(a, Vector3(0, -0.083, 0.078), Vector3(0.029, 0.026, 0.038), 0.016, Vector3(0, -0.2, 1), 1.1) # chin
	a = Sculpt.blob(a, Vector3(0.058, -0.072, 0.030), Vector3(0.032, 0.032, 0.052), 0.010, Vector3(0.5, -0.4, 0.5).normalized(), 1.2, true) # jaw angle
	return a

static func _ears(a: Array) -> Array:
	# Ears are separate volumes fused into the skull: helix ring, concha bowl,
	# lobe. Small, but their absence is instantly readable as "not a person".
	for side in [1.0, -1.0]:
		var root := Vector3(side * 0.074, -0.008, -0.018)
		a = Sculpt.blob(a, root, Vector3(0.021, 0.042, 0.025), 0.024, Vector3(side, 0, -0.2).normalized(), 1.0)
		a = Sculpt.blob(a, root + Vector3(side * 0.006, 0.018, 0.002), Vector3(0.015, 0.019, 0.017), 0.011, Vector3(side, 0.3, 0).normalized(), 1.3)
		a = Sculpt.blob(a, root + Vector3(side * 0.006, -0.026, 0.004), Vector3(0.013, 0.015, 0.015), 0.009, Vector3(side, -0.3, 0).normalized(), 1.3)
		a = Sculpt.blob(a, root + Vector3(side * 0.010, -0.002, 0.006), Vector3(0.011, 0.017, 0.013), -0.011, Vector3.ZERO, 1.6)
	return a

static func _neck_socket(a: Array) -> Array:
	# Open the bottom of the skull so the neck loft fuses without a seam bulge.
	a = Sculpt.scale_region(a, Vector3(0, -0.098, -0.010), Vector3(0.090, 0.040, 0.100), Vector3(0.80, 1.0, 0.82), 0.9)
	return a

static func _eyes() -> Array:
	# A single mesh holding both eyeballs, shaded with the cornea shader.
	var left := Sculpt.uv_sphere(Vector3(0.0125, 0.0125, 0.0125), 20, 26)
	left = Sculpt.project_uv_spherical(left, Vector3.ZERO)
	var right := left.duplicate(true)
	var merged := Sculpt.merge(
		_offset(left, Vector3(0.0315, 0.012, 0.0765)),
		_offset(right, Vector3(-0.0315, 0.012, 0.0765)))
	return MeshLib.with_tangents(merged)

static func _offset(arrays: Array, delta: Vector3) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = verts[i] + delta
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	return out
