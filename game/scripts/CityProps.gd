class_name CityProps
extends Node3D
## 街の演出要素:
## - 上空の「次元の裂け目」(ゲームの世界観の核)
## - ネオンホログラム広告 / 街灯 (クラスタードライティングで大量配置)
## - Poly Haven フォトグラメトリの樹木・岩の散布

var night_factor := 1.0


func build(p_night_factor: float) -> void:
	night_factor = p_night_factor
	_build_rift()
	_build_neon_billboards()
	_build_streetlights()
	_scatter_nature()


func _build_rift() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(46, 80)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rift.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "Rift"
	mi.mesh = quad
	mi.material_override = mat
	mi.position = Vector3(0, 85, -30)
	mi.rotation_degrees = Vector3(8, 15, 6)
	add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.2, 0.55)
	l.light_energy = 6.0
	l.omni_range = 90.0
	l.omni_attenuation = 1.6
	l.position = mi.position
	add_child(l)


func _build_neon_billboards() -> void:
	if night_factor < 0.3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4649
	var palette := [
		[Color(1.0, 0.05, 0.45), Color(0.1, 0.85, 1.0)],
		[Color(1.0, 0.55, 0.05), Color(1.0, 0.1, 0.3)],
		[Color(0.2, 1.0, 0.5), Color(0.1, 0.5, 1.0)],
		[Color(0.7, 0.2, 1.0), Color(0.1, 0.9, 0.9)],
	]
	for i in 14:
		var ang := TAU * i / 14.0 + rng.randf_range(-0.15, 0.15)
		var radius := rng.randf_range(30.0, 55.0)
		var w := rng.randf_range(3.0, 7.0)
		var h := rng.randf_range(4.0, 10.0)
		var y := rng.randf_range(6.0, 26.0)
		var pos := Vector3(cos(ang) * radius, y, sin(ang) * radius)

		var quad := QuadMesh.new()
		quad.size = Vector2(w, h)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/neon_holo.gdshader")
		var colors: Array = palette[i % palette.size()]
		mat.set_shader_parameter("color_a", colors[0])
		mat.set_shader_parameter("color_b", colors[1])
		mat.set_shader_parameter("scroll_speed", rng.randf_range(0.2, 0.6))
		mat.set_shader_parameter("intensity", rng.randf_range(5.0, 10.0))

		var mi := MeshInstance3D.new()
		mi.name = "Neon%d" % i
		mi.mesh = quad
		mi.material_override = mat
		add_child(mi)
		mi.look_at_from_position(pos, Vector3(0, y, 0), Vector3.UP)

		# ネオンの照り返し
		var l := OmniLight3D.new()
		l.light_color = colors[0].lerp(colors[1], 0.5)
		l.light_energy = 1.6
		l.omni_range = 22.0
		l.position = pos + Vector3(0, -2, 0)
		l.shadow_enabled = false
		add_child(l)


func _build_streetlights() -> void:
	if night_factor < 0.3:
		return
	var pole_mat := MatLib.metal(Color(0.25, 0.26, 0.28), 0.5)
	var lamp_mat := MatLib.emissive(Color(1.0, 0.85, 0.6), 5.0)
	for i in 12:
		var ang := TAU * i / 12.0
		var pos := Vector3(cos(ang) * 24.0, 0, sin(ang) * 24.0)
		var pole := MatLib.mesh_node(MatLib.cone(0.09, 5.6, 0.07), pole_mat, pos + Vector3(0, 2.8, 0))
		add_child(pole)
		var arm := MatLib.mesh_node(MatLib.box(Vector3(0.08, 0.08, 1.2)), pole_mat,
				pos + Vector3(0, 5.5, 0))
		add_child(arm)
		arm.look_at_from_position(arm.position, Vector3(0, 5.5, 0), Vector3.UP)
		var lamp_pos := pos + (Vector3.ZERO - pos).normalized() * 1.0 + Vector3(0, 5.4, 0)
		add_child(MatLib.mesh_node(MatLib.sphere(0.14, Vector3(1, 0.5, 1)), lamp_mat, lamp_pos))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.light_energy = 2.4
		l.omni_range = 16.0
		l.omni_attenuation = 1.4
		l.position = lamp_pos + Vector3(0, -0.3, 0)
		l.shadow_enabled = i % 3 == 0  # 影は間引いて品質と負荷のバランスを取る
		add_child(l)


func _scatter_nature() -> void:
	var trees := PolyHavenAssets.model_scenes("trees")
	var rocks := PolyHavenAssets.model_scenes("rocks")
	if trees.is_empty() and rocks.is_empty():
		print("[Props] Poly Haven モデル未取得 (tools/fetch_polyhaven.py で樹木・岩を追加)")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 8931
	var n_trees := 0
	var n_rocks := 0
	# 街路樹: 広場の縁 + 大通り沿い
	if not trees.is_empty():
		for i in 36:
			var ang := TAU * i / 36.0 + rng.randf_range(-0.05, 0.05)
			var radius := 58.0 if i % 2 == 0 else rng.randf_range(70.0, 140.0)
			var pos := Vector3(cos(ang) * radius, 0, sin(ang) * radius)
			_place_scene(trees[rng.randi() % trees.size()], pos,
					rng.randf_range(0.85, 1.35), rng.randf() * TAU)
			n_trees += 1
	if not rocks.is_empty():
		for i in 16:
			var ang := rng.randf() * TAU
			var radius := rng.randf_range(45.0, 120.0)
			var pos := Vector3(cos(ang) * radius, 0, sin(ang) * radius)
			_place_scene(rocks[rng.randi() % rocks.size()], pos,
					rng.randf_range(0.7, 1.6), rng.randf() * TAU)
			n_rocks += 1
	print("[Props] フォトグラメトリ散布: 樹木 %d / 岩 %d" % [n_trees, n_rocks])


func _place_scene(scene: PackedScene, pos: Vector3, scale_f: float, yaw: float) -> void:
	var inst := scene.instantiate()
	if inst is Node3D:
		var n := inst as Node3D
		n.position = pos
		n.scale = Vector3.ONE * scale_f
		n.rotation.y = yaw
		add_child(n)
	else:
		inst.queue_free()
