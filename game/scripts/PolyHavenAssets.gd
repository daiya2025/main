class_name PolyHavenAssets
extends Object
## tools/fetch_polyhaven.py が生成した manifest.json を読み、
## HDRI / PBR マテリアル / フォトグラメトリモデル (glTF) を提供する。
## アセットが無い場合は null / フォールバックを返し、ゲームは常に起動できる。

const MANIFEST_PATH := "res://assets/polyhaven/manifest.json"

static var _manifest: Dictionary = {}
static var _loaded := false


static func manifest() -> Dictionary:
	if _loaded:
		return _manifest
	_loaded = true
	if FileAccess.file_exists(MANIFEST_PATH):
		var text := FileAccess.get_file_as_string(MANIFEST_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest


static func available() -> bool:
	return not manifest().is_empty()


static func _load_res(path: String) -> Resource:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## HDRI パノラマテクスチャ (night / dusk / day)。無ければ null。
static func hdri_texture(slot: String) -> Texture2D:
	var hdris: Dictionary = manifest().get("hdris", {})
	var path: String = hdris.get(slot, "")
	if path.is_empty() and not hdris.is_empty():
		path = hdris.values()[0]
	return _load_res(path) as Texture2D


## PBR テクスチャセットから StandardMaterial3D を構築する。
## role: asphalt / sidewalk / concrete / plaza / soil
static func pbr_material(role: String, uv_scale: float = 0.08) -> StandardMaterial3D:
	var sets: Dictionary = manifest().get("textures", {})
	var maps: Dictionary = sets.get(role, {})
	if maps.is_empty():
		return null
	var mat := StandardMaterial3D.new()
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var albedo := _load_res(maps.get("albedo", "")) as Texture2D
	if albedo:
		mat.albedo_texture = albedo
	var normal := _load_res(maps.get("normal", "")) as Texture2D
	if normal:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = 1.0
	var rough := _load_res(maps.get("rough", "")) as Texture2D
	if rough:
		mat.roughness_texture = rough
	else:
		mat.roughness = 0.9
	var ao := _load_res(maps.get("ao", "")) as Texture2D
	if ao:
		mat.ao_enabled = true
		mat.ao_texture = ao
	var disp := _load_res(maps.get("disp", "")) as Texture2D
	if disp:
		mat.heightmap_enabled = true
		mat.heightmap_texture = disp
		mat.heightmap_scale = 3.0
	return mat


## PBR テクスチャの生パス辞書 (シェーダー用)。
static func pbr_maps(role: String) -> Dictionary:
	var sets: Dictionary = manifest().get("textures", {})
	var maps: Dictionary = sets.get(role, {})
	var out := {}
	for key in maps:
		if key == "asset":
			continue
		var tex := _load_res(maps[key]) as Texture2D
		if tex:
			out[key] = tex
	return out


## フォトグラメトリモデル (trees / rocks) の PackedScene 配列。
static func model_scenes(kind: String) -> Array:
	var models: Dictionary = manifest().get("models", {})
	var paths: Array = models.get(kind, [])
	var out: Array = []
	for p in paths:
		var scene := _load_res(p) as PackedScene
		if scene:
			out.append(scene)
	return out


## 取得状況サマリ (QualityAudit 用)
static func summary() -> Dictionary:
	var m := manifest()
	var n_models := 0
	for kind in m.get("models", {}):
		n_models += (m["models"][kind] as Array).size()
	return {
		"manifest": available(),
		"hdris": (m.get("hdris", {}) as Dictionary).size(),
		"texture_sets": (m.get("textures", {}) as Dictionary).size(),
		"models": n_models,
	}
