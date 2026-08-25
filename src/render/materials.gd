class_name Materials
extends RefCounted
## Material factory.
##
## Shaders live in res://shaders and are wired up here with the right textures
## and defaults, so the rest of the code never touches uniform names. Materials
## are cached per configuration — a city of 300 buildings must not compile 300
## copies of the facade shader.

const SKIN := "res://shaders/skin.gdshader"
const EYE := "res://shaders/eye.gdshader"
const SUIT := "res://shaders/suit.gdshader"
const ARMOR := "res://shaders/armor.gdshader"
const ENERGY := "res://shaders/energy.gdshader"
const CARAPACE := "res://shaders/carapace.gdshader"
const TERRAIN := "res://shaders/terrain.gdshader"
const FACADE := "res://shaders/facade.gdshader"
const ROAD := "res://shaders/road.gdshader"
const HAIR := "res://shaders/hair.gdshader"
const FOLIAGE := "res://shaders/foliage.gdshader"

## The hero palette. Everything orange in the game comes from here so a single
## edit re-grades the whole character.
const ORANGE_PRIMARY := Color(0.905, 0.318, 0.031)
const ORANGE_HOT := Color(1.0, 0.52, 0.12)
const ORANGE_EMISSIVE := Color(1.0, 0.45, 0.08)
const ORANGE_DEEP := Color(0.312, 0.086, 0.020)
const CHARCOAL := Color(0.045, 0.047, 0.055)

static var _cache: Dictionary = {}

static func _shader(path: String) -> Shader:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

static func _make(path: String, key: String) -> ShaderMaterial:
	var cache_key := "%s#%s" % [path, key]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var mat := ShaderMaterial.new()
	mat.shader = _shader(path)
	mat.resource_name = key
	_cache[cache_key] = mat
	return mat

static func clear_cache() -> void:
	_cache.clear()

# ---------------------------------------------------------------- character --

static func skin(tone: Color = Color(0.803, 0.607, 0.503)) -> ShaderMaterial:
	var mat := _make(SKIN, "skin_%s" % tone.to_html(false))
	mat.set_shader_parameter("skin_tone", tone)
	mat.set_shader_parameter("shadow_tone", tone.darkened(0.42).lerp(Color(0.42, 0.20, 0.16), 0.5))
	mat.set_shader_parameter("albedo_detail", AssetLibrary.procedural_albedo("concrete_wall", 512))
	mat.set_shader_parameter("pore_normal", AssetLibrary.procedural_normal("gravel", 512))
	mat.set_shader_parameter("pore_scale", 34.0)
	mat.set_shader_parameter("pore_strength", 0.65)
	mat.set_shader_parameter("sss_strength", 0.62)
	return mat

static func eye() -> ShaderMaterial:
	return _make(EYE, "eye")

static func hair(color: Color = Color(0.055, 0.040, 0.032)) -> ShaderMaterial:
	var mat := _make(HAIR, "hair_%s" % color.to_html(false))
	mat.set_shader_parameter("hair_color", color)
	mat.set_shader_parameter("hair_tip", color.lightened(0.22))
	return mat

static func suit(charge: float = 0.55) -> ShaderMaterial:
	var mat := _make(SUIT, "suit")
	mat.set_shader_parameter("weave_normal", AssetLibrary.procedural_normal("metal_scifi", 512))
	mat.set_shader_parameter("accent_color", ORANGE_EMISSIVE)
	mat.set_shader_parameter("fabric_color", CHARCOAL)
	mat.set_shader_parameter("charge", charge)
	return mat

## `variant`: "primary" (orange plates), "dark" (gunmetal), "trim" (bright).
static func armor(variant: String = "primary") -> ShaderMaterial:
	var mat := _make(ARMOR, "armor_%s" % variant)
	match variant:
		"dark":
			mat.set_shader_parameter("paint_color", Color(0.085, 0.088, 0.098))
			mat.set_shader_parameter("paint_shadow", Color(0.028, 0.030, 0.036))
			mat.set_shader_parameter("flake_amount", 0.18)
			mat.set_shader_parameter("paint_roughness", 0.35)
			mat.set_shader_parameter("energy_emission", 2.5)
		"trim":
			mat.set_shader_parameter("paint_color", ORANGE_HOT)
			mat.set_shader_parameter("paint_shadow", ORANGE_DEEP)
			mat.set_shader_parameter("flake_amount", 0.5)
			mat.set_shader_parameter("paint_roughness", 0.18)
			mat.set_shader_parameter("energy_emission", 9.0)
		_:
			mat.set_shader_parameter("paint_color", ORANGE_PRIMARY)
			mat.set_shader_parameter("paint_shadow", ORANGE_DEEP)
	mat.set_shader_parameter("energy_color", ORANGE_EMISSIVE)
	mat.set_shader_parameter("micro_normal", AssetLibrary.procedural_normal("metal_scifi", 512))
	# Set explicitly so the hero's energy meter can drive it at runtime; an
	# unset uniform reads back as null and would be skipped.
	mat.set_shader_parameter("charge", 0.7)
	return mat

static func energy(color: Color = ORANGE_EMISSIVE, intensity: float = 8.0) -> ShaderMaterial:
	var mat := _make(ENERGY, "energy_%s_%0.1f" % [color.to_html(false), intensity])
	mat.set_shader_parameter("core_color", color.lightened(0.45))
	mat.set_shader_parameter("edge_color", color)
	mat.set_shader_parameter("intensity", intensity)
	return mat

static func carapace(rage: float = 0.0) -> ShaderMaterial:
	var mat := _make(CARAPACE, "carapace")
	mat.set_shader_parameter("vein_color", ORANGE_EMISSIVE)
	mat.set_shader_parameter("rage", rage)
	return mat

# -------------------------------------------------------------- environment --

static func terrain(role_ground: String = "ground_primary", role_rock: String = "cliff", role_path: String = "gravel") -> ShaderMaterial:
	var mat := _make(TERRAIN, "terrain_%s_%s_%s" % [role_ground, role_rock, role_path])
	_bind_layer(mat, "l0", role_ground, 0.35)
	_bind_layer(mat, "l1", role_rock, 0.18)
	_bind_layer(mat, "l2", role_path, 0.5)
	return mat

static func _bind_layer(mat: ShaderMaterial, prefix: String, role: String, scale: float) -> void:
	var set_data := AssetLibrary.texture_set_for_role(role)
	var albedo: Texture2D = null
	var normal: Texture2D = null
	var rough: Texture2D = null
	if not set_data.is_empty():
		albedo = AssetLibrary.load_texture(String(set_data.get("diffuse", "")))
		normal = AssetLibrary.load_texture(String(set_data.get("normal", "")))
		rough = AssetLibrary.load_texture(String(set_data.get("rough", "")))
		if rough == null:
			rough = AssetLibrary.load_texture(String(set_data.get("arm", "")))
	if albedo == null:
		albedo = AssetLibrary.procedural_albedo(role, 1024)
	if normal == null:
		normal = AssetLibrary.procedural_normal(role, 1024)
	if rough == null:
		rough = AssetLibrary.procedural_roughness(role, 512)
	mat.set_shader_parameter(prefix + "_albedo", albedo)
	mat.set_shader_parameter(prefix + "_normal", normal)
	mat.set_shader_parameter(prefix + "_rough", rough)
	mat.set_shader_parameter(prefix + "_scale", scale)

static func facade(role: String, seed_value: int, floor_height: float, bay_width: float, lit_ratio: float) -> ShaderMaterial:
	var mat := _make(FACADE, "facade_%s_%d" % [role, seed_value])
	_bind_facade_maps(mat, role)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	mat.set_shader_parameter("floor_height", floor_height)
	mat.set_shader_parameter("bay_width", bay_width)
	mat.set_shader_parameter("lit_ratio", lit_ratio)
	mat.set_shader_parameter("wall_tint", Color(
		rng.randf_range(0.42, 0.70),
		rng.randf_range(0.41, 0.68),
		rng.randf_range(0.40, 0.66)))
	mat.set_shader_parameter("room_light", Color(1.0, rng.randf_range(0.56, 0.74), rng.randf_range(0.24, 0.42)))
	mat.set_shader_parameter("room_depth", rng.randf_range(1.8, 3.4))
	mat.set_shader_parameter("streak_amount", rng.randf_range(0.25, 0.6))
	mat.set_shader_parameter("grime_amount", rng.randf_range(0.2, 0.55))
	return mat

static func _bind_facade_maps(mat: ShaderMaterial, role: String) -> void:
	var set_data := AssetLibrary.texture_set_for_role(role)
	var albedo: Texture2D = null
	var normal: Texture2D = null
	var rough: Texture2D = null
	if not set_data.is_empty():
		albedo = AssetLibrary.load_texture(String(set_data.get("diffuse", "")))
		normal = AssetLibrary.load_texture(String(set_data.get("normal", "")))
		rough = AssetLibrary.load_texture(String(set_data.get("rough", "")))
	if albedo == null:
		albedo = AssetLibrary.procedural_albedo(role, 1024)
	if normal == null:
		normal = AssetLibrary.procedural_normal(role, 1024)
	if rough == null:
		rough = AssetLibrary.procedural_roughness(role, 512)
	mat.set_shader_parameter("wall_albedo", albedo)
	mat.set_shader_parameter("wall_normal", normal)
	mat.set_shader_parameter("wall_rough", rough)

static func road(wetness: float = 0.55) -> ShaderMaterial:
	var mat := _make(ROAD, "road")
	var set_data := AssetLibrary.texture_set_for_role("asphalt")
	var albedo: Texture2D = null
	var normal: Texture2D = null
	var rough: Texture2D = null
	if not set_data.is_empty():
		albedo = AssetLibrary.load_texture(String(set_data.get("diffuse", "")))
		normal = AssetLibrary.load_texture(String(set_data.get("normal", "")))
		rough = AssetLibrary.load_texture(String(set_data.get("rough", "")))
	mat.set_shader_parameter("asphalt_albedo", albedo if albedo != null else AssetLibrary.procedural_albedo("asphalt", 1024))
	mat.set_shader_parameter("asphalt_normal", normal if normal != null else AssetLibrary.procedural_normal("asphalt", 1024))
	mat.set_shader_parameter("asphalt_rough", rough if rough != null else AssetLibrary.procedural_roughness("asphalt", 512))
	mat.set_shader_parameter("wetness", wetness)
	return mat

static func foliage(albedo: Texture2D, normal: Texture2D = null, tint: Color = Color.WHITE) -> ShaderMaterial:
	var mat := _make(FOLIAGE, "foliage_%d" % (albedo.get_instance_id() if albedo != null else 0))
	mat.set_shader_parameter("albedo_tex", albedo)
	if normal != null:
		mat.set_shader_parameter("normal_tex", normal)
	mat.set_shader_parameter("tint", tint)
	return mat
