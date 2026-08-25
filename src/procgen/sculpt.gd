class_name Sculpt
extends RefCounted
## Field-based mesh sculpting.
##
## Faces, muscles and creature anatomy are built the way a sculptor blocks them
## in: start from a smooth primitive, then push/pull with soft-falloff brushes.
## Every operation here works on `Mesh.ARRAY_*` arrays and composes with
## MeshLib.subdivide / relax / displace.

## Smooth falloff (smoothstep) of a point inside an ellipsoid brush.
## Returns 1.0 at the centre, 0.0 at or beyond the boundary.
static func falloff(p: Vector3, center: Vector3, radii: Vector3, hardness: float = 1.0) -> float:
	var d := Vector3(
		(p.x - center.x) / maxf(radii.x, 0.0001),
		(p.y - center.y) / maxf(radii.y, 0.0001),
		(p.z - center.z) / maxf(radii.z, 0.0001))
	var t := d.length()
	if t >= 1.0:
		return 0.0
	var s := 1.0 - t
	# smoothstep, then hardness biases the profile towards the centre
	s = s * s * (3.0 - 2.0 * s)
	return pow(s, maxf(hardness, 0.01))

## Push vertices inside an ellipsoid brush along `direction`, or along their own
## normal when `direction` is zero. Negative `amount` carves inwards.
static func blob(arrays: Array, center: Vector3, radii: Vector3, amount: float,
		direction: Vector3 = Vector3.ZERO, hardness: float = 1.0, symmetric_x: bool = false) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != verts.size():
		arrays = MeshLib.recompute_normals(arrays)
		normals = arrays[Mesh.ARRAY_NORMAL]
	var use_normal := direction.length_squared() < 0.000001
	var dir := direction.normalized() if not use_normal else Vector3.ZERO
	var mirrored := Vector3(-center.x, center.y, center.z)
	for i in verts.size():
		var p: Vector3 = verts[i]
		var w := falloff(p, center, radii, hardness)
		if symmetric_x:
			w = maxf(w, falloff(p, mirrored, radii, hardness))
		if w <= 0.0:
			continue
		var push := (normals[i] if use_normal else dir)
		if symmetric_x and not use_normal and p.x < 0.0:
			push = Vector3(-dir.x, dir.y, dir.z)
		verts[i] = p + push * (amount * w)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = null
	return MeshLib.recompute_normals(out)

## Scales the region inside a brush around its centre — widens a jaw, tapers a
## waist, fattens a muscle belly.
static func scale_region(arrays: Array, center: Vector3, radii: Vector3, factor: Vector3,
		hardness: float = 1.0, symmetric_x: bool = false) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var mirrored := Vector3(-center.x, center.y, center.z)
	for i in verts.size():
		var p: Vector3 = verts[i]
		var w := falloff(p, center, radii, hardness)
		var c := center
		if symmetric_x:
			var wm := falloff(p, mirrored, radii, hardness)
			if wm > w:
				w = wm
				c = mirrored
		if w <= 0.0:
			continue
		var rel := p - c
		var scaled := Vector3(rel.x * factor.x, rel.y * factor.y, rel.z * factor.z)
		verts[i] = c + rel.lerp(scaled, w)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = null
	return MeshLib.recompute_normals(out)

## Carves a soft crease along a plane — eyelid folds, lips, armour panel lines.
static func crease(arrays: Array, point: Vector3, normal: Vector3, width: float, depth: float,
		limit_center: Vector3 = Vector3.INF, limit_radii: Vector3 = Vector3.ONE) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != verts.size():
		arrays = MeshLib.recompute_normals(arrays)
		normals = arrays[Mesh.ARRAY_NORMAL]
	var n := normal.normalized()
	var limited := limit_center.x != INF
	for i in verts.size():
		var p: Vector3 = verts[i]
		var dist := absf((p - point).dot(n))
		if dist > width:
			continue
		var w := 1.0 - dist / width
		w = w * w * (3.0 - 2.0 * w)
		if limited:
			w *= falloff(p, limit_center, limit_radii, 1.0)
		if w <= 0.0:
			continue
		verts[i] = p - normals[i] * depth * w
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = null
	return MeshLib.recompute_normals(out)

## Bends the mesh around an axis, angle growing with height — used for spine
## curvature and creature tails without re-lofting.
static func bend(arrays: Array, axis: Vector3, pivot: Vector3, angle_per_unit: float, from_height: float = -INF) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var a := axis.normalized()
	for i in verts.size():
		var p: Vector3 = verts[i]
		if p.y < from_height:
			continue
		var h := p.y - pivot.y
		var angle := angle_per_unit * h
		if is_zero_approx(angle):
			continue
		var rel := p - pivot
		verts[i] = pivot + rel.rotated(a, angle)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = null
	return MeshLib.recompute_normals(out)

## Twists around the Y axis proportionally to height.
static func twist(arrays: Array, pivot: Vector3, radians_per_unit: float) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var p: Vector3 = verts[i]
		var rel := p - pivot
		verts[i] = pivot + rel.rotated(Vector3.UP, radians_per_unit * rel.y)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = null
	return MeshLib.recompute_normals(out)

## Flattens everything below `y` onto the plane — gives feet and bases a
## contact surface instead of a rounded blob.
static func flatten_below(arrays: Array, y: float, blend: float = 0.06) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var p: Vector3 = verts[i]
		if p.y < y + blend:
			var t := clampf((y + blend - p.y) / maxf(blend, 0.0001), 0.0, 1.0)
			verts[i] = Vector3(p.x, lerpf(p.y, maxf(p.y, y), t), p.z)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = null
	return MeshLib.recompute_normals(out)

## A UV sphere with poles on +Y/-Y, the starting point for heads and eyes.
static func uv_sphere(radius: Vector3, rings: int, segments: int) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for r in range(rings + 1):
		var v := float(r) / float(rings)
		var phi := v * PI
		var row := PackedVector3Array()
		for s in range(segments):
			var u := float(s) / float(segments)
			var theta := u * TAU
			row.append(Vector3(
				sin(phi) * cos(theta) * radius.x,
				cos(phi) * radius.y,
				sin(phi) * sin(theta) * radius.z))
		grid.append(row)
	for r in range(rings):
		var a: PackedVector3Array = grid[r]
		var b: PackedVector3Array = grid[r + 1]
		var v0 := float(r) / float(rings)
		var v1 := float(r + 1) / float(rings)
		for s in range(segments):
			var s1 := (s + 1) % segments
			var u0 := float(s) / float(segments)
			var u1 := float(s + 1) / float(segments)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(a[s])
			st.set_uv(Vector2(u0, v1)); st.add_vertex(b[s])
			st.set_uv(Vector2(u1, v0)); st.add_vertex(a[s1])
			st.set_uv(Vector2(u1, v0)); st.add_vertex(a[s1])
			st.set_uv(Vector2(u0, v1)); st.add_vertex(b[s])
			st.set_uv(Vector2(u1, v1)); st.add_vertex(b[s1])
	st.generate_normals()
	st.index()
	var mesh: ArrayMesh = st.commit()
	return MeshLib.weld(mesh.surface_get_arrays(0), 0.0005)

## Rounded box — armour plates, crates, building blocks with a believable
## fillet instead of razor edges (razor edges are the #1 tell of a placeholder).
static func rounded_box(size: Vector3, radius: float, steps: int = 3) -> Array:
	var half := size * 0.5
	var r := minf(radius, minf(half.x, minf(half.y, half.z)) * 0.95)
	var inner := half - Vector3(r, r, r)
	var rings := steps * 4 + 2
	var segments := steps * 8
	var arrays := uv_sphere(Vector3(r, r, r), rings, segments)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var p: Vector3 = verts[i]
		verts[i] = p + Vector3(
			signf(p.x) * inner.x if absf(p.x) > 0.0001 else 0.0,
			signf(p.y) * inner.y if absf(p.y) > 0.0001 else 0.0,
			signf(p.z) * inner.z if absf(p.z) > 0.0001 else 0.0)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	return MeshLib.recompute_normals(arrays)

## Concatenates two array-meshes (optionally transforming the second).
static func merge(a: Array, b: Array, xform: Transform3D = Transform3D.IDENTITY) -> Array:
	var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ai: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var au := PackedVector2Array()
	if a[Mesh.ARRAY_TEX_UV] != null:
		au = a[Mesh.ARRAY_TEX_UV]
	var bv: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
	var bi: PackedInt32Array = b[Mesh.ARRAY_INDEX]
	var bu := PackedVector2Array()
	if b[Mesh.ARRAY_TEX_UV] != null:
		bu = b[Mesh.ARRAY_TEX_UV]
	var offset := av.size()
	var verts := PackedVector3Array(av)
	for p in bv:
		verts.append(xform * p)
	var idx := PackedInt32Array(ai)
	for i in bi:
		idx.append(i + offset)
	var uvs := PackedVector2Array(au)
	var has_uv := au.size() == av.size() and bu.size() == bv.size()
	if has_uv:
		uvs.append_array(bu)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_INDEX] = idx
	out[Mesh.ARRAY_TEX_UV] = uvs if has_uv else null
	return MeshLib.recompute_normals(out)

## Spherical UV projection — good enough for heads and creature bodies where a
## proper unwrap would be overkill and triplanar shading does the heavy lifting.
static func project_uv_spherical(arrays: Array, center: Vector3, v_scale: float = 1.0) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	for i in verts.size():
		var d := (verts[i] - center).normalized()
		uvs[i] = Vector2(
			(atan2(d.z, d.x) / TAU) + 0.5,
			(acos(clampf(d.y, -1.0, 1.0)) / PI) * v_scale)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_TEX_UV] = uvs
	return out
