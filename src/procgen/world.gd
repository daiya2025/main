class_name WorldBuilder
extends RefCounted
## Builds the playable district.
##
## Layout: a rectangular street grid of city blocks around a central plaza that
## acts as the combat arena. Buildings are generated from a small pool of
## templates and re-instanced with per-building facade materials — a modular
## kit, which is how a real city gets built without a per-building budget.

const BLOCK := 34.0            # metres, block pitch including the street
const STREET := 12.0           # carriageway width
const SIDEWALK := 2.4
const GRID := 5                # GRID x GRID blocks
const TEMPLATE_COUNT := 8
const ARENA_RADIUS := 21.0

const WORLD_EXTENT := BLOCK * float(GRID) * 0.5 + 60.0

static func district_extent() -> float:
	return BLOCK * float(GRID) * 0.5

## Builds everything under `root` and returns a summary Dictionary.
static func build(root: Node3D, seed_value: int = 20250825) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var stats := {"buildings": 0, "props": 0, "plants": 0, "lights": 0, "triangles": 0}

	Signals.world_build_progress.emit("terrain", 0.05)
	root.add_child(_terrain(rng))

	Signals.world_build_progress.emit("streets", 0.2)
	root.add_child(_streets(rng))

	Signals.world_build_progress.emit("buildings", 0.35)
	root.add_child(_district(rng, stats))

	Signals.world_build_progress.emit("plaza", 0.7)
	root.add_child(_plaza(rng, stats))

	Signals.world_build_progress.emit("props", 0.8)
	root.add_child(_street_props(rng, stats))

	Signals.world_build_progress.emit("nature", 0.9)
	root.add_child(_nature(rng, stats))

	root.add_child(_bounds())
	Signals.world_build_progress.emit("done", 1.0)
	return stats

## Same as build(), but yields a frame between stages so the loading screen
## stays responsive and the progress bar actually moves.
static func build_staged(root: Node3D, seed_value: int = 20250825) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var stats := {"buildings": 0, "props": 0, "plants": 0, "lights": 0, "triangles": 0}
	var tree := root.get_tree()

	var stages: Array = [
		["terrain", 0.05, func() -> Node3D: return _terrain(rng)],
		["streets", 0.20, func() -> Node3D: return _streets(rng)],
		["buildings", 0.35, func() -> Node3D: return _district(rng, stats)],
		["plaza", 0.70, func() -> Node3D: return _plaza(rng, stats)],
		["props", 0.80, func() -> Node3D: return _street_props(rng, stats)],
		["nature", 0.90, func() -> Node3D: return _nature(rng, stats)],
	]
	for stage in stages:
		Signals.world_build_progress.emit(String(stage[0]), float(stage[1]))
		# Two frames: one to paint the new label, one to present it.
		await tree.process_frame
		await tree.process_frame
		var built: Node3D = (stage[2] as Callable).call()
		root.add_child(built)
	root.add_child(_bounds())
	Signals.world_build_progress.emit("done", 1.0)
	await tree.process_frame
	return stats

# ----------------------------------------------------------------- terrain --

static func _terrain(rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	node.name = "Terrain"
	var extent := WORLD_EXTENT
	var res := 96
	var flat_radius := district_extent() + 6.0

	var relief := MeshLib.make_noise(rng.seed + 11, 0.006, 5)
	var detail := MeshLib.make_noise(rng.seed + 23, 0.05, 3)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := []
	heights.resize(res + 1)
	for z in res + 1:
		var row := PackedFloat32Array()
		row.resize(res + 1)
		for x in res + 1:
			var wx := lerpf(-extent, extent, float(x) / float(res))
			var wz := lerpf(-extent, extent, float(z) / float(res))
			row[x] = _height_at(wx, wz, flat_radius, relief, detail)
		heights[z] = row

	for z in res:
		var r0: PackedFloat32Array = heights[z]
		var r1: PackedFloat32Array = heights[z + 1]
		for x in res:
			var x0 := lerpf(-extent, extent, float(x) / float(res))
			var x1 := lerpf(-extent, extent, float(x + 1) / float(res))
			var z0 := lerpf(-extent, extent, float(z) / float(res))
			var z1 := lerpf(-extent, extent, float(z + 1) / float(res))
			var p00 := Vector3(x0, r0[x], z0)
			var p10 := Vector3(x1, r0[x + 1], z0)
			var p11 := Vector3(x1, r1[x + 1], z1)
			var p01 := Vector3(x0, r1[x], z1)
			# UVs are unused by the triplanar terrain shader but keep tangents sane
			var uv := 0.02
			st.set_uv(Vector2(x0, z0) * uv); st.add_vertex(p00)
			st.set_uv(Vector2(x1, z1) * uv); st.add_vertex(p11)
			st.set_uv(Vector2(x1, z0) * uv); st.add_vertex(p10)
			st.set_uv(Vector2(x0, z0) * uv); st.add_vertex(p00)
			st.set_uv(Vector2(x0, z1) * uv); st.add_vertex(p01)
			st.set_uv(Vector2(x1, z1) * uv); st.add_vertex(p11)
	st.generate_normals()
	st.generate_tangents()
	st.index()
	var mesh: ArrayMesh = st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = MeshLib.with_lods(mesh)
	mi.material_override = Materials.terrain("ground_primary", "cliff", "gravel")
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	node.add_child(body)
	return node

static func _height_at(x: float, z: float, flat_radius: float, relief: FastNoiseLite, detail: FastNoiseLite) -> float:
	# The district is flat so combat stays readable; the land only starts to
	# move once it is outside the streets, and rises into hills at the border.
	var d := maxf(absf(x), absf(z))
	var outside := clampf((d - flat_radius) / 55.0, 0.0, 1.0)
	outside = outside * outside * (3.0 - 2.0 * outside)
	var hills := relief.get_noise_2d(x, z) * 16.0 + detail.get_noise_2d(x, z) * 0.9
	var micro := detail.get_noise_2d(x * 2.0, z * 2.0) * 0.06
	return micro + hills * outside + outside * 3.5

# ----------------------------------------------------------------- streets --

static func _streets(rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	node.name = "Streets"
	var extent := district_extent()

	var road := MeshInstance3D.new()
	road.name = "Carriageway"
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent * 2.0 + STREET, extent * 2.0 + STREET)
	plane.subdivide_width = 16
	plane.subdivide_depth = 16
	road.mesh = plane
	road.position = Vector3(0, 0.01, 0)
	road.material_override = Materials.road(0.55)
	road.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.add_child(road)

	# Sidewalk kerbs around every block.
	var kerb_mesh := BoxMesh.new()
	kerb_mesh.size = Vector3(1, 1, 1)
	var kerb_mat := AssetLibrary.material("concrete_floor", {
		"uv_scale": 0.6, "triplanar": true, "roughness": 0.86, "tint": Color(0.66, 0.65, 0.63)})
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = kerb_mesh
	var transforms: Array[Transform3D] = []
	var half := float(GRID) * 0.5
	for gx in GRID:
		for gz in GRID:
			var cx := (float(gx) - half + 0.5) * BLOCK
			var cz := (float(gz) - half + 0.5) * BLOCK
			if Vector2(cx, cz).length() < ARENA_RADIUS + 6.0:
				continue
			var size := BLOCK - STREET
			var t := Transform3D(Basis().scaled(Vector3(size + SIDEWALK * 2.0, 0.28, size + SIDEWALK * 2.0)),
				Vector3(cx, 0.14, cz))
			transforms.append(t)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sidewalks"
	mmi.multimesh = mm
	mmi.material_override = kerb_mat
	mmi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.add_child(mmi)

	# One flat collider under the whole district; the kerb lip is only 28 cm and
	# the character controller steps over it.
	var body := StaticBody3D.new()
	body.name = "StreetCollision"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(extent * 2.0 + STREET, 1.0, extent * 2.0 + STREET)
	shape.shape = box
	shape.position = Vector3(0, -0.5 + 0.28, 0)
	body.add_child(shape)
	node.add_child(body)
	return node

# --------------------------------------------------------------- buildings --

static func _building_templates(base_seed: int) -> Array:
	var templates: Array = []
	var styles := [Building.Style.TOWER, Building.Style.BLOCK, Building.Style.PODIUM_TOWER, Building.Style.LOW_RISE]
	for i in TEMPLATE_COUNT:
		# Each template owns three deterministic streams: one for its
		# dimensions, one for the tier plan and one for the mesh detail. The
		# tier plan is computed *outside* the cached closure, because the
		# collision boxes come from it and the mesh may be served from disk.
		var dims := RandomNumberGenerator.new()
		dims.seed = base_seed * 7919 + i
		var style: Building.Style = styles[i % styles.size()]
		var footprint := Vector2(dims.randf_range(13.0, 19.0), dims.randf_range(13.0, 19.0))
		var floors := dims.randi_range(3, 6) if style == Building.Style.LOW_RISE else dims.randi_range(7, 22)

		var plan_rng := RandomNumberGenerator.new()
		plan_rng.seed = base_seed * 7919 + i + 104729
		var tiers := Building._plan_tiers(plan_rng, style, footprint, floors)
		var height := Building.plan_height(tiers)

		var key := "building_%d" % i
		var state := {"data": null}
		var mesh_seed := base_seed * 7919 + i + 224737
		var facade_mesh := BuildCache.mesh(key + "_facade", func() -> Mesh:
			if state["data"] == null:
				var mesh_rng := RandomNumberGenerator.new()
				mesh_rng.seed = mesh_seed
				state["data"] = Building.build(mesh_rng, style, footprint, floors, tiers)
			return MeshLib.with_lods(MeshLib.arrays_to_mesh((state["data"] as Dictionary)["facade"], null, "facade")))
		var detail_mesh := BuildCache.mesh(key + "_detail", func() -> Mesh:
			if state["data"] == null:
				var mesh_rng := RandomNumberGenerator.new()
				mesh_rng.seed = mesh_seed
				state["data"] = Building.build(mesh_rng, style, footprint, floors, tiers)
			return MeshLib.with_lods(MeshLib.arrays_to_mesh((state["data"] as Dictionary)["detail"], null, "detail")))

		templates.append({
			"facade": facade_mesh, "detail": detail_mesh, "tiers": tiers,
			"height": height, "footprint": footprint, "style": style})
	return templates

static func _district(rng: RandomNumberGenerator, stats: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "District"
	var templates := _building_templates(int(rng.seed))
	var roles := ["concrete_wall", "brick", "concrete_floor", "metal_plate"]
	var half := float(GRID) * 0.5
	var detail_material := AssetLibrary.material("concrete_floor", {
		"uv_scale": 1.2, "triplanar": true, "roughness": 0.78, "tint": Color(0.60, 0.59, 0.58)})

	for gx in GRID:
		for gz in GRID:
			var cx := (float(gx) - half + 0.5) * BLOCK
			var cz := (float(gz) - half + 0.5) * BLOCK
			if Vector2(cx, cz).length() < ARENA_RADIUS + 8.0:
				continue                       # the plaza block stays open
			var per_block := rng.randi_range(1, 2)
			for b in per_block:
				var template: Dictionary = templates[rng.randi() % templates.size()]
				var jitter := Vector3(rng.randf_range(-3.5, 3.5), 0.0, rng.randf_range(-3.5, 3.5))
				if per_block > 1:
					jitter.x += (float(b) - 0.5) * 8.0
				var inst := Node3D.new()
				inst.name = "Building_%d_%d_%d" % [gx, gz, b]
				inst.position = Vector3(cx, 0.28, cz) + jitter
				inst.rotation.y = float(rng.randi_range(0, 3)) * PI * 0.5

				var facade_mi := MeshInstance3D.new()
				facade_mi.mesh = template["facade"]
				facade_mi.material_override = Materials.facade(
					roles[rng.randi() % roles.size()], int(rng.randi()),
					Building.FLOOR_HEIGHT, rng.randf_range(2.2, 3.2), rng.randf_range(0.15, 0.55))
				facade_mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				inst.add_child(facade_mi)

				var detail_mi := MeshInstance3D.new()
				detail_mi.mesh = template["detail"]
				detail_mi.material_override = detail_material
				detail_mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
				inst.add_child(detail_mi)

				var body := StaticBody3D.new()
				body.collision_layer = 1
				for tier in template["tiers"]:
					var size: Vector3 = tier["size"]
					var offset: Vector2 = tier["offset"]
					var base: float = tier["base"]
					var shape := CollisionShape3D.new()
					shape.shape = MeshLib.box_shape(size)
					shape.position = Vector3(offset.x, base + size.y * 0.5, offset.y)
					body.add_child(shape)
				inst.add_child(body)

				# Buildings are the level's occluders. Feeding the tier boxes to
				# the occlusion culler is what stops the renderer paying for the
				# entire district when the player is standing in one street.
				var occluder := OccluderInstance3D.new()
				var box_occluder := BoxOccluder3D.new()
				var main_tier: Dictionary = template["tiers"][0]
				var main_size: Vector3 = main_tier["size"]
				box_occluder.size = Vector3(main_size.x * 0.92, float(template["height"]) * 0.94, main_size.z * 0.92)
				occluder.occluder = box_occluder
				occluder.position = Vector3(0, float(template["height"]) * 0.47, 0)
				inst.add_child(occluder)

				# Rooftop clutter is small and numerous; drop it before the
				# facade, which still reads as a silhouette at distance.
				detail_mi.visibility_range_end = Quality.draw_distance() * 0.45
				detail_mi.visibility_range_end_margin = 25.0
				detail_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

				node.add_child(inst)
				stats["buildings"] = int(stats["buildings"]) + 1
	return node

# ------------------------------------------------------------------- plaza --

static func _plaza(rng: RandomNumberGenerator, stats: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Plaza"

	# Paved disc
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA_RADIUS
	disc.bottom_radius = ARENA_RADIUS
	disc.height = 0.34
	disc.radial_segments = 96
	disc.rings = 4
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Pavement"
	floor_mi.mesh = disc
	floor_mi.position = Vector3(0, 0.17, 0)
	floor_mi.material_override = AssetLibrary.material("tiles", {
		"uv_scale": 0.35, "triplanar": true, "roughness": 0.55, "tint": Color(0.72, 0.71, 0.70)})
	floor_mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.add_child(floor_mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = ARENA_RADIUS
	cyl.height = 0.34
	shape.shape = cyl
	shape.position = Vector3(0, 0.17, 0)
	body.add_child(shape)
	node.add_child(body)

	# The monolith: the district's landmark and the reason the fight happens
	# here. It is also the strongest orange light source in the level.
	var monolith := MeshLib.tube(
		PackedVector3Array([
			Vector3(0, 0, 0), Vector3(0, 3.0, 0), Vector3(0, 9.0, 0), Vector3(0, 13.5, 0), Vector3(0, 15.2, 0)]),
		[[0.00, 2.4, 2.4, 3.2], [0.16, 1.9, 1.9, 3.0], [0.58, 1.5, 1.5, 2.9], [0.90, 0.9, 0.9, 2.8], [1.0, 0.25, 0.25, 2.6]],
		18, 5, PackedFloat32Array(), true, true, 0.6)
	for i in 5:
		monolith = Sculpt.crease(monolith, Vector3(0, 2.0 + float(i) * 2.6, 0), Vector3(0, 1, 0), 0.22, 0.14,
			Vector3(0, 2.0 + float(i) * 2.6, 0), Vector3(3.2, 0.5, 3.2))
	monolith = Sculpt.project_uv_spherical(monolith, Vector3(0, 7.0, 0), 2.0)
	monolith = MeshLib.bake_cavity(monolith, 1.0, 0.2)
	monolith = MeshLib.with_tangents(monolith)
	var mono_mi := MeshInstance3D.new()
	mono_mi.name = "Monolith"
	mono_mi.mesh = MeshLib.arrays_to_mesh(monolith, null, "monolith")
	mono_mi.material_override = Materials.armor("dark")
	mono_mi.position = Vector3(0, 0.34, 0)
	node.add_child(mono_mi)

	var core := MeshInstance3D.new()
	core.name = "MonolithCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 1.15
	core_mesh.height = 2.3
	core_mesh.radial_segments = 32
	core_mesh.rings = 20
	core.mesh = core_mesh
	core.material_override = Materials.energy(Materials.ORANGE_EMISSIVE, 16.0)
	core.position = Vector3(0, 11.0, 0)
	node.add_child(core)

	var core_light := OmniLight3D.new()
	core_light.name = "MonolithLight"
	core_light.position = Vector3(0, 11.0, 0)
	core_light.light_color = Materials.ORANGE_EMISSIVE
	core_light.light_energy = 12.0
	core_light.omni_range = 46.0
	core_light.omni_attenuation = 1.4
	core_light.shadow_enabled = true
	core_light.light_volumetric_fog_energy = 3.0
	node.add_child(core_light)
	stats["lights"] = int(stats["lights"]) + 1

	# Ring of low bollards marking the arena edge.
	var bollard := MeshLib.tube(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 0.92, 0)]),
		[[0.0, 0.16, 0.16, 2.6], [0.6, 0.13, 0.13, 2.5], [1.0, 0.10, 0.10, 2.4]],
		12, 3, PackedFloat32Array(), true, true, 2.0)
	bollard = Sculpt.project_uv_spherical(bollard, Vector3(0, 0.45, 0), 2.0)
	bollard = MeshLib.with_tangents(bollard)
	var bollard_mesh := MeshLib.arrays_to_mesh(bollard, null, "bollard")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bollard_mesh
	var count := 32
	mm.instance_count = count
	for i in count:
		var angle := TAU * float(i) / float(count)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(
			cos(angle) * (ARENA_RADIUS - 1.4), 0.34, sin(angle) * (ARENA_RADIUS - 1.4))))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Bollards"
	mmi.multimesh = mm
	mmi.material_override = Materials.armor("trim")
	node.add_child(mmi)
	stats["props"] = int(stats["props"]) + count

	# Screen-space reflections cannot see anything off-screen, and the arena is
	# exactly where the player looks down at wet paving. A probe fills in the
	# monolith and the surrounding facades that SSR has to miss.
	var probe := ReflectionProbe.new()
	probe.name = "ArenaProbe"
	probe.size = Vector3(ARENA_RADIUS * 2.6, 26.0, ARENA_RADIUS * 2.6)
	probe.origin_offset = Vector3(0, -4.0, 0)
	probe.position = Vector3(0, 9.0, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 1.0
	probe.max_distance = 160.0
	probe.enable_shadows = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	node.add_child(probe)
	return node

# ------------------------------------------------------------------- props --

static func _street_props(rng: RandomNumberGenerator, stats: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Props"
	var half := float(GRID) * 0.5
	var extent := district_extent()

	# --- street lamps -----------------------------------------------------
	var lamp := MeshLib.tube(
		PackedVector3Array([
			Vector3(0, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 4.4, 0),
			Vector3(0.35, 5.3, 0), Vector3(1.5, 5.55, 0)]),
		[[0.0, 0.24, 0.24, 2.6], [0.10, 0.12, 0.12, 2.4], [0.72, 0.085, 0.085, 2.3],
		 [0.88, 0.075, 0.075, 2.3], [1.0, 0.10, 0.16, 2.6]],
		12, 5, PackedFloat32Array(), true, true, 1.5)
	lamp = Sculpt.project_uv_spherical(lamp, Vector3(0, 2.8, 0), 1.5)
	lamp = MeshLib.bake_cavity(lamp, 0.9, 0.06)
	lamp = MeshLib.with_tangents(lamp)
	var lamp_mesh := MeshLib.arrays_to_mesh(lamp, null, "lamp")

	var lamp_mm := MultiMesh.new()
	lamp_mm.transform_format = MultiMesh.TRANSFORM_3D
	lamp_mm.mesh = lamp_mesh
	var lamp_xforms: Array[Transform3D] = []
	var lit_positions: Array[Vector3] = []
	for gx in GRID + 1:
		for gz in GRID + 1:
			var x := (float(gx) - half) * BLOCK
			var z := (float(gz) - half) * BLOCK
			if Vector2(x, z).length() < ARENA_RADIUS + 3.0:
				continue
			if absf(x) > extent + 2.0 or absf(z) > extent + 2.0:
				continue
			var yaw := rng.randf() * TAU
			lamp_xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0.28, z)))
			lit_positions.append(Vector3(x, 0.28, z) + Vector3(cos(yaw), 0, -sin(yaw)) * 1.5)
	lamp_mm.instance_count = lamp_xforms.size()
	for i in lamp_xforms.size():
		lamp_mm.set_instance_transform(i, lamp_xforms[i])
	var lamp_mmi := MultiMeshInstance3D.new()
	lamp_mmi.name = "StreetLamps"
	lamp_mmi.multimesh = lamp_mm
	lamp_mmi.material_override = Materials.armor("dark")
	lamp_mmi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.add_child(lamp_mmi)
	stats["props"] = int(stats["props"]) + lamp_xforms.size()

	# Real lights only on the lamps nearest the arena; the rest are emissive
	# geometry, which SDFGI still picks up as bounce.
	var lit_budget := int(clampf(18.0 * Quality.foliage_density() + 6.0, 6.0, 26.0))
	lit_positions.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.length_squared() < b.length_squared())
	for i in mini(lit_budget, lit_positions.size()):
		var light := OmniLight3D.new()
		light.position = lit_positions[i] + Vector3(0, 5.5, 0)
		light.light_color = Color(1.0, 0.72, 0.42)
		light.light_energy = 5.5
		light.omni_range = 17.0
		light.omni_attenuation = 1.6
		light.shadow_enabled = i < 8
		light.light_volumetric_fog_energy = 2.0
		node.add_child(light)
		stats["lights"] = int(stats["lights"]) + 1
		var bulb := MeshInstance3D.new()
		var bulb_mesh := SphereMesh.new()
		bulb_mesh.radius = 0.16
		bulb_mesh.height = 0.32
		bulb.mesh = bulb_mesh
		bulb.position = lit_positions[i] + Vector3(0, 5.45, 0)
		bulb.material_override = Materials.energy(Color(1.0, 0.75, 0.45), 12.0)
		node.add_child(bulb)

	# --- barriers, crates and debris --------------------------------------
	var crate := Sculpt.rounded_box(Vector3(0.9, 0.9, 0.9), 0.06, 2)
	crate = Sculpt.project_uv_spherical(crate, Vector3.ZERO)
	crate = MeshLib.bake_cavity(crate, 1.0, 0.08)
	crate = MeshLib.with_tangents(crate)
	var crate_mesh := MeshLib.arrays_to_mesh(crate, null, "crate")
	var crate_mm := MultiMesh.new()
	crate_mm.transform_format = MultiMesh.TRANSFORM_3D
	crate_mm.mesh = crate_mesh
	var crates: Array[Transform3D] = []
	for i in 120:
		var pos := Vector3(rng.randf_range(-extent, extent), 0.73, rng.randf_range(-extent, extent))
		if Vector2(pos.x, pos.z).length() < ARENA_RADIUS - 3.0:
			continue
		var stack := rng.randi_range(1, 3)
		for s in stack:
			crates.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)),
				pos + Vector3(rng.randf_range(-0.1, 0.1), 0.92 * float(s), rng.randf_range(-0.1, 0.1))))
	crate_mm.instance_count = crates.size()
	for i in crates.size():
		crate_mm.set_instance_transform(i, crates[i])
	var crate_mmi := MultiMeshInstance3D.new()
	crate_mmi.name = "Crates"
	crate_mmi.multimesh = crate_mm
	crate_mmi.material_override = AssetLibrary.material("wood", {"uv_scale": 1.4, "triplanar": true, "roughness": 0.8})
	node.add_child(crate_mmi)
	stats["props"] = int(stats["props"]) + crates.size()
	return node

# ------------------------------------------------------------------ nature --

static func _nature(rng: RandomNumberGenerator, stats: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Nature"
	var density := Quality.foliage_density()
	var extent := district_extent()

	# Photoscanned meshes take priority; the procedural generators are the
	# fallback so the world is populated either way.
	var scanned_trees := AssetLibrary.scanned_meshes("tree")
	var scanned_rocks := AssetLibrary.scanned_meshes("rock")

	var tree_meshes: Array[Mesh] = []
	var tree_materials: Array[Material] = []
	if scanned_trees.is_empty():
		for i in 3:
			var built := BuildCache.mesh("tree_%d_wood" % i, func() -> Mesh:
				var local := RandomNumberGenerator.new()
				local.seed = rng.seed + 700 + i
				var t := Flora.tree(local, 7.0 + float(i) * 1.6)
				var merged := Sculpt.merge(t["wood"], t["canopy"])
				return MeshLib.with_lods(MeshLib.arrays_to_mesh(merged, null, "tree"))) 
			if built != null:
				tree_meshes.append(built)
				tree_materials.append(AssetLibrary.material("bark", {"uv_scale": 2.0, "triplanar": true, "roughness": 0.9}))
	else:
		for m in scanned_trees:
			tree_meshes.append(m)
			tree_materials.append(null)

	var rock_meshes: Array[Mesh] = []
	if scanned_rocks.is_empty():
		for i in 4:
			var built := BuildCache.mesh("rock_%d" % i, func() -> Mesh:
				var local := RandomNumberGenerator.new()
				local.seed = rng.seed + 900 + i
				return MeshLib.with_lods(MeshLib.arrays_to_mesh(Flora.rock(local, 0.7 + float(i) * 0.55), null, "rock")))
			if built != null:
				rock_meshes.append(built)
	else:
		rock_meshes.assign(scanned_rocks)

	var rock_material := AssetLibrary.material("cliff", {"uv_scale": 0.9, "triplanar": true, "roughness": 0.92})

	_scatter(node, tree_meshes, tree_materials, rng, int(190 * density), extent + 8.0, WORLD_EXTENT - 14.0, 0.75, 1.5, stats, "Trees")
	_scatter(node, rock_meshes, [], rng, int(240 * density), extent + 4.0, WORLD_EXTENT - 8.0, 0.5, 1.8, stats, "Rocks", rock_material)
	return node

static func _scatter(parent: Node3D, meshes: Array[Mesh], materials: Array[Material], rng: RandomNumberGenerator,
		count: int, min_radius: float, max_radius: float, min_scale: float, max_scale: float,
		stats: Dictionary, group_name: String, shared_material: Material = null) -> void:
	if meshes.is_empty() or count <= 0:
		return
	var per_mesh: Array = []
	per_mesh.resize(meshes.size())
	for i in meshes.size():
		per_mesh[i] = []
	var relief := MeshLib.make_noise(rng.seed + 11, 0.006, 5)
	var detail := MeshLib.make_noise(rng.seed + 23, 0.05, 3)
	var flat_radius := district_extent() + 6.0
	for i in count:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * (max_radius - min_radius) + min_radius
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		if absf(x) > WORLD_EXTENT - 6.0 or absf(z) > WORLD_EXTENT - 6.0:
			continue
		var y := _height_at(x, z, flat_radius, relief, detail)
		var idx := rng.randi() % meshes.size()
		var bucket: Array = per_mesh[idx]
		bucket.append(Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(min_scale, max_scale)),
			Vector3(x, y - 0.08, z)))
	for i in meshes.size():
		var bucket: Array = per_mesh[i]
		if bucket.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = bucket.size()
		for j in bucket.size():
			mm.set_instance_transform(j, bucket[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [group_name, i]
		mmi.multimesh = mm
		if shared_material != null:
			mmi.material_override = shared_material
		elif i < materials.size() and materials[i] != null:
			mmi.material_override = materials[i]
		mmi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = Quality.draw_distance()
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)
		stats["plants"] = int(stats["plants"]) + bucket.size()

# ------------------------------------------------------------------ bounds --

static func _bounds() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "WorldBounds"
	body.collision_layer = 1
	var extent := WORLD_EXTENT - 4.0
	for wall in [
		[Vector3(0, 30, extent), Vector3(extent * 2.0, 60, 2)],
		[Vector3(0, 30, -extent), Vector3(extent * 2.0, 60, 2)],
		[Vector3(extent, 30, 0), Vector3(2, 60, extent * 2.0)],
		[Vector3(-extent, 30, 0), Vector3(2, 60, extent * 2.0)],
	]:
		var shape := CollisionShape3D.new()
		shape.shape = MeshLib.box_shape(wall[1])
		shape.position = wall[0]
		body.add_child(shape)
	return body
