class_name CityProps
extends Node3D
## 街の演出要素:
## - 上空の「次元の裂け目」(ゲームの世界観の核)
## - ネオンホログラム広告 / 街灯 (クラスタードライティングで大量配置)
## - Poly Haven フォトグラメトリの樹木・岩の散布

var night_factor := 1.0
var rift_mesh: MeshInstance3D
var rift_light: OmniLight3D


func build(p_night_factor: float) -> void:
	night_factor = p_night_factor
	_build_rift()
	_build_neon_billboards()
	_build_streetlights()
	_build_street_furniture()
	_scatter_nature()


func _build_rift() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(56, 72)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rift.gdshader")
	rift_mesh = MeshInstance3D.new()
	rift_mesh.name = "Rift"
	rift_mesh.mesh = quad
	rift_mesh.material_override = mat
	rift_mesh.position = Vector3(0, 58, -30)
	rift_mesh.rotation_degrees = Vector3(8, 15, 6)
	add_child(rift_mesh)
	rift_light = OmniLight3D.new()
	rift_light.light_color = Color(1.0, 0.2, 0.55)
	rift_light.light_energy = 6.0
	rift_light.omni_range = 100.0
	rift_light.omni_attenuation = 1.6
	rift_light.position = rift_mesh.position
	add_child(rift_light)


## デモ演出: 裂け目を隠す / 誕生アニメーション
func set_rift_active(active: bool) -> void:
	rift_mesh.visible = active
	rift_light.visible = active


func rift_birth(duration: float = 2.5) -> void:
	rift_mesh.visible = true
	rift_light.visible = true
	rift_mesh.scale = Vector3(0.04, 0.01, 1.0)
	rift_light.light_energy = 0.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(rift_mesh, "scale", Vector3(0.06, 1.0, 1.0), duration * 0.4)
	tw.tween_property(rift_mesh, "scale", Vector3.ONE, duration * 0.6)
	var tw2 := create_tween()
	tw2.tween_property(rift_light, "light_energy", 22.0, duration * 0.3)
	tw2.tween_property(rift_light, "light_energy", 6.0, duration * 0.7)


## ガードレール / 歩行者信号 / 自販機 — 日本の街路ディテール
func _build_street_furniture() -> void:
	var white := MatLib.metal(Color(0.85, 0.86, 0.88), 0.45)
	var pole_mat := MatLib.metal(Color(0.35, 0.37, 0.4), 0.5)
	# ガードレール: 十字大通りの歩道際 (交差点部は開ける)
	for axis: int in [0, 1]:
		for side: float in [-1.0, 1.0]:
			for dir: float in [-1.0, 1.0]:
				var rail_len := 0.0
				var start := 26.0
				while start + rail_len < 130.0:
					rail_len = 24.0
					var center_d: float = (start + rail_len * 0.5) * dir
					var off: float = side * 12.5
					var pos := Vector3(center_d, 0, off) if axis == 0 else Vector3(off, 0, center_d)
					var rot := 0.0 if axis == 0 else PI * 0.5
					var beam := MatLib.mesh_node(MatLib.box(Vector3(rail_len, 0.12, 0.06)), white,
							pos + Vector3(0, 0.75, 0))
					beam.rotation.y = rot
					add_child(beam)
					for k in int(rail_len / 4.0) + 1:
						var t := -rail_len * 0.5 + k * 4.0
						var ppos := pos + (Vector3(t, 0.4, 0) if axis == 0 else Vector3(0, 0.4, t))
						add_child(MatLib.mesh_node(MatLib.cone(0.05, 0.8, 0.05), white, ppos))
					start += rail_len + 10.0
	# 歩行者信号 (交差点4隅)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base := Vector3(sx * 11.0, 0, sz * 11.0)
			add_child(MatLib.mesh_node(MatLib.cone(0.07, 3.0, 0.06), pole_mat, base + Vector3(0, 1.5, 0)))
			var housing := MatLib.mesh_node(MatLib.box(Vector3(0.35, 0.75, 0.18)), pole_mat,
					base + Vector3(0, 3.0, 0))
			housing.rotation.y = atan2(-sx, -sz)
			add_child(housing)
			var green := sin(sx * sz) >= 0.0
			var lamp := MatLib.mesh_node(MatLib.sphere(0.09),
					MatLib.emissive(Color(0.2, 1.0, 0.5) if green else Color(1.0, 0.25, 0.2), 4.0),
					base + Vector3(0, 3.0 + (-0.18 if green else 0.18), 0))
			lamp.position += Vector3(-sx * 0.1, 0, -sz * 0.1)
			add_child(lamp)
	# 自販機 (ビル際にポツポツ)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var vend_colors := [Color(0.9, 0.15, 0.15), Color(0.15, 0.4, 0.95), Color(0.95, 0.95, 0.95)]
	for i in 8:
		var ang := TAU * i / 8.0 + rng.randf_range(-0.2, 0.2)
		var radius := rng.randf_range(56.0, 90.0)
		var pos := Vector3(cos(ang) * radius, 0, sin(ang) * radius)
		var vcol: Color = vend_colors[rng.randi() % vend_colors.size()]
		var bodym := MatLib.metal(vcol, 0.35)
		var vend := MatLib.mesh_node(MatLib.box(Vector3(1.1, 1.9, 0.75)), bodym, pos + Vector3(0, 0.95, 0))
		vend.rotation.y = rng.randf() * TAU
		add_child(vend)
		var panel := MatLib.mesh_node(MatLib.box(Vector3(0.85, 1.0, 0.05)),
				MatLib.emissive(Color(1.0, 0.95, 0.85), 3.0), Vector3(0, 0.25, 0.4))
		vend.add_child(panel)
		var vl := OmniLight3D.new()
		vl.light_color = Color(1.0, 0.95, 0.85)
		vl.light_energy = 1.2
		vl.omni_range = 6.0
		vl.position = Vector3(0, 0.3, 1.0)
		vl.shadow_enabled = false
		vend.add_child(vl)


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
	for i in 20:
		var ang := TAU * i / 20.0 + rng.randf_range(-0.15, 0.15)
		var radius := rng.randf_range(30.0, 62.0)
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
		l.light_energy = 2.4
		l.omni_range = 26.0
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
		l.light_energy = 3.8
		l.omni_range = 22.0
		l.omni_attenuation = 1.4
		l.position = lamp_pos + Vector3(0, -0.3, 0)
		l.shadow_enabled = i % 3 == 0  # 影は間引いて品質と負荷のバランスを取る
		add_child(l)
		# 雨夜の光芒コーン (フェイクボリュームライト)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.16
		shaft.bottom_radius = 1.7
		shaft.height = 5.2
		shaft.radial_segments = 20
		shaft.cap_top = false
		shaft.cap_bottom = false
		var shaft_mat := ShaderMaterial.new()
		shaft_mat.shader = load("res://shaders/light_shaft.gdshader")
		var smi := MeshInstance3D.new()
		smi.mesh = shaft
		smi.material_override = shaft_mat
		smi.position = lamp_pos + Vector3(0, -2.75, 0)
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(smi)


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
