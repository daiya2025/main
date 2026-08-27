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
		var mesh := BoxMesh.new()
		mesh.size = Vector3(w, h, d)
		var mi := MeshInstance3D.new()
		mi.name = "Bldg_%d_%d_%d" % [cx, cz, i]
		mi.mesh = mesh
		mi.material_override = _facade_material
		mi.position = Vector3(cx + ox, h * 0.5, cz + oz)
		mi.rotation.y = rng.randf_range(-0.06, 0.06)
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		add_child(mi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
		building_count += 1


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
