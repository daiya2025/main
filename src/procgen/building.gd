class_name Building
extends RefCounted
## Procedural architecture.
##
## A building is a stack of extruded tiers (a podium, a shaft, setbacks) rather
## than a single box, because the setback is what gives a skyline its shape.
## Wall UVs are authored in *metres* — U runs around the perimeter, V is height
## above the base — which is exactly what the facade shader needs to lay out
## floors and window bays at a consistent real-world size.

const FLOOR_HEIGHT := 3.4

enum Style { TOWER, BLOCK, PODIUM_TOWER, LOW_RISE }

## Returns { facade: arrays, detail: arrays, height: float, footprint: Vector2,
##           tiers: Array }.
##
## `tiers` may be supplied by the caller. Callers that cache the resulting mesh
## must do so, because the collision boxes are derived from the tiers and the
## two would otherwise drift apart the moment the mesh comes back from cache
## instead of being rebuilt.
static func build(rng: RandomNumberGenerator, style: Style, footprint: Vector2, floors: int,
		precomputed_tiers: Array = []) -> Dictionary:
	var tiers := precomputed_tiers if not precomputed_tiers.is_empty() else _plan_tiers(rng, style, footprint, floors)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := 0.0
	var detail := MeshLib.empty_arrays()
	var top_y := 0.0

	for i in tiers.size():
		var tier: Dictionary = tiers[i]
		var size: Vector3 = tier["size"]
		var base: float = tier["base"]
		var offset: Vector2 = tier["offset"]
		u = _tier_walls(st, offset, size, base, u)
		top_y = base + size.y
		# Cornice: a thin oversized slab capping each tier. Cheap geometry, and
		# it is what reads as "architecture" instead of "extruded rectangle".
		var cornice := Sculpt.rounded_box(Vector3(size.x + 0.55, 0.42, size.z + 0.55), 0.08, 2)
		cornice = Sculpt.project_uv_spherical(cornice, Vector3.ZERO)
		detail = Sculpt.merge(detail, cornice, Transform3D(Basis(), Vector3(offset.x, top_y - 0.10, offset.y)))
		if i == 0 and style != Style.LOW_RISE:
			# ground-floor canopy over the entrance side
			var canopy := Sculpt.rounded_box(Vector3(size.x * 0.55, 0.22, 1.6), 0.06, 2)
			canopy = Sculpt.project_uv_spherical(canopy, Vector3.ZERO)
			detail = Sculpt.merge(detail, canopy, Transform3D(Basis(), Vector3(offset.x, 4.2, offset.y + size.z * 0.5 + 0.7)))

	# Roof: a slab plus the mechanical clutter every real roof carries.
	var last: Dictionary = tiers[tiers.size() - 1]
	var roof_size: Vector3 = last["size"]
	var roof_offset: Vector2 = last["offset"]
	detail = Sculpt.merge(detail, _roof_kit(rng, roof_offset, roof_size, top_y))

	st.generate_normals()
	st.generate_tangents()
	st.index()
	var mesh: ArrayMesh = st.commit()
	var facade := mesh.surface_get_arrays(0)

	detail = MeshLib.bake_cavity(detail, 0.9, 0.10)
	detail = MeshLib.with_tangents(detail)

	return {
		"facade": facade,
		"detail": detail,
		"height": top_y,
		"footprint": footprint,
		"tiers": tiers,
	}

static func _plan_tiers(rng: RandomNumberGenerator, style: Style, footprint: Vector2, floors: int) -> Array:
	var tiers: Array = []
	var height := float(floors) * FLOOR_HEIGHT
	match style:
		Style.LOW_RISE:
			tiers.append({"offset": Vector2.ZERO, "size": Vector3(footprint.x, height, footprint.y), "base": 0.0})
		Style.BLOCK:
			var main := height * rng.randf_range(0.78, 0.9)
			tiers.append({"offset": Vector2.ZERO, "size": Vector3(footprint.x, main, footprint.y), "base": 0.0})
			tiers.append({
				"offset": Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)),
				"size": Vector3(footprint.x * 0.72, height - main, footprint.y * 0.72),
				"base": main})
		Style.PODIUM_TOWER:
			var podium := FLOOR_HEIGHT * rng.randi_range(2, 4)
			tiers.append({"offset": Vector2.ZERO, "size": Vector3(footprint.x * 1.18, podium, footprint.y * 1.18), "base": 0.0})
			var shaft := height - podium
			tiers.append({"offset": Vector2.ZERO, "size": Vector3(footprint.x, shaft * 0.72, footprint.y), "base": podium})
			tiers.append({
				"offset": Vector2.ZERO,
				"size": Vector3(footprint.x * 0.78, shaft * 0.28, footprint.y * 0.78),
				"base": podium + shaft * 0.72})
		_:
			# TOWER: two or three setbacks, each stepping in
			var remaining := height
			var base := 0.0
			var w := footprint
			var steps := rng.randi_range(2, 3)
			for i in steps:
				var slab: float = remaining * (0.55 if i < steps - 1 else 1.0)
				tiers.append({"offset": Vector2.ZERO, "size": Vector3(w.x, slab, w.y), "base": base})
				base += slab
				remaining -= slab
				w *= rng.randf_range(0.74, 0.86)
	return tiers

## Emits the four walls of one tier, returning the running U coordinate so the
## facade pattern stays continuous from tier to tier.
static func _tier_walls(st: SurfaceTool, offset: Vector2, size: Vector3, base: float, u_start: float) -> float:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := base
	var y1 := base + size.y
	var cx := offset.x
	var cz := offset.y
	var u := u_start

	# +Z, +X, -Z, -X — anticlockwise seen from above, so normals face outwards.
	var corners := [
		[Vector3(cx - hx, 0, cz + hz), Vector3(cx + hx, 0, cz + hz), Vector3(0, 0, 1)],
		[Vector3(cx + hx, 0, cz + hz), Vector3(cx + hx, 0, cz - hz), Vector3(1, 0, 0)],
		[Vector3(cx + hx, 0, cz - hz), Vector3(cx - hx, 0, cz - hz), Vector3(0, 0, -1)],
		[Vector3(cx - hx, 0, cz - hz), Vector3(cx - hx, 0, cz + hz), Vector3(-1, 0, 0)],
	]
	for wall in corners:
		var a: Vector3 = wall[0]
		var b: Vector3 = wall[1]
		var n: Vector3 = wall[2]
		var span := a.distance_to(b)
		# Snap the wall run to whole bays so windows never get clipped mid-pane.
		var u0 := u
		var u1 := u + span
		_quad(st,
			Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z),
			Vector3(b.x, y1, b.z), Vector3(a.x, y1, a.z),
			Vector2(u0, y0), Vector2(u1, y0), Vector2(u1, y1), Vector2(u0, y1), n)
		u = u1
	return u

static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2, normal: Vector3) -> void:
	st.set_smooth_group(-1)
	for tri in [[p0, uv0, p1, uv1, p2, uv2], [p0, uv0, p2, uv2, p3, uv3]]:
		for i in 3:
			st.set_normal(normal)
			st.set_uv(tri[i * 2 + 1])
			st.add_vertex(tri[i * 2])

## Rooftop mechanical plant: HVAC blocks, a water tank, vents, a parapet and an
## antenna. Rooftops are what the player sees from above during a jump, so an
## empty one is an obvious tell.
static func _roof_kit(rng: RandomNumberGenerator, offset: Vector2, size: Vector3, top_y: float) -> Array:
	var kit := MeshLib.empty_arrays()
	var hx := size.x * 0.5
	var hz := size.z * 0.5

	# parapet ring
	var thickness := 0.28
	var height := rng.randf_range(0.9, 1.4)
	for wall in [
		[Vector3(offset.x, top_y + height * 0.5, offset.y + hz), Vector3(size.x, height, thickness)],
		[Vector3(offset.x, top_y + height * 0.5, offset.y - hz), Vector3(size.x, height, thickness)],
		[Vector3(offset.x + hx, top_y + height * 0.5, offset.y), Vector3(thickness, height, size.z)],
		[Vector3(offset.x - hx, top_y + height * 0.5, offset.y), Vector3(thickness, height, size.z)],
	]:
		var slab := Sculpt.rounded_box(wall[1], 0.05, 2)
		slab = Sculpt.project_uv_spherical(slab, Vector3.ZERO)
		kit = Sculpt.merge(kit, slab, Transform3D(Basis(), wall[0]))

	var units := rng.randi_range(2, 5)
	for i in units:
		var s := Vector3(rng.randf_range(1.2, 2.6), rng.randf_range(0.8, 1.8), rng.randf_range(1.2, 2.4))
		var pos := Vector3(
			offset.x + rng.randf_range(-hx + 2.0, hx - 2.0),
			top_y + s.y * 0.5,
			offset.y + rng.randf_range(-hz + 2.0, hz - 2.0))
		var box := Sculpt.rounded_box(s, 0.10, 2)
		box = Sculpt.project_uv_spherical(box, Vector3.ZERO)
		kit = Sculpt.merge(kit, box, Transform3D(Basis(), pos))
		# fan cowling on top
		var fan := Sculpt.uv_sphere(Vector3(s.x * 0.28, 0.16, s.z * 0.28), 10, 16)
		fan = Sculpt.project_uv_spherical(fan, Vector3.ZERO)
		kit = Sculpt.merge(kit, fan, Transform3D(Basis(), pos + Vector3(0, s.y * 0.5, 0)))

	# water tank on a short frame
	if rng.randf() < 0.6:
		var tank := MeshLib.tube(
			PackedVector3Array([
				Vector3(0, 0, 0), Vector3(0, 0.6, 0), Vector3(0, 2.2, 0), Vector3(0, 2.8, 0)]),
			[[0.0, 0.05, 0.05, 2.0], [0.16, 1.05, 1.05, 2.0], [0.86, 1.05, 1.05, 2.0], [1.0, 0.45, 0.45, 2.0]],
			18, 4, PackedFloat32Array(), true, true, 1.0)
		var tank_pos := Vector3(offset.x + rng.randf_range(-hx * 0.4, hx * 0.4), top_y + 0.9,
			offset.y + rng.randf_range(-hz * 0.4, hz * 0.4))
		kit = Sculpt.merge(kit, tank, Transform3D(Basis(), tank_pos))
		for leg in 4:
			var angle := TAU * float(leg) / 4.0 + PI * 0.25
			var leg_mesh := Sculpt.rounded_box(Vector3(0.14, 1.0, 0.14), 0.03, 1)
			leg_mesh = Sculpt.project_uv_spherical(leg_mesh, Vector3.ZERO)
			kit = Sculpt.merge(kit, leg_mesh, Transform3D(Basis(),
				tank_pos + Vector3(cos(angle) * 0.7, -0.5, sin(angle) * 0.7)))

	# antenna mast
	if rng.randf() < 0.5:
		var mast_h := rng.randf_range(4.0, 11.0)
		var mast := MeshLib.tube(
			PackedVector3Array([Vector3(0, 0, 0), Vector3(0, mast_h * 0.5, 0), Vector3(0, mast_h, 0)]),
			[[0.0, 0.13, 0.13, 2.0], [0.5, 0.08, 0.08, 2.0], [1.0, 0.03, 0.03, 2.0]],
			8, 3, PackedFloat32Array(), true, true, 1.0)
		kit = Sculpt.merge(kit, mast, Transform3D(Basis(),
			Vector3(offset.x + rng.randf_range(-hx * 0.5, hx * 0.5), top_y,
				offset.y + rng.randf_range(-hz * 0.5, hz * 0.5))))
	return kit

## Height of the tallest point of a tier plan.
static func plan_height(tiers: Array) -> float:
	var height := 0.0
	for tier in tiers:
		height = maxf(height, float(tier["base"]) + (tier["size"] as Vector3).y)
	return height

## Assembles the finished building node with collision.
static func create_node(rng: RandomNumberGenerator, style: Style, footprint: Vector2, floors: int, role: String = "concrete_wall") -> Node3D:
	var data := build(rng, style, footprint, floors)
	var root := Node3D.new()
	root.name = "Building"

	var facade_mesh := MeshLib.arrays_to_mesh(data["facade"], null, "facade")
	facade_mesh = MeshLib.with_lods(facade_mesh)
	var facade_mi := MeshInstance3D.new()
	facade_mi.name = "Facade"
	facade_mi.mesh = facade_mesh
	facade_mi.material_override = Materials.facade(
		role, int(rng.randi()), FLOOR_HEIGHT,
		rng.randf_range(2.2, 3.2), rng.randf_range(0.18, 0.55))
	facade_mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	root.add_child(facade_mi)

	var detail_mesh := MeshLib.arrays_to_mesh(data["detail"], null, "detail")
	detail_mesh = MeshLib.with_lods(detail_mesh)
	var detail_mi := MeshInstance3D.new()
	detail_mi.name = "Detail"
	detail_mi.mesh = detail_mesh
	detail_mi.material_override = AssetLibrary.material("concrete_floor", {
		"uv_scale": 1.2, "triplanar": true, "roughness": 0.78, "tint": Color(0.62, 0.61, 0.60)})
	detail_mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	root.add_child(detail_mi)

	# Collision from the tier boxes: a handful of boxes beats a trimesh with
	# thousands of triangles when hundreds of buildings are in the level.
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	for tier in data["tiers"]:
		var size: Vector3 = tier["size"]
		var offset: Vector2 = tier["offset"]
		var base: float = tier["base"]
		var shape := CollisionShape3D.new()
		shape.shape = MeshLib.box_shape(size)
		shape.position = Vector3(offset.x, base + size.y * 0.5, offset.y)
		body.add_child(shape)
	root.add_child(body)

	root.set_meta("height", data["height"])
	return root
