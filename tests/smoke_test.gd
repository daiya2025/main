extends SceneTree
## Headless build verification: exercises every procedural generator once and
## reports triangle counts. Run with:
##   godot --headless --script res://tests/smoke_test.gd

var failures: int = 0
var _stage: int = 0

func _initialize() -> void:
	print("== DIGIHARIMAN smoke test ==")
	_test_polyhaven_planner()
	_test_audio()
	_test_shaders()
	_test_mesh_lib()
	_test_humanoid()
	_test_hero()
	_test_monsters()

## Skeleton3D only propagates its dirty flag once it is inside an active tree,
## and SceneTree.root is not active during _initialize — so the animation
## checks run on the first processed frame instead.
func _process(_delta: float) -> bool:
	match _stage:
		0:
			_stage = 1
			_test_animation()
			_setup_combat()
		1:
			# Let physics settle the spawned bodies (and the monster's SPAWN
			# state finish) before asserting on them.
			_combat_frames += 1
			if _combat_frames >= 40:
				_stage = 2
		2:
			_stage = 3
			_run_combat_checks()
			_test_demo_reel()
			_report()
			return true
	return false

var _combat_stage_padding := 0

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
	_check(count >= 14, "all %d shaders checked" % count)

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

func _test_polyhaven_planner() -> void:
	print("-- Poly Haven planner")
	# The editor plugin re-implements the /files/<slug> parsing that
	# tools/fetch_polyhaven.py does, so it gets the same fixtures. A drift
	# between the two would only show up as silently missing maps.
	var api := PolyHavenAPI.new()
	var texture_files := {
		"blend": {"4k": {"blend": {"url": "https://x/rock_ground_4k.blend"}}},
		"Diffuse": {
			"1k": {"jpg": {"url": "https://x/rock_ground_diff_1k.jpg"}},
			"2k": {"jpg": {"url": "https://x/rock_ground_diff_2k.jpg"}, "png": {"url": "https://x/d.png"}},
		},
		"nor_gl": {"2k": {"exr": {"url": "https://x/rock_ground_nor_gl_2k.exr"}}},
		"nor_dx": {"2k": {"exr": {"url": "https://x/rock_ground_nor_dx_2k.exr"}}},
		"Rough": {"2k": {"exr": {"url": "https://x/rock_ground_rough_2k.exr"}}},
		"AO": {"2k": {"jpg": {"url": "https://x/rock_ground_ao_2k.jpg"}}},
		"Displacement": {"2k": {"png": {"url": "https://x/rock_ground_disp_2k.png"}}},
		"arm": {"2k": {"jpg": {"url": "https://x/rock_ground_arm_2k.jpg"}}},
	}
	var jobs: Array = []
	var entry := api._plan_texture("rock_ground", texture_files, "2k", jobs)
	for key in ["diffuse", "normal", "rough", "ao", "disp", "arm"]:
		_check(entry.has(key), "texture map '%s' planned" % key)
	_check(String(entry["normal"]).contains("_normal_2k"), "OpenGL normal preferred over DirectX")
	_check(String(entry["diffuse"]).ends_with(".jpg"), "jpg preferred over png")
	_check(String(entry["diffuse"]).contains("_2k"), "requested resolution used")
	_check(String(entry["diffuse"]).begins_with("res://assets/polyhaven/"), "res:// destination")
	var blend_planned := false
	for job in jobs:
		if String(job[0]).ends_with(".blend"):
			blend_planned = true
	_check(not blend_planned, ".blend not queued for a texture set")

	var hdri_jobs: Array = []
	var hdri := api._plan_hdri("kloppenheim", {
		"hdri": {"1k": {"hdr": {"url": "https://x/k_1k.hdr"}, "exr": {"url": "https://x/k_1k.exr"}},
				 "4k": {"hdr": {"url": "https://x/k_4k.hdr"}}},
		"tonemapped": {"jpg": {"url": "https://x/k.jpg"}},
	}, "4k", hdri_jobs)
	_check(hdri.ends_with("_4k.hdr"), "HDRI resolution and format (%s)" % hdri)
	_check(hdri_jobs.size() == 1, "one HDRI download queued")

	var model_jobs: Array = []
	var model := api._plan_model("tree_small_02", {
		"gltf": {"2k": {"gltf": {
			"url": "https://x/tree_small_02_2k.gltf",
			"include": {
				"tree_small_02_2k.bin": {"url": "https://x/tree_small_02_2k.bin"},
				"textures/diff_2k.jpg": {"url": "https://x/textures/diff_2k.jpg"},
			}}}},
	}, "2k", model_jobs)
	_check(String(model.get("scene", "")).ends_with(".gltf"), "model scene path")
	var kept_relative := false
	for job in model_jobs:
		if String(job[1]).ends_with("textures/diff_2k.jpg"):
			kept_relative = true
	_check(kept_relative, "glTF texture keeps its relative folder")
	_check(model_jobs.size() == 3, "gltf + bin + texture queued (%d)" % model_jobs.size())
	api.free()

func _test_animation() -> void:
	print("-- Procedural animation")
	var hero := DigiHariMan.create_node({"quality": 1.0})
	root.add_child(hero)
	var skeleton := hero.get_child(0) as Skeleton3D
	var animator := HumanoidAnimator.new(skeleton)
	hero.add_child(animator)
	animator.ground_raycast = false
	animator.speed = 6.0
	animator.move_local = Vector3(0, 0, -1)
	animator.grounded = true

	var rest_hand := skeleton.get_bone_global_pose(skeleton.find_bone("Hand.R")).origin
	var rest_foot := skeleton.get_bone_global_pose(skeleton.find_bone("Foot.L")).origin
	var moved_hand := 0.0
	var moved_foot := 0.0
	var finite := true
	for i in 40:
		animator.update(1.0 / 60.0)
		skeleton.force_update_all_bone_transforms()
		for b in skeleton.get_bone_count():
			var o := skeleton.get_bone_global_pose(b).origin
			if is_nan(o.x) or is_nan(o.y) or is_nan(o.z) or o.length() > 8.0:
				finite = false
		moved_hand = maxf(moved_hand, rest_hand.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone("Hand.R")).origin))
		moved_foot = maxf(moved_foot, rest_foot.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone("Foot.L")).origin))

	# An animator that silently fails to bind its bones poses nothing at all,
	# which is invisible in code review and obvious only on screen.
	_check(moved_foot > 0.15, "walk cycle drives the feet (%.3f m)" % moved_foot)
	_check(moved_hand > 0.08, "arms swing (%.3f m)" % moved_hand)
	_check(finite, "no NaN or exploded bones over 40 ticks")

	var attack_hand := 0.0
	animator.attack_pose = "smash"
	for i in 20:
		animator.attack_time = float(i) / 19.0
		animator.update(1.0 / 60.0)
		skeleton.force_update_all_bone_transforms()
		attack_hand = maxf(attack_hand, rest_hand.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone("Hand.R")).origin))
	_check(attack_hand > 0.3, "attack pose swings the striking arm (%.3f m)" % attack_hand)
	hero.queue_free()

	print("-- Quadruped animation")
	var beast := Monster.create_node(Monster.Kind.STALKER, {"quality": 1.0})
	root.add_child(beast)
	var beast_skeleton := beast.get_child(0) as Skeleton3D
	var beast_animator := MonsterAnimator.new(beast_skeleton)
	beast.add_child(beast_animator)
	beast_animator.speed = 6.0
	beast_animator.move_local = Vector3(0, 0, -1)
	var rest_paw := beast_skeleton.get_bone_global_pose(beast_skeleton.find_bone("FrontFoot.L")).origin
	var rest_tail := beast_skeleton.get_bone_global_pose(beast_skeleton.find_bone("Tail4")).origin
	var moved_paw := 0.0
	var moved_tail := 0.0
	var beast_finite := true
	for i in 40:
		beast_animator.turn_rate = sin(float(i) * 0.3)
		beast_animator.update(1.0 / 60.0)
		beast_skeleton.force_update_all_bone_transforms()
		for b in beast_skeleton.get_bone_count():
			var o := beast_skeleton.get_bone_global_pose(b).origin
			if is_nan(o.x) or is_nan(o.y) or is_nan(o.z) or o.length() > 12.0:
				beast_finite = false
		moved_paw = maxf(moved_paw, rest_paw.distance_to(beast_skeleton.get_bone_global_pose(beast_skeleton.find_bone("FrontFoot.L")).origin))
		moved_tail = maxf(moved_tail, rest_tail.distance_to(beast_skeleton.get_bone_global_pose(beast_skeleton.find_bone("Tail4")).origin))
	_check(moved_paw > 0.15, "trot drives the front paw (%.3f m)" % moved_paw)
	_check(moved_tail > 0.02, "tail chain follows the turn (%.3f m)" % moved_tail)
	_check(beast_finite, "no NaN or exploded bones over 40 ticks")
	beast.queue_free()

func _test_audio() -> void:
	print("-- Procedural audio")
	var names := ["slash_1", "slash_2", "slash_3", "impact", "impact_heavy", "dash",
		"jump", "land", "bolt_fire", "bolt_hit", "hurt", "enemy_die", "growl",
		"wave_start", "toast", "footstep", "wind_loop", "hum_loop"]
	var all_ok := true
	for name in names:
		var stream := SoundBank.get_stream(name)
		if stream == null or stream.data.size() < 512:
			all_ok = false
			printerr("     %s missing or too short" % name)
			continue
		# A silent buffer means a recipe multiplied itself to zero somewhere.
		var peak := 0
		var data := stream.data
		var count := data.size() / 2
		var step := maxi(count / 512, 1)
		for i in range(0, count, step):
			peak = maxi(peak, absi(data.decode_s16(i * 2)))
		if peak < 2000:
			all_ok = false
			printerr("     %s is near-silent (peak %d)" % [name, peak])
	_check(all_ok, "all %d clips synthesise with signal" % names.size())
	var wind := SoundBank.get_stream("wind_loop")
	_check(wind.loop_mode == AudioStreamWAV.LOOP_FORWARD, "ambient loops marked as loops")
	var again := SoundBank.get_stream("impact")
	_check(again == SoundBank.get_stream("impact"), "clip cache returns the same stream")

## Autoload identifiers are not resolvable when this script is compiled via
## --script (it parses before the autoloads register), so they are fetched by
## node path at runtime instead.
var _game: Node = null
var _signals: Node = null

var _combat_frames: int = 0
# Loaded at runtime: a global class whose script references autoloads cannot be
# resolved by name from a --script file (this file parses before the autoloads
# register, which poisons those class bindings with a failed compile).
var _combat_player: CharacterBody3D = null
var _combat_monster: CharacterBody3D = null
var _player_max_health: float = 0.0
var _died_events: Array = []
var _damaged_events: Array = []

func _setup_combat() -> void:
	print("-- Combat logic")
	_game = root.get_node("/root/Game")
	_signals = root.get_node("/root/Signals")
	var arena := Node3D.new()
	root.add_child(arena)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	arena.add_child(floor_body)

	var player_script: GDScript = load("res://src/player/player.gd")
	_player_max_health = float(player_script.get_script_constant_map()["MAX_HEALTH"])
	_combat_player = player_script.new()
	arena.add_child(_combat_player)
	_combat_player.global_position = Vector3(0, 0.2, 0)

	var agent_script: GDScript = load("res://src/ai/monster_agent.gd")
	_combat_monster = agent_script.new()
	_combat_monster.call("setup", Monster.Kind.SWARMER)
	_combat_monster.set("target", _combat_player)
	arena.add_child(_combat_monster)
	_combat_monster.global_position = Vector3(0, 0.2, -30.0)

	_game.set("enemies_alive", 1)
	_signals.connect("enemy_died", func(enemy: Node3D, pos: Vector3) -> void: _died_events.append([enemy, pos]))
	_signals.connect("enemy_damaged", func(enemy: Node3D, amount: float, crit: bool, _pos: Vector3) -> void:
		_damaged_events.append([enemy, amount, crit]))

func _run_combat_checks() -> void:
	var monster := _combat_monster
	var player := _combat_player
	_check(monster != null and player != null, "combat actors constructed")
	if monster == null or player == null:
		return
	_check(bool(monster.call("is_alive")), "monster alive after spawn settling")
	_check(monster.is_in_group("enemy"), "monster registered in enemy group")
	_check(float(player.get("health")) == _player_max_health, "player at full health")

	# --- damage pipeline ---------------------------------------------------
	var before := float(monster.get("health"))
	monster.call("take_damage", 30.0, monster.global_position + Vector3(0, 1, 1), Vector3.FORWARD, false)
	_check(float(monster.get("health")) == before - 30.0, "damage subtracts health")
	_check(_damaged_events.size() == 1 and float(_damaged_events[0][1]) == 30.0, "enemy_damaged signal carries the amount")

	# --- player i-frames ---------------------------------------------------
	player.call("take_damage", 20.0, player.global_position + Vector3(0, 1, 2), Vector3.BACK, false)
	var after_first := float(player.get("health"))
	player.call("take_damage", 20.0, player.global_position + Vector3(0, 1, 2), Vector3.BACK, false)
	_check(after_first == _player_max_health - 20.0, "player takes the first hit")
	_check(float(player.get("health")) == after_first, "invulnerability window blocks the immediate second hit")
	player.call("heal", 999.0)
	_check(float(player.get("health")) == _player_max_health, "heal clamps to max")

	# --- demo immortality ---------------------------------------------------
	_game.set("demo_mode", true)
	player.set("_invulnerable", 0.0)
	player.call("take_damage", 99999.0, player.global_position + Vector3(0, 1, 2), Vector3.BACK, true)
	_check(float(player.get("health")) >= 1.0 and bool(player.get("alive")),
		"demo mode caps damage below lethal")
	_game.set("demo_mode", false)
	player.call("heal", 999.0)

	# --- lethal damage ------------------------------------------------------
	monster.call("take_damage", 9999.0, monster.global_position + Vector3(0, 1, 1), Vector3.FORWARD, true)
	_check(not bool(monster.call("is_alive")), "lethal damage kills")
	_check(_died_events.size() == 1, "enemy_died emitted exactly once")
	_check(int(_game.get("enemies_alive")) == 0, "wave counter decremented")
	_check(int(_game.get("score")) > 0, "score awarded on kill")
	monster.call("take_damage", 10.0, monster.global_position, Vector3.FORWARD, false)
	_check(_died_events.size() == 1, "corpse takes no further death events")

	# --- freed-reference hygiene -------------------------------------------
	# A restart frees the whole scene while the Game autoload survives; every
	# consumer must see null, not a dangling pointer (casting one trips the
	# debugger and freezes the game — observed live on hud.gd's reticle draw).
	player.set("lock_on_target", monster)
	monster.free()
	player.call("_physics_process", 1.0 / 120.0)
	_check(player.get("lock_on_target") == null, "freed lock-on target is dropped")
	_combat_monster = null
	player.free()
	_combat_player = null
	_check(_game.call("alive_player") == null, "alive_player() nulls after the player is freed")

func _test_demo_reel() -> void:
	print("-- Demo reel")
	var main_stub := Node3D.new()
	root.add_child(main_stub)
	var demo_script: GDScript = load("res://src/core/demo_director.gd")
	var demo: Node = demo_script.new(main_stub)
	main_stub.add_child(demo)

	# The reel must cover the full 60 seconds with a finite camera transform at
	# every sampled instant, and the cuts must land where the reel says.
	var expected := {0.0: "establish", 12.0: "street", 25.0: "hero",
		40.0: "combat", 50.0: "low", 57.0: "outro"}
	var all_finite := true
	for t in range(0, 61):
		demo.call("seek", float(t))
		var cam := demo.get_node("DemoCamera") as Camera3D
		var o := cam.transform.origin
		if is_nan(o.x) or is_nan(o.y) or is_nan(o.z) or o.length() > 500.0:
			all_finite = false
			printerr("     bad camera at t=%d: %s" % [t, o])
	_check(all_finite, "camera finite across 61 sampled seconds")
	var cuts_ok := true
	for t in expected.keys():
		var got := String(demo.call("shot_name_at", float(t)))
		if got != String(expected[t]):
			cuts_ok = false
			printerr("     t=%.0f expected %s got %s" % [t, expected[t], got])
	_check(cuts_ok, "cut points land on the intended shots")
	_check(float(demo.get("DURATION")) == 60.0, "reel is exactly 60 seconds")
	main_stub.queue_free()
