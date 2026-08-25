class_name MeshLib
extends RefCounted
## Low-level procedural modelling toolkit.
##
## The whole art pipeline of this project is code: bodies, creatures and
## buildings are lofted from cross-sections, subdivided, relaxed and then
## detail-displaced with noise — the same order of operations a modeller would
## use in a DCC package. Everything here works on raw `Mesh.ARRAY_*` arrays so
## the stages compose.

const ARRAY_COUNT := Mesh.ARRAY_MAX

# --------------------------------------------------------------- profiles --

## A closed cross-section ring in the XZ plane. `n` shapes the silhouette:
## 2.0 = ellipse, >2 = boxier (armour plates), <2 = pinched (fins, blades).
static func superellipse_ring(rx: float, rz: float, segments: int, n: float = 2.0) -> PackedVector3Array:
	var ring := PackedVector3Array()
	ring.resize(segments)
	var e := 2.0 / maxf(n, 0.05)
	for i in segments:
		var t := TAU * float(i) / float(segments)
		var c := cos(t)
		var s := sin(t)
		var x := signf(c) * pow(absf(c), e) * rx
		var z := signf(s) * pow(absf(s), e) * rz
		ring[i] = Vector3(x, 0.0, z)
	return ring

## Ring whose radius is modulated per-angle by `lobes` — used for muscle bellies,
## rib cages and knuckles where a plain ellipse reads as a balloon.
static func lobed_ring(rx: float, rz: float, segments: int, lobes: PackedFloat32Array, n: float = 2.0) -> PackedVector3Array:
	var ring := superellipse_ring(rx, rz, segments, n)
	if lobes.is_empty():
		return ring
	for i in segments:
		var t := float(i) / float(segments)
		var lobe := _sample_loop(lobes, t)
		ring[i] = ring[i] * lobe
	return ring

static func _sample_loop(values: PackedFloat32Array, t: float) -> float:
	var count := values.size()
	if count == 0:
		return 1.0
	var f := fposmod(t, 1.0) * float(count)
	var i0 := int(floor(f)) % count
	var i1 := (i0 + 1) % count
	return lerpf(values[i0], values[i1], f - floor(f))

# ------------------------------------------------------------------ curves --

## Centripetal Catmull-Rom resampling — gives limbs and spines a natural,
## overshoot-free curve through the control points.
static func catmull_rom(points: PackedVector3Array, samples_per_segment: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := points.size()
	if n < 2:
		return points
	for i in range(n - 1):
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, n - 1)]
		var steps := samples_per_segment if i < n - 2 else samples_per_segment + 1
		for s in steps:
			var t := float(s) / float(samples_per_segment)
			out.append(_catmull_point(p0, p1, p2, p3, t))
	return out

static func _catmull_point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

## Rotation-minimising frames (double-reflection method). Without these, lofted
## limbs twist visibly wherever the spine curves.
static func rmf_frames(path: PackedVector3Array, initial_up: Vector3 = Vector3.UP) -> Array[Basis]:
	var frames: Array[Basis] = []
	var n := path.size()
	if n < 2:
		return frames
	var tangent := (path[1] - path[0]).normalized()
	var ref := initial_up
	if absf(ref.dot(tangent)) > 0.98:
		ref = Vector3.FORWARD
	var normal := (ref - tangent * ref.dot(tangent)).normalized()
	var binormal := tangent.cross(normal).normalized()
	frames.append(Basis(binormal, tangent, normal))
	for i in range(1, n):
		var prev: Vector3 = path[i - 1]
		var cur: Vector3 = path[i]
		var next_t: Vector3 = (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		if next_t.length_squared() < 0.0001:
			next_t = tangent
		var v1 := cur - prev
		var c1 := v1.length_squared()
		var n_l := normal
		var t_l := tangent
		if c1 > 0.000001:
			n_l = normal - v1 * (2.0 / c1) * v1.dot(normal)
			t_l = tangent - v1 * (2.0 / c1) * v1.dot(tangent)
		var v2 := next_t - t_l
		var c2 := v2.length_squared()
		var n_next := n_l
		if c2 > 0.000001:
			n_next = n_l - v2 * (2.0 / c2) * v2.dot(n_l)
		normal = n_next.normalized()
		tangent = next_t
		binormal = tangent.cross(normal).normalized()
		normal = binormal.cross(tangent).normalized()
		frames.append(Basis(binormal, tangent, normal))
	return frames

# ----------------------------------------------------------------- lofting --

## Places a ring (authored in the XZ plane) onto a frame along a path.
static func place_ring(ring: PackedVector3Array, origin: Vector3, frame: Basis, scale_xz: Vector2 = Vector2.ONE) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(ring.size())
	for i in ring.size():
		var p: Vector3 = ring[i]
		var local := frame.x * (p.x * scale_xz.x) + frame.z * (p.z * scale_xz.y)
		out[i] = origin + local
	return out

## Stitches an ordered list of equal-length rings into a triangle strip tube.
## `v_coords` supplies the V texture coordinate per ring (arc length works best).
static func stitch(
		st: SurfaceTool,
		rings: Array,
		v_coords: PackedFloat32Array,
		u_repeat: float = 1.0,
		smooth_group: int = 0,
		bones: Array = [],
		weights: Array = []) -> void:
	if rings.size() < 2:
		return
	var seg: int = (rings[0] as PackedVector3Array).size()
	for r in range(rings.size() - 1):
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		var va: float = v_coords[r] if r < v_coords.size() else float(r)
		var vb: float = v_coords[r + 1] if r + 1 < v_coords.size() else float(r + 1)
		for i in seg:
			var j := (i + 1) % seg
			var u0 := u_repeat * float(i) / float(seg)
			var u1 := u_repeat * float(i + 1) / float(seg)
			_tri(st, a[i], a[j], b[i], Vector2(u0, va), Vector2(u1, va), Vector2(u0, vb), smooth_group,
				_bw(bones, r, i), _bw(weights, r, i), _bw(bones, r, j), _bw(weights, r, j), _bw(bones, r + 1, i), _bw(weights, r + 1, i))
			_tri(st, a[j], b[j], b[i], Vector2(u1, va), Vector2(u1, vb), Vector2(u0, vb), smooth_group,
				_bw(bones, r, j), _bw(weights, r, j), _bw(bones, r + 1, j), _bw(weights, r + 1, j), _bw(bones, r + 1, i), _bw(weights, r + 1, i))

static func _bw(table: Array, ring_index: int, _vert_index: int) -> Variant:
	if table.is_empty() or ring_index >= table.size():
		return null
	return table[ring_index]

static func _tri(
		st: SurfaceTool,
		p0: Vector3, p1: Vector3, p2: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2,
		smooth_group: int,
		b0: Variant = null, w0: Variant = null,
		b1: Variant = null, w1: Variant = null,
		b2: Variant = null, w2: Variant = null) -> void:
	st.set_smooth_group(smooth_group)
	_vert(st, p0, uv0, b0, w0)
	_vert(st, p1, uv1, b1, w1)
	_vert(st, p2, uv2, b2, w2)

static func _vert(st: SurfaceTool, p: Vector3, uv: Vector2, b: Variant, w: Variant) -> void:
	if b != null and w != null:
		st.set_bones(b)
		st.set_weights(w)
	st.set_uv(uv)
	st.add_vertex(p)

## Closes a ring with a triangle fan to `apex` (used for finger tips, horns...).
static func cap_ring(st: SurfaceTool, ring: PackedVector3Array, apex: Vector3, v: float, flip: bool, smooth_group: int = 0, bone: Variant = null, weight: Variant = null) -> void:
	var seg := ring.size()
	for i in seg:
		var j := (i + 1) % seg
		var u0 := float(i) / float(seg)
		var u1 := float(i + 1) / float(seg)
		if flip:
			_tri(st, ring[j], ring[i], apex, Vector2(u1, v), Vector2(u0, v), Vector2(0.5, v), smooth_group, bone, weight, bone, weight, bone, weight)
		else:
			_tri(st, ring[i], ring[j], apex, Vector2(u0, v), Vector2(u1, v), Vector2(0.5, v), smooth_group, bone, weight, bone, weight, bone, weight)

# ------------------------------------------------- array-level mesh surgery --

static func arrays_from_mesh(mesh: Mesh, surface: int = 0) -> Array:
	return mesh.surface_get_arrays(surface)

## 1-to-4 midpoint subdivision with shared edge points. Combined with
## `relax()` this approximates Loop subdivision closely enough for organic
## shapes while staying fast enough to run at load time.
static func subdivide(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	var has_uv := uvs.size() == verts.size()
	if idx.is_empty():
		return arrays

	# Plain Arrays (reference semantics) while we grow, packed again at the end.
	var out_verts: Array = []
	out_verts.assign(verts)
	var out_uvs: Array = []
	if has_uv:
		out_uvs.assign(uvs)
	var new_idx := PackedInt32Array()
	var edge_cache := {}
	var tri_count := idx.size() / 3

	for t in tri_count:
		var c0 := idx[t * 3 + 0]
		var c1 := idx[t * 3 + 1]
		var c2 := idx[t * 3 + 2]
		var corner := [c0, c1, c2]
		var mids := [0, 0, 0]
		for e in 3:
			var a: int = corner[e]
			var b: int = corner[(e + 1) % 3]
			var key: int = (mini(a, b) << 32) | maxi(a, b)
			if edge_cache.has(key):
				mids[e] = edge_cache[key]
				continue
			var vi := out_verts.size()
			out_verts.append((verts[a] + verts[b]) * 0.5)
			if has_uv:
				out_uvs.append((uvs[a] + uvs[b]) * 0.5)
			edge_cache[key] = vi
			mids[e] = vi
		new_idx.append_array([c0, mids[0], mids[2]])
		new_idx.append_array([mids[0], c1, mids[1]])
		new_idx.append_array([mids[2], mids[1], c2])
		new_idx.append_array([mids[0], mids[1], mids[2]])

	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = PackedVector3Array(out_verts)
	out[Mesh.ARRAY_INDEX] = new_idx
	out[Mesh.ARRAY_TEX_UV] = PackedVector2Array(out_uvs) if has_uv else null
	out[Mesh.ARRAY_NORMAL] = null
	out[Mesh.ARRAY_TANGENT] = null
	# Per-vertex data we cannot interpolate generically is dropped here; skinned
	# meshes are therefore subdivided before weights are assigned.
	out[Mesh.ARRAY_BONES] = null
	out[Mesh.ARRAY_WEIGHTS] = null
	out[Mesh.ARRAY_COLOR] = null
	return out

## Laplacian relaxation with a boundary-preserving weight. `strength` 0..1.
static func relax(arrays: Array, iterations: int = 1, strength: float = 0.5) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.is_empty() or verts.is_empty():
		return arrays
	var neighbours := _build_adjacency(verts.size(), idx)
	for _it in iterations:
		var next := PackedVector3Array(verts)
		for v in verts.size():
			var links: Array = neighbours[v]
			if links.size() < 3:
				continue
			var sum := Vector3.ZERO
			for l in links:
				sum += verts[int(l)]
			var avg := sum / float(links.size())
			next[v] = verts[v].lerp(avg, strength)
		verts = next
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_TANGENT] = null
	return recompute_normals(out)

static func _build_adjacency(vertex_count: int, idx: PackedInt32Array) -> Array:
	var adj: Array = []
	adj.resize(vertex_count)
	for i in vertex_count:
		adj[i] = []
	var tri_count := idx.size() / 3
	for t in tri_count:
		for e in 3:
			var a := idx[t * 3 + e]
			var b := idx[t * 3 + (e + 1) % 3]
			var la: Array = adj[a]
			if not la.has(b):
				la.append(b)
			var lb: Array = adj[b]
			if not lb.has(a):
				lb.append(a)
	return adj

## Pushes vertices along their normals by fBm noise — pores, muscle striation,
## rock erosion. `mask` is an optional Callable(Vector3 pos, Vector3 nrm) -> float.
static func displace(arrays: Array, noise: FastNoiseLite, amount: float, mask: Callable = Callable()) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != verts.size():
		arrays = recompute_normals(arrays)
		normals = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		var p: Vector3 = verts[i]
		var n: Vector3 = normals[i]
		var d := noise.get_noise_3d(p.x, p.y, p.z) * amount
		if mask.is_valid():
			d *= float(mask.call(p, n))
		verts[i] = p + n * d
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = null
	out[Mesh.ARRAY_TANGENT] = null
	return recompute_normals(out)

## Area-weighted smooth normals (angle weighting would cost more than it buys
## at these densities).
static func recompute_normals(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.ZERO)
	var tri_count := idx.size() / 3
	for t in tri_count:
		var i0 := idx[t * 3 + 0]
		var i1 := idx[t * 3 + 1]
		var i2 := idx[t * 3 + 2]
		var face := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		normals[i0] += face
		normals[i1] += face
		normals[i2] += face
	for i in normals.size():
		var n: Vector3 = normals[i]
		normals[i] = n.normalized() if n.length_squared() > 0.000001 else Vector3.UP
	var out := arrays.duplicate()
	out[Mesh.ARRAY_NORMAL] = normals
	return out

## Merges vertices closer than `epsilon`, so lofted seams shade smoothly.
static func weld(arrays: Array, epsilon: float = 0.0008) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	var has_uv := uvs.size() == verts.size()
	if idx.is_empty():
		return arrays
	var inv := 1.0 / maxf(epsilon, 0.00001)
	var lookup := {}
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	var new_verts := PackedVector3Array()
	var new_uvs := PackedVector2Array()
	for i in verts.size():
		var p: Vector3 = verts[i]
		var key := "%d_%d_%d" % [roundi(p.x * inv), roundi(p.y * inv), roundi(p.z * inv)]
		if lookup.has(key):
			remap[i] = lookup[key]
		else:
			var ni := new_verts.size()
			lookup[key] = ni
			remap[i] = ni
			new_verts.append(p)
			if has_uv:
				new_uvs.append(uvs[i])
	var new_idx := PackedInt32Array()
	var tri_count := idx.size() / 3
	for t in tri_count:
		var a := remap[idx[t * 3 + 0]]
		var b := remap[idx[t * 3 + 1]]
		var c := remap[idx[t * 3 + 2]]
		if a == b or b == c or a == c:
			continue
		new_idx.append_array([a, b, c])
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = new_verts
	out[Mesh.ARRAY_INDEX] = new_idx
	out[Mesh.ARRAY_TEX_UV] = new_uvs if has_uv else null
	out[Mesh.ARRAY_NORMAL] = null
	out[Mesh.ARRAY_TANGENT] = null
	out[Mesh.ARRAY_BONES] = null
	out[Mesh.ARRAY_WEIGHTS] = null
	out[Mesh.ARRAY_COLOR] = null
	return recompute_normals(out)

## Bakes ambient-occlusion-ish cavity into vertex colours. Cheap, and it stops
## procedural surfaces from reading as plastic before SSAO even kicks in.
static func bake_cavity(arrays: Array, strength: float = 0.6, radius: float = 0.12) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != verts.size():
		arrays = recompute_normals(arrays)
		normals = arrays[Mesh.ARRAY_NORMAL]
	var adj := _build_adjacency(verts.size(), idx)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in verts.size():
		var p: Vector3 = verts[i]
		var n: Vector3 = normals[i]
		var links: Array = adj[i]
		var concavity := 0.0
		for l in links:
			var d: Vector3 = verts[int(l)] - p
			var dist := d.length()
			if dist < 0.00001:
				continue
			concavity += clampf(-d.normalized().dot(n), -1.0, 1.0) * clampf(radius / dist, 0.0, 1.0)
		if links.size() > 0:
			concavity /= float(links.size())
		var ao := clampf(1.0 - maxf(concavity, 0.0) * strength * 2.0, 0.25, 1.0)
		colors[i] = Color(ao, ao, ao, 1.0)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_COLOR] = colors
	return out

# ---------------------------------------------------------------- assembly --

static func arrays_to_mesh(arrays: Array, material: Material = null, name: String = "") -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.create_from_arrays(arrays)
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	if material != null:
		mesh.surface_set_material(0, material)
	if not name.is_empty():
		mesh.resource_name = name
		mesh.surface_set_name(0, name)
	return mesh

## Adds an already-built mesh into a SurfaceTool, transformed. Used to bolt
## armour plates, rivets and greebles onto a base body.
static func append_mesh(st: SurfaceTool, mesh: Mesh, xform: Transform3D, surface: int = 0) -> void:
	st.append_from(mesh, surface, xform)

## Generates discrete LODs on an ArrayMesh through the importer's
## meshoptimizer path, and returns the mesh that carries them.
static func with_lods(mesh: ArrayMesh, material: Material = null, normal_merge_deg: float = 25.0) -> ArrayMesh:
	if not ClassDB.class_exists("ImporterMesh"):
		return mesh
	var importer := ImporterMesh.new()
	for s in mesh.get_surface_count():
		var mat: Material = material if material != null else mesh.surface_get_material(s)
		importer.add_surface(
			mesh.surface_get_primitive_type(s),
			mesh.surface_get_arrays(s),
			[],
			{},
			mat,
			mesh.surface_get_name(s),
			mesh.surface_get_format(s))
	importer.generate_lods(normal_merge_deg, 60.0, [])
	var built := importer.get_mesh()
	return built if built != null else mesh

## Same as with_lods() but reports how many LOD levels each surface got, so a
## test can assert the reduction actually happened rather than trusting it.
static func lod_levels(mesh: ArrayMesh, normal_merge_deg: float = 25.0) -> PackedInt32Array:
	var levels := PackedInt32Array()
	if not ClassDB.class_exists("ImporterMesh"):
		return levels
	var importer := ImporterMesh.new()
	for s in mesh.get_surface_count():
		importer.add_surface(
			mesh.surface_get_primitive_type(s),
			mesh.surface_get_arrays(s),
			[],
			{},
			mesh.surface_get_material(s),
			mesh.surface_get_name(s),
			mesh.surface_get_format(s))
	importer.generate_lods(normal_merge_deg, 60.0, [])
	for s in importer.get_surface_count():
		levels.append(importer.get_surface_lod_count(s))
	return levels

## Collision shape helpers -----------------------------------------------------

static func trimesh_body(mesh: Mesh, layer: int = 1, mask: int = 0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	body.collision_layer = layer
	body.collision_mask = mask
	return body

static func box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s

# ------------------------------------------------------------------ noise --

static func make_noise(seed_value: int, frequency: float, octaves: int = 4, type: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH, gain: float = 0.5) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = type
	n.frequency = frequency
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = 2.02
	return n

static func ridged_noise(seed_value: int, frequency: float, octaves: int = 5) -> FastNoiseLite:
	var n := make_noise(seed_value, frequency, octaves)
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	return n

## Runs the tangent generator over raw arrays (needs UVs + normals). Do this
## before attaching bone weights so nothing is lost in the round-trip.
static func with_tangents(arrays: Array) -> Array:
	if arrays[Mesh.ARRAY_TEX_UV] == null:
		return arrays
	if arrays[Mesh.ARRAY_NORMAL] == null:
		arrays = recompute_normals(arrays)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.create_from_arrays(arrays)
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return arrays
	var result := mesh.surface_get_arrays(0)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_TANGENT] = result[Mesh.ARRAY_TANGENT]
	return out

## Triangle count of an array-mesh, for build-time logging.
static func tri_count(arrays: Array) -> int:
	if arrays[Mesh.ARRAY_INDEX] == null:
		return 0
	return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


# ------------------------------------------------------------ loft helpers --

## An empty array-mesh, ready to merge into.
static func empty_arrays() -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	out[Mesh.ARRAY_INDEX] = PackedInt32Array()
	out[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	return out

## Linear-with-smoothstep interpolation of radius keys `[t, radius_x, radius_z,
## superellipse_n]`, returning Vector3(rx, rz, n).
static func sample_radius_keys(keys: Array, t: float) -> Vector3:
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

## Lofts a closed tube along `control`, resampled through Catmull-Rom and
## oriented with rotation-minimising frames. This is the workhorse behind every
## limb, torso, tail and armour plate in the project.
static func tube(control: PackedVector3Array, keys: Array, segments: int, samples_per_span: int,
		lobes: PackedFloat32Array = PackedFloat32Array(), cap_start: bool = true, cap_end: bool = true,
		v_scale: float = 1.0) -> Array:
	var path := catmull_rom(control, samples_per_span)
	var frames := rmf_frames(path, Vector3.FORWARD)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: Array = []
	var vs := PackedFloat32Array()
	var arc := 0.0
	for i in path.size():
		var t := float(i) / float(maxi(path.size() - 1, 1))
		var rk := sample_radius_keys(keys, t)
		var ring := lobed_ring(rk.x, rk.y, segments, lobes, rk.z)
		rings.append(place_ring(ring, path[i], frames[i]))
		if i > 0:
			arc += path[i].distance_to(path[i - 1])
		vs.append(arc * v_scale)
	stitch(st, rings, vs, 1.0, 0)
	if cap_start:
		cap_ring(st, rings[0], path[0] - (path[1] - path[0]).normalized() * 0.004, vs[0], true, 0)
	if cap_end:
		var last := rings.size() - 1
		cap_ring(st, rings[last], path[last] + (path[last] - path[last - 1]).normalized() * 0.004, vs[last], false, 0)
	st.generate_normals()
	st.index()
	var mesh: ArrayMesh = st.commit()
	return weld(mesh.surface_get_arrays(0), 0.0006)

## Mirrors across X and flips the winding so the copy is not inside-out.
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
	var tris := idx.size() / 3
	for t in tris:
		out_idx[t * 3 + 0] = idx[t * 3 + 0]
		out_idx[t * 3 + 1] = idx[t * 3 + 2]
		out_idx[t * 3 + 2] = idx[t * 3 + 1]
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = out_verts
	out[Mesh.ARRAY_INDEX] = out_idx
	out[Mesh.ARRAY_TANGENT] = null
	return recompute_normals(out)

## Translates every vertex.
static func translate(arrays: Array, delta: Vector3) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		moved[i] = verts[i] + delta
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = moved
	return out
