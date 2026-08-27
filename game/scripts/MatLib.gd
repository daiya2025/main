class_name MatLib
extends Object
## 手続きマテリアル/ノイズテクスチャのライブラリ。
## Poly Haven アセットが無い環境でも見栄えが破綻しないための基盤 + キャラクター用素材。

static var _noise_cache: Dictionary = {}


static func noise_texture(seed_val: int = 0, freq: float = 0.02, as_normal: bool = false) -> NoiseTexture2D:
	var key := "%d_%f_%s" % [seed_val, freq, as_normal]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = freq
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = as_normal
	if as_normal:
		tex.bump_strength = 4.0
	_noise_cache[key] = tex
	return tex


static func skin(tone: Color = Color(0.87, 0.68, 0.57)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tone
	m.roughness = 0.55
	m.metallic = 0.0
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.6
	m.subsurf_scatter_skin_mode = true
	m.normal_enabled = true
	m.normal_texture = noise_texture(11, 0.15, true)
	m.normal_scale = 0.15
	m.metallic_specular = 0.35
	return m


static func fabric(color: Color, rough: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.normal_enabled = true
	m.normal_texture = noise_texture(23, 0.35, true)
	m.normal_scale = 0.5
	m.metallic_specular = 0.2
	return m


static func leather(color: Color = Color(0.09, 0.09, 0.11)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	m.clearcoat_enabled = true
	m.clearcoat = 0.4
	m.clearcoat_roughness = 0.4
	m.normal_enabled = true
	m.normal_texture = noise_texture(37, 0.25, true)
	m.normal_scale = 0.3
	return m


static func metal(color: Color = Color(0.75, 0.76, 0.78), rough: float = 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 1.0
	m.roughness = rough
	return m


static func hair(color: Color = Color(0.08, 0.07, 0.07)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.35
	m.anisotropy_enabled = true
	m.anisotropy = 0.8
	m.metallic_specular = 0.5
	return m


static func eye() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.96, 0.95)
	m.roughness = 0.05
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.05
	return m


static func emissive(color: Color, energy: float = 4.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func concrete_fallback() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.42, 0.43)
	m.roughness = 0.92
	m.normal_enabled = true
	m.normal_texture = noise_texture(51, 0.08, true)
	m.normal_scale = 0.6
	return m


## MeshInstance3D をまとめて作るヘルパ
static func mesh_node(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, node_name: String = "Part") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.001)
	return c


static func sphere(radius: float, squash: Vector3 = Vector3.ONE) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0 * squash.y
	s.radial_segments = 32
	s.rings = 16
	return s


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cone(bottom_r: float, height: float, top_r: float = 0.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom_r
	c.top_radius = top_r
	c.height = height
	return c
