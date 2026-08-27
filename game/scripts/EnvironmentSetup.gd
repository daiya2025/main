class_name EnvironmentSetup
extends Object
## ライティング / 大気 / ポストプロセスの構築。
## AAA 志向の設定: HDRI IBL + SDFGI + SSR + SSAO + SSIL + ボリュメトリックフォグ
## + ACES トーンマップ + ブルーム + 被写界深度 (CameraAttributes)。
## preset: "night" (既定 / 渋谷の雨夜) , "dusk", "day"

const PRESETS := {
	"night": {
		"sun_energy": 0.30, "sun_color": Color(0.62, 0.72, 1.0),
		"sun_dir": Vector3(-0.35, -0.5, -0.4),
		"bg_energy": 0.8, "exposure": 1.1,
		"fog_density": 0.02, "fog_albedo": Color(0.35, 0.42, 0.6),
		"night_factor": 1.0, "rain": true,
		"sky_top": Color(0.015, 0.02, 0.05), "sky_horizon": Color(0.12, 0.08, 0.16),
	},
	"dusk": {
		"sun_energy": 1.1, "sun_color": Color(1.0, 0.55, 0.3),
		"sun_dir": Vector3(-0.8, -0.18, 0.3),
		"bg_energy": 1.0, "exposure": 1.0,
		"fog_density": 0.012, "fog_albedo": Color(0.8, 0.55, 0.45),
		"night_factor": 0.5, "rain": false,
		"sky_top": Color(0.1, 0.12, 0.3), "sky_horizon": Color(0.95, 0.45, 0.2),
	},
	"day": {
		"sun_energy": 1.5, "sun_color": Color(1.0, 0.97, 0.9),
		"sun_dir": Vector3(-0.4, -0.75, -0.25),
		"bg_energy": 1.0, "exposure": 0.9,
		"fog_density": 0.004, "fog_albedo": Color(0.8, 0.85, 0.95),
		"night_factor": 0.0, "rain": false,
		"sky_top": Color(0.25, 0.45, 0.85), "sky_horizon": Color(0.75, 0.85, 0.95),
	},
}


static func setup(root: Node3D, preset_name: String) -> Dictionary:
	var p: Dictionary = PRESETS.get(preset_name, PRESETS["night"])

	var env := Environment.new()

	# --- 空: Poly Haven HDRI (無ければ手続き空) ---
	var sky := Sky.new()
	var pano := PolyHavenAssets.hdri_texture(preset_name)
	if pano:
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = pano
		sky.sky_material = sky_mat
	else:
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = p["sky_top"]
		proc.sky_horizon_color = p["sky_horizon"]
		proc.ground_bottom_color = Color(0.02, 0.02, 0.03)
		proc.ground_horizon_color = p["sky_horizon"]
		proc.sun_angle_max = 20.0
		sky.sky_material = proc
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = p["bg_energy"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# --- GI / 遮蔽 / 反射 ---
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6
	env.sdfgi_max_distance = 1200.0
	env.sdfgi_energy = 1.0
	env.ssr_enabled = true
	env.ssr_max_steps = 128
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.0
	env.ssao_power = 1.8
	env.ssil_enabled = true
	env.ssil_radius = 5.0
	env.ssil_intensity = 1.0

	# --- トーンマップ / グロー / 色調 ---
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.12

	# --- ボリュメトリックフォグ (ネオンの光芒) ---
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = p["fog_density"]
	env.volumetric_fog_albedo = p["fog_albedo"]
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_gi_inject = 1.0
	env.volumetric_fog_ambient_inject = 0.4

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env

	# --- カメラ属性 (露出 / DoF) ---
	var attrs := CameraAttributesPractical.new()
	attrs.exposure_multiplier = p["exposure"]
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_amount = 0.06
	world_env.camera_attributes = attrs
	root.add_child(world_env)

	# --- 太陽 / 月 ---
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = p["sun_energy"]
	sun.light_color = p["sun_color"]
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 500.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	var dir: Vector3 = (p["sun_dir"] as Vector3).normalized()
	sun.basis = Basis.looking_at(dir, Vector3.UP)
	root.add_child(sun)

	# --- 中心部のリフレクションプローブ (交差点の艶) ---
	var probe := ReflectionProbe.new()
	probe.name = "CrossingProbe"
	probe.size = Vector3(180, 80, 180)
	probe.position = Vector3(0, 38, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 1.0
	root.add_child(probe)

	# --- 雨 (夜プリセット) ---
	if p["rain"]:
		root.add_child(_build_rain())

	return {"world_env": world_env, "sun": sun, "attributes": attrs,
			"night_factor": p["night_factor"], "preset": preset_name}


static func _build_rain() -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 6000
	rain.lifetime = 1.4
	rain.preprocess = 1.4
	rain.visibility_aabb = AABB(Vector3(-150, -10, -150), Vector3(300, 90, 300))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(130, 1, 130)
	mat.direction = Vector3(0.15, -1, 0.05)
	mat.spread = 2.0
	mat.initial_velocity_min = 42.0
	mat.initial_velocity_max = 55.0
	mat.gravity = Vector3(0, -22, 0)
	mat.particle_flag_align_y = true
	rain.process_material = mat
	rain.position = Vector3(0, 65, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.55)
	var qmat := StandardMaterial3D.new()
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.albedo_color = Color(0.65, 0.75, 0.95, 0.18)
	qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = qmat
	rain.draw_pass_1 = quad
	return rain
