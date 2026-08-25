extends Node
## Persisted user settings. Autoloaded as `Settings`.

const PATH := "user://digihariman.cfg"

var data := {
	"quality_preset": "ULTRA",
	"mouse_sensitivity": 0.0022,
	"invert_y": false,
	"fov": 68.0,
	"master_volume_db": -4.0,
	"motion_blur": true,
	"film_grain": 0.35,
	"chromatic_aberration": 0.45,
	"lens_dirt": 0.5,
	"vignette": 0.42,
	"auto_exposure": true,
	"polyhaven_resolution": "2k",
	"world_seed": 20250825,
}

func _ready() -> void:
	load_settings()

func get_value(key: String, fallback: Variant = null) -> Variant:
	return data.get(key, fallback)

func set_value(key: String, value: Variant) -> void:
	data[key] = value
	save_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in data.keys():
		if cfg.has_section_key("game", key):
			data[key] = cfg.get_value("game", key)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value("game", key, data[key])
	cfg.save(PATH)
