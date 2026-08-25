extends SceneTree
## Headless build verification: exercises every procedural generator once and
## reports triangle counts. Run with:
##   godot --headless --script res://tests/smoke_test.gd

var failures: int = 0

func _initialize() -> void:
	print("== DIGIHARIMAN smoke test ==")
	_test_shaders()
	_test_mesh_lib()
	_test_humanoid()
	_test_hero()
	_test_monsters()
	_report()
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  [ok]   %s" % label)
	else:
		failures += 1
		printerr("  [FAIL] %s" % label)

func _test_mesh_lib() -> void:
	print("-- MeshLib")
	var ring := MeshLib.superellipse_ring(0.5, 0.3, 24, 3.0)
	_check(ring.size() == 24, "superellipse_ring size")

	var path := MeshLib.catmull_rom(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 1, 0.2), Vector3(0.1, 2, 0), Vector3(0, 3, -0.2)]), 8)
	_check(path.size() > 20, "catmull_rom resample (%d pts)" % path.size())

	var frames := MeshLib.rmf_frames(path)
	_check(frames.size() == path.size(), "rmf frames")

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var vs := PackedFloat32Array()
	for i in path.size():
		rings.append(MeshLib.place_ring(ring, path[i], frames[i]))
		vs.append(float(i) / float(path.size()))
	MeshLib.stitch(st, rings, vs, 1.0, 0)
	st.generate_normals()
	st.index()
	var mesh: ArrayMesh = st.commit()
	_check(mesh.get_surface_count() == 1, "loft commits a surface")

	var arrays := mesh.surface_get_arrays(0)
	var base_tris: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	arrays = MeshLib.subdivide(arrays)
	var sub_tris: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_check(sub_tris == base_tris * 4, "subdivide 1->4 (%d -> %d)" % [base_tris, sub_tris])

	arrays = MeshLib.relax(arrays, 2, 0.4)
	_check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0, "relax keeps vertices")

	arrays = MeshLib.weld(arrays, 0.001)
	_check((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "weld + normals")

	arrays = MeshLib.displace(arrays, MeshLib.make_noise(1, 3.0, 4), 0.02)
	_check((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() > 0, "noise displace")

	arrays = MeshLib.bake_cavity(arrays, 0.7, 0.1)
	_check((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0, "cavity bake")

	var final_mesh := MeshLib.arrays_to_mesh(arrays, StandardMaterial3D.new(), "test")
	_check(final_mesh.get_surface_count() == 1, "arrays_to_mesh")

	var lod_mesh := MeshLib.with_lods(final_mesh)
	_check(lod_mesh != null and lod_mesh.get_surface_count() == 1, "LOD generation")
	var levels := MeshLib.lod_levels(final_mesh)
	_check(levels.size() == 1 and levels[0] > 0, "LOD levels produced (%s)" % str(levels))

func _report() -> void:
	if failures == 0:
		print("== ALL CHECKS PASSED ==")
	else:
		printerr("== %d CHECK(S) FAILED ==" % failures)

func _test_humanoid() -> void:
	print("-- Humanoid")
	var t0 := Time.get_ticks_msec()
	var bones := Humanoid.bone_table()
	_check(bones.size() > 50, "bone table (%d bones)" % bones.size())
	var segments := Humanoid.skinning_segments(bones)
	_check(segments.size() == bones.size() - 1, "skinning capsules (%d)" % segments.size())

	var figure := Humanoid.build({"quality": 1.0})
	var stats: Dictionary = figure["stats"]
	print("     body %d tris / skin %d tris / %d bones" % [stats["body_tris"], stats["skin_tris"], stats["bones"]])
	_check(int(stats["body_tris"]) > 20000, "body density")
	_check(int(stats["skin_tris"]) > 10000, "head+hands density")

	var skinned := Skinning.skin_arrays(figure["body"], segments)
	var weights: PackedFloat32Array = skinned[Mesh.ARRAY_WEIGHTS]
	var verts: PackedVector3Array = skinned[Mesh.ARRAY_VERTEX]
	_check(weights.size() == verts.size() * 4, "4 weights per vertex")
	var bad := 0
	for v in verts.size():
		var sum := weights[v * 4] + weights[v * 4 + 1] + weights[v * 4 + 2] + weights[v * 4 + 3]
		if absf(sum - 1.0) > 0.001:
			bad += 1
	_check(bad == 0, "weights normalised (%d bad)" % bad)

	var mesh := Skinning.commit_skinned(skinned, StandardMaterial3D.new(), "body")
	_check(mesh.get_surface_count() == 1, "skinned surface commits")
	print("     built in %d ms" % (Time.get_ticks_msec() - t0))

func _test_hero() -> void:
	print("-- DIGIHARIMAN")
	BuildCache.clear()
	var t0 := Time.get_ticks_msec()
	var parts := DigiHariMan.build({"quality": 1.0})
	var stats: Dictionary = parts["stats"]
	var total: int = int(stats["body_tris"]) + int(stats["skin_tris"]) + int(stats["armor_tris"]) + int(stats["trim_tris"])
	print("     body %d / skin %d / armor %d / trim %d = %d tris, %d bones, %d ms"
		% [stats["body_tris"], stats["skin_tris"], stats["armor_tris"], stats["trim_tris"], total,
			stats["bones"], Time.get_ticks_msec() - t0])
	_check(total > 90000, "hero geometry density")
	_check(int(stats["armor_tris"]) > 15000, "armour density")

	var t1 := Time.get_ticks_msec()
	var node := DigiHariMan.create_node({"quality": 1.0})
	_check(node != null, "hero node built")
	var skeleton := node.get_child(0) as Skeleton3D
	_check(skeleton != null and skeleton.get_bone_count() > 50, "skeleton attached")
	var meshes := 0
	var skinned_ok := true
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			meshes += 1
			if (child as MeshInstance3D).mesh == null or (child as MeshInstance3D).skin == null:
				skinned_ok = false
	_check(meshes == 5, "five material groups (%d)" % meshes)
	_check(skinned_ok, "every group is skinned")
	print("     assembled in %d ms (first run, cold cache)" % (Time.get_ticks_msec() - t1))

	var t2 := Time.get_ticks_msec()
	var node2 := DigiHariMan.create_node({"quality": 1.0})
	print("     assembled in %d ms (warm cache)" % (Time.get_ticks_msec() - t2))
	_check(node2 != null, "cached rebuild")
	node.free()
	node2.free()

func _test_shaders() -> void:
	print("-- Shaders")
	var dir := DirAccess.open("res://shaders")
	if dir == null:
		_check(false, "shaders folder present")
		return
	var files := dir.get_files()
	files.sort()
	var count := 0
	for f in files:
		if not f.ends_with(".gdshader"):
			continue
		var shader := load("res://shaders/" + f) as Shader
		var mat := ShaderMaterial.new()
		mat.shader = shader
		# A shader that failed to parse reports no uniforms at all.
		var uniforms := shader.get_shader_uniform_list()
		_check(uniforms.size() > 0, "%s compiles (%d uniforms)" % [f, uniforms.size()])
		count += 1
	_check(count >= 12, "all %d shaders checked" % count)

func _test_monsters() -> void:
	print("-- Monsters")
	for kind in [Monster.Kind.STALKER, Monster.Kind.BRUTE, Monster.Kind.SWARMER]:
		var t0 := Time.get_ticks_msec()
		var parts := Monster.build(kind, {"quality": 1.0})
		var stats: Dictionary = parts["stats"]
		var profile: Dictionary = parts["profile"]
		print("     %-8s %6d tris / %d bones / %d ms" % [profile["name"], stats["flesh_tris"], stats["bones"], Time.get_ticks_msec() - t0])
		_check(int(stats["flesh_tris"]) > 20000, "%s density" % profile["name"])
		var skinned := Skinning.skin_arrays(parts["groups"]["flesh"], parts["segments"])
		var w: PackedFloat32Array = skinned[Mesh.ARRAY_WEIGHTS]
		var v: PackedVector3Array = skinned[Mesh.ARRAY_VERTEX]
		_check(w.size() == v.size() * 4, "%s skinning" % profile["name"])
		var node := Monster.create_node(kind, {"quality": 1.0})
		_check(node != null and node.get_child(0) is Skeleton3D, "%s node" % profile["name"])
		node.free()
