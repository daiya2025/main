class_name Skinning
extends RefCounted
## Automatic bone-weight solving for procedurally generated bodies.
##
## Each bone contributes a smooth falloff around its own segment; the four
## strongest contributors per vertex are kept and normalised, which is exactly
## what a GPU skinning pipeline expects. It behaves like a simplified
## "bone glow" bind and holds up well because our meshes are generated *around*
## these very segments in the first place.

const MAX_INFLUENCES := 4

## A capsule of influence. `index` is the Skeleton3D bone index.
static func segment(index: int, a: Vector3, b: Vector3, radius: float, sharpness: float = 2.0, gain: float = 1.0) -> Dictionary:
	return {"index": index, "a": a, "b": b, "radius": radius, "sharpness": sharpness, "gain": gain}

static func _distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Returns {"bones": PackedInt32Array, "weights": PackedFloat32Array}, four
## entries per vertex, ready for Mesh.ARRAY_BONES / ARRAY_WEIGHTS.
static func solve(verts: PackedVector3Array, segments: Array) -> Dictionary:
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(verts.size() * MAX_INFLUENCES)
	weights.resize(verts.size() * MAX_INFLUENCES)

	for v in verts.size():
		var p: Vector3 = verts[v]
		var best_idx := [0, 0, 0, 0]
		var best_w := [0.0, 0.0, 0.0, 0.0]
		var nearest_bone := 0
		var nearest_dist := INF

		for seg in segments:
			var d := _distance_to_segment(p, seg["a"], seg["b"])
			if d < nearest_dist:
				nearest_dist = d
				nearest_bone = int(seg["index"])
			var radius := float(seg["radius"])
			if d >= radius:
				continue
			var w: float = pow(1.0 - d / radius, float(seg["sharpness"])) * float(seg["gain"])
			if w <= 0.0001:
				continue
			# insertion into the running top-4
			for slot in MAX_INFLUENCES:
				if w > best_w[slot]:
					for shift in range(MAX_INFLUENCES - 1, slot, -1):
						best_w[shift] = best_w[shift - 1]
						best_idx[shift] = best_idx[shift - 1]
					best_w[slot] = w
					best_idx[slot] = int(seg["index"])
					break

		var total: float = best_w[0] + best_w[1] + best_w[2] + best_w[3]
		var base := v * MAX_INFLUENCES
		if total <= 0.00001:
			# outside every capsule: rigid-bind to the closest bone
			bones[base] = nearest_bone
			weights[base] = 1.0
			for slot in range(1, MAX_INFLUENCES):
				bones[base + slot] = nearest_bone
				weights[base + slot] = 0.0
		else:
			for slot in MAX_INFLUENCES:
				bones[base + slot] = best_idx[slot]
				weights[base + slot] = best_w[slot] / total
	return {"bones": bones, "weights": weights}

## Attaches solved weights to an array-mesh and returns a skinned ArrayMesh.
static func skin_arrays(arrays: Array, segments: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var solved := solve(verts, segments)
	var out := arrays.duplicate()
	out[Mesh.ARRAY_BONES] = solved["bones"]
	out[Mesh.ARRAY_WEIGHTS] = solved["weights"]
	return out

## Builds an ArrayMesh whose surface carries 4-bone skinning data.
static func commit_skinned(arrays: Array, material: Material, surface_name: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var flags := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_INDEX
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		flags |= Mesh.ARRAY_FORMAT_TEX_UV
	if arrays[Mesh.ARRAY_COLOR] != null:
		flags |= Mesh.ARRAY_FORMAT_COLOR
	if arrays[Mesh.ARRAY_TANGENT] != null:
		flags |= Mesh.ARRAY_FORMAT_TANGENT
	if arrays[Mesh.ARRAY_BONES] != null:
		flags |= Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	if material != null:
		mesh.surface_set_material(0, material)
	mesh.surface_set_name(0, surface_name)
	mesh.resource_name = surface_name
	return mesh
