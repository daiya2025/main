class_name SkyEnv
extends Node
## Lighting and atmosphere.
##
## One key light, one bounce-fill, a physically-scaled sky and a fog volume that
## the key light actually scatters through. The look is late golden hour: a low,
## warm sun raking across the district so every surface gets a long shadow and
## the orange of the hero reads against a cool ambient.

signal time_of_day_changed(hours: float)

const HDRI_MOODS := ["golden_hour", "overcast", "night"]

var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var environment: Environment
var _sky_material: ShaderMaterial = null

## Hours, 0-24. 17.0 puts the sun about 14 degrees up: still a raking, warm key
## with long shadows, but high enough that a street between 20-storey towers is
## readable. Below roughly 16.5 the district goes to silhouette.
var time_of_day: float = 17.0
var day_length_seconds: float = 0.0    # 0 = frozen

func _init(mood: String = "golden_hour") -> void:
	name = "SkyEnv"
	environment = _build_environment(mood)
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.light_color = Color(1.0, 0.79, 0.55)
	sun.light_energy = 3.4
	sun.light_indirect_energy = 1.35
	sun.light_volumetric_fog_energy = 1.5
	sun.light_angular_distance = 0.62      # real sun ≈ 0.53°; a touch more softens contact shadows
	sun.shadow_enabled = true
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.14
	sun.directional_shadow_split_3 = 0.38
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.92
	sun.directional_shadow_max_distance = 320.0
	sun.directional_shadow_pancake_size = 24.0
	add_child(sun)

	# Sky-coloured bounce from the opposite side. Real interiors and exteriors
	# both die without one; it is what keeps shadow sides readable.
	fill = DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color(0.55, 0.68, 0.92)
	fill.light_energy = 0.85
	fill.light_indirect_energy = 0.6
	fill.shadow_enabled = false
	fill.light_specular = 0.15
	add_child(fill)

	apply_time_of_day(time_of_day)

func _ready() -> void:
	Quality.register_environment(environment, sun)

func _process(delta: float) -> void:
	if day_length_seconds > 0.001:
		apply_time_of_day(fposmod(time_of_day + 24.0 * delta / day_length_seconds, 24.0))

# ---------------------------------------------------------------------------

func _build_environment(mood: String) -> Environment:
	var env := Environment.new()

	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var hdri := AssetLibrary.hdri_texture(mood)
	if hdri != null:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdri
		pano.energy_multiplier = 1.0
		sky.sky_material = pano
	else:
		# The layered custom sky: gradient + sun + two FBM cloud decks + stars
		# + horizon city glow. Drives GI/reflections through the radiance map.
		_sky_material = ShaderMaterial.new()
		_sky_material.shader = load("res://shaders/sky.gdshader")
		sky.sky_material = _sky_material

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.15
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# --- tonemapping -------------------------------------------------------
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0

	# --- global illumination ----------------------------------------------
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.15
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_energy = 1.1
	env.sdfgi_probe_bias = 1.1
	env.sdfgi_normal_bias = 1.1

	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.12
	env.ssao_ao_channel_affect = 0.35

	env.ssil_enabled = true
	env.ssil_radius = 4.5
	env.ssil_intensity = 1.15
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0

	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.4
	env.ssr_depth_tolerance = 0.24

	# --- atmosphere --------------------------------------------------------
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.028
	env.volumetric_fog_albedo = Color(0.86, 0.78, 0.72)
	env.volumetric_fog_emission = Color(0.10, 0.055, 0.03)
	env.volumetric_fog_emission_energy = 0.35
	env.volumetric_fog_gi_inject = 1.2
	env.volumetric_fog_anisotropy = 0.32       # forward scattering = visible god rays
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_detail_spread = 2.4
	env.volumetric_fog_ambient_inject = 0.6
	env.volumetric_fog_sky_affect = 0.55
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.92

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.62, 0.56, 0.52)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.4
	env.fog_height = -6.0
	env.fog_height_density = 0.06
	env.fog_aerial_perspective = 0.55

	# --- glow --------------------------------------------------------------
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	env.glow_map_strength = 0.0
	# Level index 0..6 maps to glow levels 1..7; a wide, low tail gives the
	# soft halo bloom without smearing the whole frame.
	for i in 7:
		env.set_glow_level(i, [0.9, 1.0, 0.75, 0.5, 0.35, 0.2, 0.1][i])

	# --- adjustments -------------------------------------------------------
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.03
	env.adjustment_saturation = 1.05

	return env

## Sets sun angle, light colour and sky mood from a 24-hour clock.
func apply_time_of_day(hours: float) -> void:
	time_of_day = hours
	# Elevation peaks at noon; the district sits at a mid latitude.
	var day_t := clampf((hours - 6.0) / 12.0, -0.5, 1.5)
	var elevation := sin(PI * clampf(day_t, 0.0, 1.0)) * 68.0 - 4.0
	var azimuth := lerpf(95.0, 265.0, clampf(day_t, 0.0, 1.0))
	sun.rotation_degrees = Vector3(-elevation, azimuth, 0.0)
	fill.rotation_degrees = Vector3(-32.0, azimuth + 165.0, 0.0)

	# Colour temperature drops hard as the sun approaches the horizon.
	var horizon := clampf(1.0 - maxf(elevation, 0.0) / 22.0, 0.0, 1.0)
	sun.light_color = Color(1.0, 0.92, 0.82).lerp(Color(1.0, 0.55, 0.24), horizon)
	sun.light_energy = lerpf(4.4, 1.6, horizon)
	var night := clampf((-elevation) / 8.0, 0.0, 1.0)
	sun.light_energy = lerpf(sun.light_energy, 0.05, night)
	fill.light_energy = lerpf(0.85, 0.28, night)
	environment.ambient_light_energy = lerpf(1.15, 0.40, night)
	environment.volumetric_fog_density = lerpf(0.028, 0.045, horizon)
	environment.tonemap_exposure = lerpf(0.92, 1.25, night)
	if _sky_material != null:
		# The sun node is a direct child, so its local basis is world-space.
		_sky_material.set_shader_parameter("sun_direction", -sun.transform.basis.z)
		_sky_material.set_shader_parameter("day_night", night)
		_sky_material.set_shader_parameter("horizon_warmth", horizon)
	time_of_day_changed.emit(hours)
