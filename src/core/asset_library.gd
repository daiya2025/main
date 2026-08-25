class_name AssetLibrary
extends RefCounted
## Central art-asset resolver.
##
## A static class rather than an autoload on purpose: the procedural builders
## are plain `RefCounted` utilities that must resolve at script-compile time,
## and an autoload identifier is not available that early.
##
## Every material in the game is requested through here by *role*
## ("asphalt", "concrete_wall", "cliff", ...). If the Poly Haven bridge has
## downloaded a photoscanned set for that role, the real 2K-8K PBR maps are
## used. If not, a procedurally synthesised PBR set stands in, so the project
## always builds, always runs, and degrades in fidelity instead of crashing.

const MANIFEST_PATH := "res://assets/polyhaven/manifest.json"

## Roles the world builders ask for, mapped to the Poly Haven slugs we prefer
## (first available wins). These slugs are all real assets on polyhaven.com.
const ROLE_SLUGS := {
	"ground_primary": ["rocky_terrain_02", "aerial_rocks_02", "coast_sand_rocks_02", "rock_ground"],
	"ground_secondary": ["forest_leaves_02", "brown_mud_leaves_01", "forrest_ground_01", "leafy_grass"],
	"gravel": ["gravel_floor", "gravelly_sand", "gravel_embedded_concrete"],
	"cliff": ["rock_face_03", "rock_wall_10", "cliff_side"],
	"asphalt": ["asphalt_02", "asphalt_04", "asphalt_track"],
	"concrete_wall": ["concrete_wall_008", "concrete_wall_006", "painted_concrete_02"],
	"concrete_floor": ["concrete_floor_worn_001", "concrete_layers_02"],
	"brick": ["red_brick_03", "castle_brick_02_red", "brick_wall_006"],
	"metal_plate": ["metal_plate", "rusty_metal_02", "metal_grill"],
	"metal_scifi": ["metal_plate_02", "sci-fi_metal_panel", "scuffed_metal"],
	"wood": ["wood_planks_dirt", "weathered_planks", "plywood"],
	"bark": ["bark_brown_02", "bark_willow", "bark_brown_01"],
	"roof": ["roof_09", "roof_slates_02", "roof_tiles_14"],
	"tiles": ["floor_tiles_06", "large_floor_tiles_02", "marble_01"],
	"sand": ["sandy_gravel", "aerial_beach_01"],
	"foliage_atlas": ["leaves_forest_ground"],
}

const HDRI_SLUGS := {
	"golden_hour": ["kloppenheim_02_puresky", "syferfontein_18d_clear_puresky", "belfast_sunset_puresky"],
	"overcast": ["kloofendal_48d_partly_cloudy_puresky", "qwantani_puresky", "rogland_clear_night"],
	"night": ["dikhololo_night", "moonless_golf", "satara_night"],
	"studio": ["studio_small_09", "brown_photostudio_02"],
}

const MODEL_SLUGS := {
	"tree": ["tree_small_02", "dead_tree_trunk", "sycamore_tree", "fern_02"],
	"rock": ["rock_boulder_dry", "boulder_01", "rock_02", "rocks_ground_01"],
	"prop": ["concrete_barrier", "wooden_crate_02", "trash_can", "street_light_01"],
}

static var manifest: Dictionary = {}
static var has_photoscans: bool = false
static var _loaded: bool = false

static var _material_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _procedural_cache: Dictionary = {}

## Every public entry point funnels through here, so the manifest is read once
## on first use and never on a hot path.
static func ensure_loaded() -> void:
	if not _loaded:
		reload_manifest()

static func reload_manifest() -> void:
	_loaded = true
	manifest = {}
	_material_cache.clear()
	_texture_cache.clear()
	has_photoscans = false
	if not FileAccess.file_exists(MANIFEST_PATH):
		print_rich("[color=orange]AssetLibrary:[/color] Poly Haven manifest not found — using procedural PBR stand-ins. ",
			"Run the Poly Haven dock (or tools/fetch_polyhaven.py) to pull photoscanned assets.")
		return
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("AssetLibrary: manifest.json is malformed; ignoring it.")
		return
	manifest = parsed
	var tex_count: int = (manifest.get("textures", {}) as Dictionary).size()
	var hdri_count: int = (manifest.get("hdris", {}) as Dictionary).size()
	var model_count: int = (manifest.get("models", {}) as Dictionary).size()
	has_photoscans = tex_count > 0 or hdri_count > 0 or model_count > 0
	print_rich("[color=orange]AssetLibrary:[/color] Poly Haven manifest loaded — %d textures / %d HDRIs / %d models."
		% [tex_count, hdri_count, model_count])

# ---------------------------------------------------------------- textures --

static func _manifest_textures() -> Dictionary:
	ensure_loaded()
	return manifest.get("textures", {}) as Dictionary

static func texture_set_for_role(role: String) -> Dictionary:
	ensure_loaded()
	var slugs: Array = ROLE_SLUGS.get(role, [])
	var table := _manifest_textures()
	for slug in slugs:
		if table.has(slug):
			return table[slug] as Dictionary
	return {}

static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

## Builds (and caches) a PBR material for a role.
## `opts` accepts: uv_scale (float), tint (Color), roughness (float),
## metallic (float), triplanar (bool), parallax (bool), emission (Color).
static func material(role: String, opts: Dictionary = {}) -> StandardMaterial3D:
	# str() rather than JSON.stringify: opts carries Colors, which JSON drops,
	# and two different tints must not collide on one cache entry.
	var key := "%s|%s" % [role, str(opts)]
	if _material_cache.has(key):
		return _material_cache[key]

	var mat := StandardMaterial3D.new()
	mat.resource_name = "mat_%s" % role
	var uv_scale := float(opts.get("uv_scale", 1.0))
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.uv1_triplanar = bool(opts.get("triplanar", false))
	mat.uv1_world_triplanar = mat.uv1_triplanar
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.albedo_color = opts.get("tint", Color.WHITE)
	mat.roughness = float(opts.get("roughness", 0.85))
	mat.metallic = float(opts.get("metallic", 0.0))
	mat.metallic_specular = 0.5
	mat.ao_light_affect = 1.0

	var set_data := texture_set_for_role(role)
	if set_data.is_empty():
		_apply_procedural(mat, role, opts)
	else:
		_apply_photoscan(mat, set_data, opts)

	var emission: Color = opts.get("emission", Color(0, 0, 0, 0))
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = float(opts.get("emission_energy", 1.5))

	_material_cache[key] = mat
	return mat

static func _apply_photoscan(mat: StandardMaterial3D, set_data: Dictionary, opts: Dictionary) -> void:
	mat.albedo_texture = load_texture(String(set_data.get("diffuse", "")))
	var nrm := load_texture(String(set_data.get("normal", "")))
	if nrm != null:
		mat.normal_enabled = true
		mat.normal_texture = nrm
		mat.normal_scale = float(opts.get("normal_scale", 1.0))
	var arm := load_texture(String(set_data.get("arm", "")))
	if arm != null:
		# Poly Haven's packed AO(R) / Rough(G) / Metal(B) map.
		mat.ao_enabled = true
		mat.ao_texture = arm
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = arm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = arm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		mat.metallic = float(opts.get("metallic", 1.0))
		mat.roughness = float(opts.get("roughness", 1.0))
	else:
		var rgh := load_texture(String(set_data.get("rough", "")))
		if rgh != null:
			mat.roughness_texture = rgh
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
			mat.roughness = float(opts.get("roughness", 1.0))
		var ao := load_texture(String(set_data.get("ao", "")))
		if ao != null:
			mat.ao_enabled = true
			mat.ao_texture = ao
			mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		var met := load_texture(String(set_data.get("metal", "")))
		if met != null:
			mat.metallic_texture = met
			mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
			mat.metallic = 1.0
	var disp := load_texture(String(set_data.get("disp", "")))
	if disp != null and bool(opts.get("parallax", true)):
		mat.heightmap_enabled = true
		mat.heightmap_texture = disp
		mat.heightmap_scale = float(opts.get("height_scale", 3.0))
		mat.heightmap_deep_parallax = true
		mat.heightmap_min_layers = 12
		mat.heightmap_max_layers = 42

# ------------------------------------------------ procedural PBR fallback --

const PROC_PROFILES := {
	"ground_primary": {"albedo": Color(0.30, 0.26, 0.22), "alt": Color(0.19, 0.16, 0.14), "freq": 0.02, "rough": 0.94, "bump": 2.4, "octaves": 6},
	"ground_secondary": {"albedo": Color(0.21, 0.24, 0.15), "alt": Color(0.11, 0.13, 0.08), "freq": 0.035, "rough": 0.92, "bump": 2.0, "octaves": 5},
	"gravel": {"albedo": Color(0.33, 0.31, 0.29), "alt": Color(0.17, 0.16, 0.15), "freq": 0.08, "rough": 0.95, "bump": 3.0, "octaves": 5},
	"cliff": {"albedo": Color(0.34, 0.31, 0.28), "alt": Color(0.16, 0.14, 0.13), "freq": 0.012, "rough": 0.88, "bump": 4.0, "octaves": 6},
	"asphalt": {"albedo": Color(0.085, 0.086, 0.092), "alt": Color(0.045, 0.046, 0.05), "freq": 0.09, "rough": 0.72, "bump": 1.2, "octaves": 4},
	"concrete_wall": {"albedo": Color(0.44, 0.43, 0.41), "alt": Color(0.30, 0.29, 0.28), "freq": 0.018, "rough": 0.82, "bump": 1.0, "octaves": 5},
	"concrete_floor": {"albedo": Color(0.38, 0.375, 0.36), "alt": Color(0.24, 0.235, 0.23), "freq": 0.025, "rough": 0.80, "bump": 1.4, "octaves": 5},
	"brick": {"albedo": Color(0.36, 0.17, 0.12), "alt": Color(0.22, 0.11, 0.08), "freq": 0.05, "rough": 0.86, "bump": 2.6, "octaves": 4},
	"metal_plate": {"albedo": Color(0.42, 0.41, 0.40), "alt": Color(0.24, 0.22, 0.20), "freq": 0.04, "rough": 0.42, "bump": 1.0, "octaves": 4},
	"metal_scifi": {"albedo": Color(0.52, 0.53, 0.55), "alt": Color(0.30, 0.31, 0.33), "freq": 0.03, "rough": 0.30, "bump": 0.8, "octaves": 3},
	"wood": {"albedo": Color(0.31, 0.21, 0.13), "alt": Color(0.18, 0.12, 0.07), "freq": 0.02, "rough": 0.78, "bump": 1.6, "octaves": 4},
	"bark": {"albedo": Color(0.20, 0.16, 0.12), "alt": Color(0.10, 0.08, 0.06), "freq": 0.06, "rough": 0.93, "bump": 3.4, "octaves": 5},
	"roof": {"albedo": Color(0.20, 0.19, 0.19), "alt": Color(0.11, 0.10, 0.10), "freq": 0.06, "rough": 0.74, "bump": 2.2, "octaves": 4},
	"tiles": {"albedo": Color(0.52, 0.51, 0.49), "alt": Color(0.37, 0.36, 0.35), "freq": 0.03, "rough": 0.36, "bump": 1.2, "octaves": 4},
	"sand": {"albedo": Color(0.46, 0.40, 0.31), "alt": Color(0.31, 0.27, 0.21), "freq": 0.12, "rough": 0.90, "bump": 1.4, "octaves": 4},
}

static func _profile(role: String) -> Dictionary:
	return PROC_PROFILES.get(role, PROC_PROFILES["concrete_wall"])

static func _noise(seed_value: int, freq: float, octaves: int, noise_type: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = noise_type
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.05
	n.fractal_gain = 0.5
	return n

static func procedural_albedo(role: String, size: int = 1024) -> Texture2D:
	var key := "alb_%s_%d" % [role, size]
	if _procedural_cache.has(key):
		return _procedural_cache[key]
	var p := _profile(role)
	var base: Color = p["albedo"]
	var alt: Color = p["alt"]
	var grad := Gradient.new()
	grad.set_color(0, alt)
	grad.set_color(1, base)
	grad.add_point(0.45, alt.lerp(base, 0.35))
	grad.add_point(0.78, base.lerp(Color.WHITE, 0.08))
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.seamless_blend_skirt = 0.2
	tex.generate_mipmaps = true
	tex.color_ramp = grad
	tex.noise = _noise(hash(role), float(p["freq"]) * float(size) / 12.0, int(p["octaves"]))
	_procedural_cache[key] = tex
	return tex

static func procedural_normal(role: String, size: int = 1024) -> Texture2D:
	var key := "nrm_%s_%d" % [role, size]
	if _procedural_cache.has(key):
		return _procedural_cache[key]
	var p := _profile(role)
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.seamless_blend_skirt = 0.2
	tex.generate_mipmaps = true
	tex.as_normal_map = true
	tex.bump_strength = float(p["bump"])
	tex.noise = _noise(hash(role) + 977, float(p["freq"]) * float(size) / 12.0, int(p["octaves"]))
	_procedural_cache[key] = tex
	return tex

static func procedural_roughness(role: String, size: int = 512) -> Texture2D:
	var key := "rgh_%s_%d" % [role, size]
	if _procedural_cache.has(key):
		return _procedural_cache[key]
	var p := _profile(role)
	var r := float(p["rough"])
	var grad := Gradient.new()
	grad.set_color(0, Color(clampf(r - 0.22, 0.02, 1.0), 0, 0))
	grad.set_color(1, Color(clampf(r + 0.10, 0.02, 1.0), 0, 0))
	var tex := NoiseTexture2D.new()
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.color_ramp = grad
	tex.noise = _noise(hash(role) + 4231, float(p["freq"]) * float(size) / 6.0, 4)
	_procedural_cache[key] = tex
	return tex

static func _apply_procedural(mat: StandardMaterial3D, role: String, opts: Dictionary) -> void:
	var p := _profile(role)
	mat.albedo_texture = procedural_albedo(role)
	mat.normal_enabled = true
	mat.normal_texture = procedural_normal(role)
	mat.normal_scale = float(opts.get("normal_scale", 1.0))
	mat.roughness_texture = procedural_roughness(role)
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.roughness = float(opts.get("roughness", 1.0))
	if not opts.has("tint"):
		mat.albedo_color = Color.WHITE
	if role.begins_with("metal"):
		mat.metallic = float(opts.get("metallic", 0.9))

# -------------------------------------------------------------- HDRI / sky --

static func hdri_texture(mood: String = "golden_hour") -> Texture2D:
	ensure_loaded()
	var table := manifest.get("hdris", {}) as Dictionary
	for slug in HDRI_SLUGS.get(mood, []):
		if table.has(slug):
			var tex := load_texture(String(table[slug]))
			if tex != null:
				return tex
	# any HDRI is better than none
	for slug in table.keys():
		var tex2 := load_texture(String(table[slug]))
		if tex2 != null:
			return tex2
	return null

# ------------------------------------------------------------------ models --

static func model_paths(category: String) -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	var table := manifest.get("models", {}) as Dictionary
	for slug in MODEL_SLUGS.get(category, []):
		if table.has(slug):
			var entry := table[slug] as Dictionary
			var path := String(entry.get("scene", ""))
			if not path.is_empty() and ResourceLoader.exists(path):
				out.append(path)
	# include any other downloaded model whose slug hints at the category
	for slug in table.keys():
		if String(slug).contains(category):
			var entry2 := table[slug] as Dictionary
			var path2 := String(entry2.get("scene", ""))
			if not path2.is_empty() and ResourceLoader.exists(path2) and not out.has(path2):
				out.append(path2)
	return out

## Returns meshes extracted from downloaded photogrammetry scenes, ready to be
## dropped into a MultiMeshInstance3D. Empty when nothing was downloaded — the
## scatter system then falls back to its procedural generators.
static func scanned_meshes(category: String) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	for path in model_paths(category):
		var packed := ResourceLoader.load(path) as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate()
		_collect_meshes(inst, meshes)
		inst.queue_free()
	return meshes

static func _collect_meshes(node: Node, out: Array[Mesh]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node.mesh)
	for child in node.get_children():
		_collect_meshes(child, out)
