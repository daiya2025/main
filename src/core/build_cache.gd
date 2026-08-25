class_name BuildCache
extends RefCounted
## Disk cache for procedurally generated meshes.
##
## Building the hero costs ~3 s of sculpting and the city a good deal more.
## That is fine once, but not on every launch, so finished ArrayMeshes are
## written to user://cache and reloaded on subsequent runs. Bumping VERSION
## (or changing the key) invalidates everything derived from it.

const VERSION := 7
const DIR := "user://cache"

static var enabled: bool = true

static func _path(key: String) -> String:
	return "%s/%s_v%d.res" % [DIR, key, VERSION]

static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

## Returns the cached mesh for `key`, or builds it with `builder` (a Callable
## returning a Mesh), stores it and returns that.
static func mesh(key: String, builder: Callable) -> Mesh:
	if enabled:
		var path := _path(key)
		if ResourceLoader.exists(path):
			var cached := ResourceLoader.load(path, "Mesh", ResourceLoader.CACHE_MODE_IGNORE) as Mesh
			if cached != null:
				return cached
	var built: Mesh = builder.call()
	if built != null and enabled:
		ensure_dir()
		# Materials are re-bound at runtime, so they are not part of the cache.
		var stripped := built
		if stripped is ArrayMesh:
			for s in (stripped as ArrayMesh).get_surface_count():
				(stripped as ArrayMesh).surface_set_material(s, null)
		ResourceSaver.save(stripped, _path(key))
	return built

static func clear() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
