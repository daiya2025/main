class_name Flora
extends RefCounted
## Vegetation and rock generation.
##
## When the Poly Haven bridge has downloaded photoscans, the scatter system uses
## those meshes directly. These generators are the fallback so the world is
## never empty, and they are built to the same silhouette rules: trunks taper
## and lean, branches split at plausible angles, and rocks are eroded rather
## than bumpy spheres.

## Recursive branching tree. Returns { wood: arrays, canopy: arrays }.
static func tree(rng: RandomNumberGenerator, height: float = 7.0) -> Dictionary:
	var wood := MeshLib.empty_arrays()
	var canopy := MeshLib.empty_arrays()
	var trunk_radius := height * rng.randf_range(0.035, 0.055)
	_branch(rng, wood, canopy, Vector3.ZERO, Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12)).normalized(),
		height * 0.42, trunk_radius, 0, 4)

	wood = MeshLib.displace(wood, MeshLib.ridged_noise(int(rng.randi()), 18.0, 4), 0.012)
	wood = MeshLib.bake_cavity(wood, 1.0, 0.05)
	wood = Sculpt.project_uv_spherical(wood, Vector3(0, height * 0.4, 0), 4.0)
	wood = MeshLib.with_tangents(wood)

	canopy = MeshLib.displace(canopy, MeshLib.make_noise(int(rng.randi()), 2.2, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.6), 0.30)
	canopy = MeshLib.bake_cavity(canopy, 1.0, 0.25)
	canopy = Sculpt.project_uv_spherical(canopy, Vector3(0, height * 0.75, 0), 2.0)
	canopy = MeshLib.with_tangents(canopy)
	return {"wood": wood, "canopy": canopy}

static func _branch(rng: RandomNumberGenerator, wood: Array, canopy: Array,
		origin: Vector3, direction: Vector3, length: float, radius: float, depth: int, max_depth: int) -> void:
	if depth > max_depth or length < 0.18 or radius < 0.012:
		return
	# A branch bows: the tip lags behind the base direction under its own weight.
	var mid := origin + direction * length * 0.5 + Vector3(0, -length * 0.04 * float(depth), 0)
	var tip := origin + direction * length + Vector3(0, -length * 0.09 * float(depth), 0)
	var control := PackedVector3Array([origin, mid, tip])
	var tip_radius: float = radius * (0.55 if depth < max_depth else 0.25)
	var segments: int = maxi(6, 14 - depth * 2)
	var section := MeshLib.tube(control,
		[[0.0, radius, radius, 2.1], [0.5, radius * 0.78, radius * 0.78, 2.05], [1.0, tip_radius, tip_radius, 2.0]],
		segments, 4, PackedFloat32Array(), depth == 0, false, 3.0)
	# root flare on the trunk
	if depth == 0:
		for i in 5:
			var angle := TAU * float(i) / 5.0 + rng.randf() * 0.5
			section = Sculpt.blob(section, Vector3(cos(angle) * radius * 0.9, 0.06, sin(angle) * radius * 0.9),
				Vector3(radius * 0.9, 0.35, radius * 0.9), radius * 0.35, Vector3(cos(angle), -0.3, sin(angle)).normalized(), 1.3)
	var merged := Sculpt.merge(wood, section)
	wood.clear()
	wood.append_array(merged)

	if depth == max_depth:
		var blob := Sculpt.uv_sphere(Vector3(length * 1.5, length * 1.05, length * 1.5), 12, 16)
		blob = Sculpt.project_uv_spherical(blob, Vector3.ZERO)
		var leaf := Sculpt.merge(canopy, blob, Transform3D(Basis(), tip + direction * length * 0.35))
		canopy.clear()
		canopy.append_array(leaf)
		return

	var children := rng.randi_range(2, 3)
	for i in children:
		var yaw := TAU * (float(i) / float(children)) + rng.randf_range(-0.5, 0.5)
		var pitch := rng.randf_range(0.35, 0.75)
		var side := Vector3(cos(yaw), 0, sin(yaw))
		var next_dir := (direction * cos(pitch) + side * sin(pitch)).normalized()
		var start := origin + direction * length * rng.randf_range(0.72, 0.98)
		_branch(rng, wood, canopy, start, next_dir,
			length * rng.randf_range(0.58, 0.76), radius * rng.randf_range(0.52, 0.68), depth + 1, max_depth)

## An eroded boulder: an ellipsoid pushed around by ridged noise, then
## flat-bottomed so it sits on the ground instead of hovering.
static func rock(rng: RandomNumberGenerator, size: float = 1.0) -> Array:
	var radii := Vector3(
		size * rng.randf_range(0.8, 1.3),
		size * rng.randf_range(0.55, 0.95),
		size * rng.randf_range(0.8, 1.3))
	var a := Sculpt.uv_sphere(radii, 22, 30)
	# large-scale facets first, then erosion, then fine grain
	for i in 4:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized()
		a = Sculpt.blob(a, dir * size * 0.7, Vector3.ONE * size * rng.randf_range(0.6, 1.1),
			-size * rng.randf_range(0.06, 0.16), Vector3.ZERO, rng.randf_range(0.7, 1.4))
	a = MeshLib.subdivide(a)
	a = MeshLib.relax(a, 1, 0.2)
	a = MeshLib.displace(a, MeshLib.ridged_noise(int(rng.randi()), 1.6 / maxf(size, 0.2), 5), size * 0.11)
	a = MeshLib.displace(a, MeshLib.make_noise(int(rng.randi()), 9.0 / maxf(size, 0.2), 3), size * 0.02)
	a = Sculpt.flatten_below(a, -radii.y * 0.62, size * 0.18)
	a = Sculpt.project_uv_spherical(a, Vector3.ZERO, 1.0)
	a = MeshLib.bake_cavity(a, 1.0, size * 0.14)
	return MeshLib.with_tangents(a)

## Low grass / fern tuft built from crossed blades — used as ground cover in the
## scatter system where a full scanned plant would be overkill.
static func tuft(rng: RandomNumberGenerator, blades: int = 7, height: float = 0.45) -> Array:
	var a := MeshLib.empty_arrays()
	for i in blades:
		var yaw := TAU * rng.randf()
		var lean := rng.randf_range(0.15, 0.5)
		var h := height * rng.randf_range(0.6, 1.25)
		var dir := Vector3(cos(yaw) * lean, 1.0, sin(yaw) * lean).normalized()
		var base := Vector3(cos(yaw) * 0.06, 0.0, sin(yaw) * 0.06) * rng.randf_range(0.2, 1.0)
		var blade := MeshLib.tube(
			PackedVector3Array([base, base + dir * h * 0.5, base + dir * h + Vector3(0, -h * 0.18, 0)]),
			[[0.0, 0.018, 0.004, 1.6], [0.5, 0.013, 0.003, 1.6], [1.0, 0.001, 0.001, 1.6]],
			5, 3, PackedFloat32Array(), true, true, 4.0)
		a = Sculpt.merge(a, blade)
	a = Sculpt.project_uv_spherical(a, Vector3(0, height * 0.4, 0), 2.0)
	return MeshLib.with_tangents(a)
