class_name CityLoader
extends Node3D
## 都市の構築。
## - tools/fetch_plateau.py が生成した PLATEAU 実測 OBJ (game/assets/city/) があればそれを読み込み、
##   テクスチャ無し面には夜の窓明かりが灯るファサードシェーダーを適用する。
## - 無ければ渋谷風の手続き生成シティ (スクランブル交差点 + ビル群) でフォールバック。
## - 路面は Poly Haven アスファルト PBR + 濡れ表現シェーダー。

const CITY_MANIFEST := "res://assets/city/city_manifest.json"
const FACADE_SHADER := "res://shaders/building_facade.gdshader"
const ROAD_SHADER := "res://shaders/wet_road.gdshader"

var night_factor := 1.0
var loaded_real_city := false
var building_count := 0

var _facade_material: ShaderMaterial


func build(p_night_factor: float) -> void:
	night_factor = p_night_factor
	_facade_material = _make_facade_material()
	_build_ground()
	if not _load_plateau_city():
		_build_procedural_city()


func _make_facade_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(FACADE_SHADER)
	mat.set_shader_parameter("night_factor", night_factor)
	return mat


# ------------------------------------------------------------------ PLATEAU

func _load_plateau_city() -> bool:
	if not FileAccess.file_exists(CITY_MANIFEST):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CITY_MANIFEST))
	if not (parsed is Dictionary):
		return false
	var files: Array = parsed.get("files", [])
	var loaded := 0
	for entry in files:
		var obj_path := "res://assets/city/%s" % entry.get("obj", "")
		if not ResourceLoader.exists(obj_path):
			continue
		var mesh := load(obj_path) as Mesh
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Plateau_%s" % String(entry.get("obj", "tile")).get_basename()
		mi.mesh = _enhance_city_mesh(mesh)
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		add_child(mi)
		_add_trimesh_collision(mi)
		loaded += 1
		building_count += int(entry.get("buildings", 0))
	if loaded > 0:
		loaded_real_city = true
		print("[City] PLATEAU 実測都市を読み込み: %d タイル / %d 棟" % [loaded, building_count])
	return loaded > 0


## OBJ の各サーフェスを検査し、テクスチャ付きは PBR 調整、無地はファサードシェーダーに差し替え
func _enhance_city_mesh(mesh: Mesh) -> Mesh:
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		var std := mat as StandardMaterial3D
		if std and std.albedo_texture:
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			std.roughness = 0.82
			std.metallic_specular = 0.35
			std.metallic = 0.0
		else:
			mesh.surface_set_material(i, _facade_material)
	return mesh


func _add_trimesh_collision(mi: MeshInstance3D) -> void:
	var shape := mi.mesh.create_trimesh_shape()
	if shape == null:
		return
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)


# ------------------------------------------------------------------ 手続き生成フォールバック

const BLOCK := 46.0        # 街区ピッチ
const STREET := 14.0       # 道路幅
const PLAZA_RADIUS := 52.0 # スクランブル交差点広場
const CITY_EXTENT := 5     # 街区数 (片側)


func _build_procedural_city() -> void:
	print("[City] PLATEAU データ未取得 → 手続き生成シティで起動 (tools/fetch_plateau.py で実データ化)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1091  # 渋谷
	for gx in range(-CITY_EXTENT, CITY_EXTENT + 1):
		for gz in range(-CITY_EXTENT, CITY_EXTENT + 1):
			var cx := gx * BLOCK
			var cz := gz * BLOCK
			var dist := Vector2(cx, cz).length()
			if dist < PLAZA_RADIUS:
				continue
			# 大通り (十字 + 斜め) を空ける
			if absf(cx) < STREET or absf(cz) < STREET:
				continue
			_spawn_block(rng, cx, cz, dist)
	print("[City] 手続き生成ビル %d 棟" % building_count)


func _spawn_block(rng: RandomNumberGenerator, cx: float, cz: float, dist: float) -> void:
	var n := rng.randi_range(1, 3)
	for i in n:
		var w := rng.randf_range(14, 30)
		var d := rng.randf_range(14, 30)
		var closeness := clampf(1.0 - (dist - PLAZA_RADIUS) / 260.0, 0.0, 1.0)
		var h := rng.randf_range(12, 40) + closeness * rng.randf_range(20, 110)
		var ox := rng.randf_range(-8, 8)
		var oz := rng.randf_range(-8, 8)
		_spawn_building(rng, Vector3(cx + ox, 0, cz + oz), w, d, h, closeness)
		building_count += 1


## アーキタイプ付きビル1棟: 基壇 + タワー + セットバック + パラペット + 屋上設備 + 看板
func _spawn_building(rng: RandomNumberGenerator, base_pos: Vector3,
		w: float, d: float, h: float, closeness: float) -> void:
	var b := Node3D.new()
	b.name = "Bldg"
	b.position = base_pos
	b.rotation.y = rng.randf_range(-0.06, 0.06)
	add_child(b)

	var concrete := MatLib.concrete_fallback()
	var metal := MatLib.metal(Color(0.5, 0.52, 0.55), 0.5)

	# --- 基壇 (ポディウム) ---
	var podium_h := 0.0
	if h > 28.0 and rng.randf() < 0.7:
		podium_h = rng.randf_range(5.0, 9.0)
		_box_part(b, Vector3(w * 1.18, podium_h, d * 1.18), Vector3(0, podium_h * 0.5, 0), _facade_material)
		_box_part(b, Vector3(w * 1.22, 0.5, d * 1.22), Vector3(0, podium_h + 0.25, 0), concrete)

	# --- タワー本体 (箱 / 円筒 / L字 の3形状 + セットバック) ---
	var tower_h := h - podium_h
	var setback := h > 55.0 and rng.randf() < 0.55
	var lower_h := tower_h * (0.62 if setback else 1.0)
	var shape_roll := rng.randf()
	var cylindrical := shape_roll < 0.16 and h > 35.0
	if cylindrical:
		var cyl := CylinderMesh.new()
		cyl.top_radius = minf(w, d) * 0.5
		cyl.bottom_radius = cyl.top_radius
		cyl.height = lower_h
		cyl.radial_segments = 24
		var cmi := MeshInstance3D.new()
		cmi.mesh = cyl
		cmi.material_override = _facade_material
		cmi.position = Vector3(0, podium_h + lower_h * 0.5, 0)
		cmi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		b.add_child(cmi)
	else:
		_box_part(b, Vector3(w, lower_h, d), Vector3(0, podium_h + lower_h * 0.5, 0), _facade_material)
		if shape_roll < 0.42:  # L字: 直交する副翼
			_box_part(b, Vector3(w * 0.55, lower_h * rng.randf_range(0.7, 1.0), d * 0.55),
					Vector3(w * 0.42, podium_h + lower_h * 0.35, d * 0.42), _facade_material)
		# コーナーの付柱 (垂直リブ)
		if closeness > 0.25:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_box_part(b, Vector3(0.55, lower_h, 0.55),
							Vector3(sx * w * 0.5, podium_h + lower_h * 0.5, sz * d * 0.5), concrete)
	var top_y := podium_h + lower_h
	var top_w := w
	var top_d := d
	if setback:
		top_w = w * rng.randf_range(0.6, 0.78)
		top_d = d * rng.randf_range(0.6, 0.78)
		var upper_h := tower_h - lower_h
		_box_part(b, Vector3(top_w, upper_h, top_d), Vector3(0, top_y + upper_h * 0.5, 0), _facade_material)
		# 下段屋上のパラペット
		_box_part(b, Vector3(w + 0.5, 0.7, d + 0.5), Vector3(0, top_y + 0.35, 0), concrete)
		top_y += upper_h

	# エントランス庇 + 支柱 (中心街のみ)
	if closeness > 0.35 and not cylindrical:
		var front := -1.0 if base_pos.z > 0 else 1.0
		_box_part(b, Vector3(w * 0.5, 0.3, 3.0), Vector3(0, 3.9, front * (d * 0.5 + 1.5)), metal)
		for sx in [-1.0, 1.0]:
			_box_part(b, Vector3(0.18, 3.8, 0.18),
					Vector3(sx * w * 0.2, 1.9, front * (d * 0.5 + 2.6)), metal)

	# 高層ビルのクラウン照明 (渋谷の頂部ライン)
	if h > 68.0:
		var crown_colors := [Color(0.4, 0.8, 1.0), Color(1.0, 0.35, 0.5), Color(0.9, 0.8, 0.5), Color(0.5, 1.0, 0.7)]
		var crown := MatLib.emissive(crown_colors[rng.randi() % crown_colors.size()], 2.8)
		_box_part(b, Vector3(top_w + 0.35, 1.1, top_d + 0.35), Vector3(0, top_y - 0.8, 0), crown)

	# --- 屋上: パラペット + 手すり + 設備 ---
	_box_part(b, Vector3(top_w + 0.4, 0.8, top_d + 0.4), Vector3(0, top_y + 0.4, 0), concrete)
	var roof_y := top_y + 0.8
	if h > 38.0 and not cylindrical:
		for side_rail in [-1.0, 1.0]:
			_box_part(b, Vector3(top_w, 0.9, 0.07), Vector3(0, roof_y + 0.45, side_rail * top_d * 0.48), metal)
			_box_part(b, Vector3(0.07, 0.9, top_d), Vector3(side_rail * top_w * 0.48, roof_y + 0.45, 0), metal)
	for _k in rng.randi_range(1, 3):  # 室外機・キュービクル
		_box_part(b, Vector3(rng.randf_range(1.5, 3.5), rng.randf_range(1.0, 2.0), rng.randf_range(1.5, 3.0)),
				Vector3(rng.randf_range(-0.3, 0.3) * top_w, roof_y + 0.8, rng.randf_range(-0.3, 0.3) * top_d),
				metal)
	if rng.randf() < 0.5:  # ペントハウス (階段室)
		_box_part(b, Vector3(top_w * 0.3, 3.0, top_d * 0.3),
				Vector3(top_w * 0.25, roof_y + 1.5, -top_d * 0.2), _facade_material)
	if rng.randf() < 0.4:  # 高架水槽
		var tank := MatLib.mesh_node(MatLib.cone(1.1, 2.4, 1.1), metal,
				Vector3(-top_w * 0.28, roof_y + 2.0, top_d * 0.25))
		b.add_child(tank)
		_box_part(b, Vector3(0.25, 1.6, 0.25), Vector3(-top_w * 0.28, roof_y + 0.6, top_d * 0.25), metal)
	if h > 45.0 and rng.randf() < 0.6:  # アンテナ + 航空障害灯
		var mast_h := rng.randf_range(5.0, 12.0)
		_box_part(b, Vector3(0.22, mast_h, 0.22), Vector3(0, roof_y + mast_h * 0.5, 0), metal)
		var beacon := MatLib.mesh_node(MatLib.sphere(0.28), MatLib.emissive(Color(1.0, 0.1, 0.08), 5.0),
				Vector3(0, roof_y + mast_h + 0.2, 0))
		b.add_child(beacon)
	if closeness > 0.5 and rng.randf() < 0.35:  # 屋上ビルボード
		_rooftop_billboard(b, rng, top_w, top_d, roof_y)
	if closeness > 0.4 and h > 25.0 and rng.randf() < 0.5:  # 壁面の縦看板
		_vertical_sign(b, rng, w, d, minf(h, 40.0))

	# --- 当たり判定 (タワー + 基壇をまとめて1箱) ---
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(w, top_w) * (1.18 if podium_h > 0 else 1.0), h, maxf(d, top_d) * (1.18 if podium_h > 0 else 1.0))
	cs.shape = shape
	cs.position.y = h * 0.5
	body.add_child(cs)
	b.add_child(body)


func _box_part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(mi)


func _rooftop_billboard(b: Node3D, rng: RandomNumberGenerator, top_w: float, top_d: float, roof_y: float) -> void:
	var bw := clampf(top_w * 0.8, 4.0, 14.0)
	var bh := bw * 0.45
	var frame := MatLib.metal(Color(0.3, 0.3, 0.32), 0.6)
	_box_part(b, Vector3(0.3, bh * 0.6, 0.3), Vector3(-bw * 0.35, roof_y + bh * 0.3, 0), frame)
	_box_part(b, Vector3(0.3, bh * 0.6, 0.3), Vector3(bw * 0.35, roof_y + bh * 0.3, 0), frame)
	var quad := QuadMesh.new()
	quad.size = Vector2(bw, bh)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/neon_holo.gdshader")
	mat.set_shader_parameter("scroll_speed", rng.randf_range(0.15, 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position = Vector3(0, roof_y + bh * 0.6 + bh * 0.5, 0)
	mi.rotation.y = rng.randf_range(0, TAU)
	b.add_child(mi)


func _vertical_sign(b: Node3D, rng: RandomNumberGenerator, w: float, d: float, max_h: float) -> void:
	var sh := rng.randf_range(8.0, minf(max_h - 6.0, 18.0))
	var sw := rng.randf_range(1.4, 2.2)
	var y := rng.randf_range(5.0, max_h - sh)
	var sides: Array = [Vector3(w * 0.5 + sw * 0.55, 0, d * 0.3), Vector3(-w * 0.5 - sw * 0.55, 0, -d * 0.25),
			Vector3(w * 0.3, 0, d * 0.5 + sw * 0.55)]
	var side: Vector3 = sides[rng.randi() % 3]
	var box := BoxMesh.new()
	box.size = Vector3(sw, sh, 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/neon_holo.gdshader")
	var hues := [[Color(1.0, 0.1, 0.4), Color(1.0, 0.7, 0.1)], [Color(0.1, 0.9, 0.9), Color(0.9, 0.2, 1.0)],
			[Color(0.2, 1.0, 0.4), Color(1.0, 0.9, 0.2)]]
	var pair: Array = hues[rng.randi() % hues.size()]
	mat.set_shader_parameter("color_a", pair[0])
	mat.set_shader_parameter("color_b", pair[1])
	mat.set_shader_parameter("glyph_density", 4.0)
	mat.set_shader_parameter("scroll_speed", rng.randf_range(0.1, 0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = side + Vector3(0, y + sh * 0.5, 0)
	b.add_child(mi)


# ------------------------------------------------------------------ 路面

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400, 2400)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = _make_road_material()
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2400, 1.0, 2400)
	cs.shape = shape
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)


func _make_road_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(ROAD_SHADER)
	mat.set_shader_parameter("wetness", 0.85 if night_factor > 0.5 else 0.25)
	var maps := PolyHavenAssets.pbr_maps("asphalt")
	if maps.has("albedo"):
		mat.set_shader_parameter("use_textures", true)
		mat.set_shader_parameter("albedo_tex", maps["albedo"])
		if maps.has("normal"):
			mat.set_shader_parameter("normal_tex", maps["normal"])
		if maps.has("rough"):
			mat.set_shader_parameter("rough_tex", maps["rough"])
		if maps.has("ao"):
			mat.set_shader_parameter("ao_tex", maps["ao"])
		print("[City] 路面: Poly Haven アスファルト PBR + 濡れ表現")
	else:
		print("[City] 路面: フォールバック (手続きアスファルト)")
	return mat
