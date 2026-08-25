@tool
class_name PolyHavenImportTuner
extends RefCounted
## Rewrites the .import settings of downloaded Poly Haven maps.
##
## Godot's defaults treat every image as an sRGB colour texture. Feeding a
## normal / roughness / AO map through that path costs both accuracy and
## specular stability, so after a fetch we set:
##   * normal maps  -> normal-map compression (better tangent-space precision)
##   * data maps    -> no 3D-detect recompression
##   * roughness    -> mip-level roughness limiting driven by the normal map,
##                     which is what kills shimmer on distant detailed surfaces
##   * HDRIs        -> lossless, mipmapped, ready for a panorama sky

# ResourceImporterTexture enum orders, from the engine's option hints.
const NORMAL_MAP_DETECT := 0
const NORMAL_MAP_ENABLE := 1
const NORMAL_MAP_DISABLE := 2
const ROUGHNESS_DETECT := 0
const ROUGHNESS_DISABLED := 1
const ROUGHNESS_RED := 2
const ROUGHNESS_GREEN := 3
const ROUGHNESS_BLUE := 4
const ROUGHNESS_GRAY := 5
const DETECT_3D_DISABLED := 0

const DATA_SUFFIXES := ["_normal_", "_normal_dx_", "_rough_", "_ao_", "_disp_", "_arm_", "_metal_", "_bump_", "_spec_"]

static func tune_all(root: String = "res://assets/polyhaven", log_sink: Callable = Callable()) -> PackedStringArray:
	var touched := PackedStringArray()
	var files := PackedStringArray()
	_walk(root, files)
	# index normal maps per asset folder so roughness limiting can reference them
	var normals := {}
	for path in files:
		if path.get_file().contains("_normal_"):
			normals[path.get_base_dir()] = path
	for path in files:
		var import_path := path + ".import"
		if not FileAccess.file_exists(import_path):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(import_path) != OK:
			continue
		var name := path.get_file()
		var changed := false
		var ext := path.get_extension().to_lower()

		if ext == "hdr" or ext == "exr":
			changed = _put(cfg, "compress/mode", 0) or changed          # lossless
			changed = _put(cfg, "mipmaps/generate", true) or changed
			changed = _put(cfg, "compress/hdr_compression", 0) or changed
			changed = _put(cfg, "detect_3d/compress_to", DETECT_3D_DISABLED) or changed
		elif name.contains("_normal_"):
			changed = _put(cfg, "compress/normal_map", NORMAL_MAP_ENABLE) or changed
			changed = _put(cfg, "mipmaps/generate", true) or changed
			changed = _put(cfg, "detect_3d/compress_to", DETECT_3D_DISABLED) or changed
			changed = _put(cfg, "process/normal_map_invert_y", name.contains("_normal_dx_")) or changed
		elif _is_data_map(name):
			changed = _put(cfg, "compress/normal_map", NORMAL_MAP_DISABLE) or changed
			changed = _put(cfg, "mipmaps/generate", true) or changed
			changed = _put(cfg, "detect_3d/compress_to", DETECT_3D_DISABLED) or changed
			var src_normal: String = normals.get(path.get_base_dir(), "")
			if not src_normal.is_empty():
				if name.contains("_arm_"):
					changed = _put(cfg, "roughness/mode", ROUGHNESS_GREEN) or changed
					changed = _put(cfg, "roughness/src_normal", src_normal) or changed
				elif name.contains("_rough_"):
					changed = _put(cfg, "roughness/mode", ROUGHNESS_GRAY) or changed
					changed = _put(cfg, "roughness/src_normal", src_normal) or changed
		else:
			changed = _put(cfg, "mipmaps/generate", true) or changed

		if changed:
			cfg.save(import_path)
			touched.append(path)
			if log_sink.is_valid():
				log_sink.call("  tuned %s" % name)
	return touched

static func _is_data_map(name: String) -> bool:
	for suffix in DATA_SUFFIXES:
		if name.contains(suffix):
			return true
	return false

static func _put(cfg: ConfigFile, key: String, value: Variant) -> bool:
	if cfg.has_section_key("params", key) and cfg.get_value("params", key) == value:
		return false
	cfg.set_value("params", key, value)
	return true

static func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full, out)
		elif not entry.ends_with(".import"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
