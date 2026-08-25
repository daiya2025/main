@tool
class_name PolyHavenAPI
extends Node
## Thin async client for https://api.polyhaven.com.
##
## Poly Haven exposes three JSON endpoints we care about:
##   /assets?t=<type>   index of every asset of a type
##   /info/<slug>       metadata (name, authors, categories)
##   /files/<slug>      the download tree: map -> resolution -> format -> url
## Everything there is CC0, so downloaded files can ship with the game.

signal log_line(text: String)
signal progress(done: int, total: int, label: String)
signal finished(summary: Dictionary)

const API := "https://api.polyhaven.com"
const OUT_ROOT := "res://assets/polyhaven"
const MANIFEST := OUT_ROOT + "/manifest.json"
const USER_AGENT := "DIGIHARIMAN-OrangeProtocol/1.0 (Godot asset fetcher)"

const MAP_ALIASES := {
	"diffuse": "diffuse", "diff": "diffuse", "albedo": "diffuse", "col": "diffuse",
	"nor_gl": "normal", "normal": "normal", "nor_dx": "normal_dx",
	"rough": "rough", "roughness": "rough",
	"ao": "ao",
	"displacement": "disp", "disp": "disp", "height": "disp",
	"arm": "arm", "metal": "metal", "metallic": "metal",
	"spec": "spec", "bump": "bump", "emission": "emission",
}
const TEXTURE_FORMATS := ["jpg", "png", "exr"]
const HDRI_FORMATS := ["hdr", "exr"]
const RES_FALLBACK := ["8k", "4k", "2k", "1k"]

var cancelled := false

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 120.0
	add_child(_http)

func _headers() -> PackedStringArray:
	return PackedStringArray(["User-Agent: " + USER_AGENT])

func _get_bytes(url: String, to_file: String = "") -> PackedByteArray:
	for attempt in 4:
		if cancelled:
			return PackedByteArray()
		_http.download_file = to_file
		var err := _http.request(url, _headers())
		if err != OK:
			await get_tree().create_timer(pow(2.0, attempt)).timeout
			continue
		var result: Array = await _http.request_completed
		var code: int = result[1]
		if result[0] == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
			return result[3]
		log_line.emit("  ! HTTP %d on %s (attempt %d)" % [code, url.get_file(), attempt + 1])
		await get_tree().create_timer(pow(2.0, attempt)).timeout
	log_line.emit("  ! giving up on %s" % url)
	return PackedByteArray()

func api_json(path: String) -> Variant:
	var bytes := await _get_bytes("%s/%s" % [API, path])
	if bytes.is_empty():
		return null
	return JSON.parse_string(bytes.get_string_from_utf8())

# ------------------------------------------------------------------ helpers --

static func pick_resolution(node: Dictionary, wanted: String) -> Array:
	if node.has(wanted):
		return [wanted, node[wanted]]
	for res in RES_FALLBACK:
		if node.has(res):
			return [res, node[res]]
	for key in node.keys():
		if typeof(node[key]) == TYPE_DICTIONARY:
			return [String(key), node[key]]
	return []

static func pick_format(node: Dictionary, preferred: Array) -> Dictionary:
	for fmt in preferred:
		if node.has(fmt) and typeof(node[fmt]) == TYPE_DICTIONARY and (node[fmt] as Dictionary).has("url"):
			return node[fmt]
	for key in node.keys():
		if typeof(node[key]) == TYPE_DICTIONARY and (node[key] as Dictionary).has("url"):
			return node[key]
	return {}

static func _ext_of(url: String, fallback: String) -> String:
	var clean := url.get_file()
	var dot := clean.rfind(".")
	return clean.substr(dot) if dot > 0 else fallback

# -------------------------------------------------------------------- fetch --

## `sets` is a Dictionary of {"textures": PackedStringArray, "hdris": ..., "models": ...}
func fetch(sets: Dictionary, resolution: String) -> void:
	cancelled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_ROOT))
	var manifest := _load_manifest()
	manifest["resolution"] = resolution

	var jobs: Array = []          # [url, res_path, label]
	var credits: Array = []

	for kind in ["textures", "hdris", "models"]:
		for slug in sets.get(kind, PackedStringArray()):
			if cancelled:
				break
			log_line.emit("[%s] %s" % [kind, slug])
			var files: Variant = await api_json("files/%s" % slug)
			if typeof(files) != TYPE_DICTIONARY:
				log_line.emit("  ! no file list for %s" % slug)
				continue
			match kind:
				"textures":
					var entry := _plan_texture(slug, files, resolution, jobs)
					if entry.size() > 2:
						(manifest["textures"] as Dictionary)[slug] = entry
				"hdris":
					var path := _plan_hdri(slug, files, resolution, jobs)
					if not path.is_empty():
						(manifest["hdris"] as Dictionary)[slug] = path
				"models":
					var m := _plan_model(slug, files, resolution, jobs)
					if not m.is_empty():
						(manifest["models"] as Dictionary)[slug] = m
			var info: Variant = await api_json("info/%s" % slug)
			var authors := "Poly Haven"
			var nice: String = slug
			if typeof(info) == TYPE_DICTIONARY:
				nice = String((info as Dictionary).get("name", slug))
				var auth_dict: Dictionary = (info as Dictionary).get("authors", {})
				if not auth_dict.is_empty():
					authors = ", ".join(PackedStringArray(auth_dict.keys()))
			credits.append([slug, nice, authors])

	var total := jobs.size()
	log_line.emit("Downloading %d file(s) at %s ..." % [total, resolution])
	var done := 0
	var written := 0
	for job in jobs:
		if cancelled:
			break
		var url: String = job[0]
		var res_path: String = job[1]
		var abs_path := ProjectSettings.globalize_path(res_path)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		if FileAccess.file_exists(res_path):
			done += 1
			progress.emit(done, total, res_path.get_file())
			continue
		await _get_bytes(url, abs_path)
		if FileAccess.file_exists(res_path):
			written += 1
		done += 1
		progress.emit(done, total, res_path.get_file())

	_save_manifest(manifest)
	_write_credits(credits)
	log_line.emit("Manifest written: %s (%d new file(s))" % [MANIFEST, written])
	finished.emit({"downloaded": written, "total": total, "manifest": manifest})

func _plan_texture(slug: String, files: Dictionary, resolution: String, jobs: Array) -> Dictionary:
	var entry := {"slug": slug, "kind": "texture"}
	var folder := "%s/textures/%s" % [OUT_ROOT, slug]
	for raw_key in files.keys():
		var key: String = MAP_ALIASES.get(String(raw_key).to_lower(), "")
		if key.is_empty() or typeof(files[raw_key]) != TYPE_DICTIONARY:
			continue
		var picked := pick_resolution(files[raw_key], resolution)
		if picked.is_empty():
			continue
		var file_entry := pick_format(picked[1], TEXTURE_FORMATS)
		if file_entry.is_empty():
			continue
		var url := String(file_entry["url"])
		var dest := "%s/%s_%s_%s%s" % [folder, slug, key, picked[0], _ext_of(url, ".jpg")]
		jobs.append([url, dest])
		entry[key] = dest
	if not entry.has("normal") and entry.has("normal_dx"):
		entry["normal"] = entry["normal_dx"]
	return entry

func _plan_hdri(slug: String, files: Dictionary, resolution: String, jobs: Array) -> String:
	if typeof(files.get("hdri")) != TYPE_DICTIONARY:
		return ""
	var picked := pick_resolution(files["hdri"], resolution)
	if picked.is_empty():
		return ""
	var file_entry := pick_format(picked[1], HDRI_FORMATS)
	if file_entry.is_empty():
		return ""
	var url := String(file_entry["url"])
	var dest := "%s/hdris/%s_%s%s" % [OUT_ROOT, slug, picked[0], _ext_of(url, ".hdr")]
	jobs.append([url, dest])
	return dest

func _plan_model(slug: String, files: Dictionary, resolution: String, jobs: Array) -> Dictionary:
	if typeof(files.get("gltf")) != TYPE_DICTIONARY:
		return {}
	var picked := pick_resolution(files["gltf"], resolution)
	if picked.is_empty():
		return {}
	var branch: Dictionary = picked[1]
	if typeof(branch.get("gltf")) != TYPE_DICTIONARY:
		return {}
	var gltf: Dictionary = branch["gltf"]
	if not gltf.has("url"):
		return {}
	var folder := "%s/models/%s" % [OUT_ROOT, slug]
	var main := "%s/%s" % [folder, String(gltf["url"]).get_file()]
	jobs.append([String(gltf["url"]), main])
	var include: Dictionary = gltf.get("include", {})
	for rel in include.keys():
		var sub: Dictionary = include[rel]
		if not sub.has("url"):
			continue
		var safe_rel := String(rel).replace("\\", "/").lstrip("/")
		jobs.append([String(sub["url"]), "%s/%s" % [folder, safe_rel]])
	return {"slug": slug, "kind": "model", "scene": main}

# ----------------------------------------------------------------- manifest --

func _load_manifest() -> Dictionary:
	var base := {"version": 1, "resolution": "2k", "textures": {}, "hdris": {}, "models": {}}
	if not FileAccess.file_exists(MANIFEST):
		return base
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(parsed) == TYPE_DICTIONARY:
		base.merge(parsed, true)
	return base

func _save_manifest(manifest: Dictionary) -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
	if file == null:
		log_line.emit("  ! cannot write %s" % MANIFEST)
		return
	file.store_string(JSON.stringify(manifest, "\t", true))
	file.close()

func _write_credits(credits: Array) -> void:
	if credits.is_empty():
		return
	var file := FileAccess.open(OUT_ROOT + "/CREDITS.md", FileAccess.WRITE)
	if file == null:
		return
	file.store_line("# Poly Haven assets\n")
	file.store_line("CC0 assets from https://polyhaven.com, fetched by the Poly Haven Bridge plugin.\n")
	file.store_line("| Slug | Name | Author(s) |")
	file.store_line("|---|---|---|")
	credits.sort()
	for row in credits:
		file.store_line("| `%s` | %s | %s |" % [row[0], row[1], row[2]])
	file.close()
