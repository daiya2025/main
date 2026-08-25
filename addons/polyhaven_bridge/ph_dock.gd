@tool
extends VBoxContainer
## Editor dock for the Poly Haven bridge. Built in code so the plugin has no
## .tscn to keep in sync.

const CURATED := {
	"textures": [
		"rocky_terrain_02", "aerial_rocks_02", "forest_leaves_02", "brown_mud_leaves_01",
		"gravel_floor", "rock_face_03", "coast_sand_rocks_02", "leafy_grass",
		"asphalt_02", "concrete_wall_008", "concrete_floor_worn_001", "red_brick_03",
		"roof_09", "floor_tiles_06", "metal_plate", "rusty_metal_02",
		"wood_planks_dirt", "bark_brown_02", "scuffed_metal", "painted_concrete_02",
	],
	"hdris": [
		"kloppenheim_02_puresky", "syferfontein_18d_clear_puresky",
		"kloofendal_48d_partly_cloudy_puresky", "dikhololo_night", "studio_small_09",
	],
	"models": [
		"tree_small_02", "dead_tree_trunk", "fern_02",
		"rock_boulder_dry", "boulder_01", "rocks_ground_01",
		"concrete_barrier", "wooden_crate_02",
	],
}

var _api: PolyHavenAPI
var _res_option: OptionButton
var _checks := {}
var _extra: LineEdit
var _fetch_button: Button
var _cancel_button: Button
var _bar: ProgressBar
var _log: RichTextLabel
var _busy := false

func _ready() -> void:
	name = "Poly Haven"
	custom_minimum_size = Vector2(280, 380)
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Poly Haven Bridge"
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.16))
	add_child(title)

	var hint := Label.new()
	hint.text = "CC0 photoscans, HDRIs and PBR sets\nstraight from api.polyhaven.com."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)

	var res_row := HBoxContainer.new()
	var res_label := Label.new()
	res_label.text = "Resolution"
	res_row.add_child(res_label)
	_res_option = OptionButton.new()
	for res in ["1k", "2k", "4k", "8k"]:
		_res_option.add_item(res.to_upper())
	_res_option.selected = 1
	_res_option.tooltip_text = "4K is the sweet spot for an RTX 5080 at 1440p-4K.\n8K is for hero surfaces only."
	res_row.add_child(_res_option)
	add_child(res_row)

	for kind in ["textures", "hdris", "models"]:
		var check := CheckBox.new()
		check.text = "%s (%d)" % [kind, (CURATED[kind] as Array).size()]
		check.button_pressed = true
		_checks[kind] = check
		add_child(check)

	var extra_label := Label.new()
	extra_label.text = "Extra slugs (comma separated)"
	extra_label.add_theme_font_size_override("font_size", 11)
	add_child(extra_label)
	_extra = LineEdit.new()
	_extra.placeholder_text = "mossy_forest, tree_oak, ..."
	add_child(_extra)

	_fetch_button = Button.new()
	_fetch_button.text = "Fetch from Poly Haven"
	_fetch_button.pressed.connect(_on_fetch)
	add_child(_fetch_button)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.disabled = true
	_cancel_button.pressed.connect(_on_cancel)
	add_child(_cancel_button)

	var tune := Button.new()
	tune.text = "Tune imports (normal / roughness)"
	tune.pressed.connect(_on_tune)
	add_child(tune)

	var reload := Button.new()
	reload.text = "Reload manifest in game"
	reload.pressed.connect(_on_reload)
	add_child(reload)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = true
	add_child(_bar)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 140)
	add_child(_log)

	_api = PolyHavenAPI.new()
	add_child(_api)
	_api.log_line.connect(_append)
	_api.progress.connect(_on_progress)
	_api.finished.connect(_on_finished)
	_append("Ready. Assets land in res://assets/polyhaven/.")

func _append(text: String) -> void:
	if is_instance_valid(_log):
		_log.append_text(text + "\n")

func _on_progress(done: int, total: int, label: String) -> void:
	_bar.value = float(done) / maxf(float(total), 1.0)
	_bar.tooltip_text = "%d / %d — %s" % [done, total, label]

func _on_fetch() -> void:
	if _busy:
		return
	_busy = true
	_fetch_button.disabled = true
	_cancel_button.disabled = false
	_log.clear()
	var sets := {}
	for kind in CURATED.keys():
		if (_checks[kind] as CheckBox).button_pressed:
			sets[kind] = PackedStringArray(CURATED[kind])
	var extras := _extra.text.strip_edges()
	if not extras.is_empty():
		await _resolve_extras(extras, sets)
	var resolution := _res_option.get_item_text(_res_option.selected).to_lower()
	_append("Fetching at %s ..." % resolution)
	await _api.fetch(sets, resolution)

## Extra slugs are classified by querying each type index once.
func _resolve_extras(csv: String, sets: Dictionary) -> void:
	var wanted := PackedStringArray()
	for token in csv.split(",", false):
		var slug := String(token).strip_edges()
		if not slug.is_empty():
			wanted.append(slug)
	if wanted.is_empty():
		return
	for kind in ["textures", "hdris", "models"]:
		var index: Variant = await _api.api_json("assets?t=%s" % kind)
		if typeof(index) != TYPE_DICTIONARY:
			continue
		for slug in wanted:
			if (index as Dictionary).has(slug):
				var bucket: PackedStringArray = sets.get(kind, PackedStringArray())
				if not bucket.has(slug):
					bucket.append(slug)
				sets[kind] = bucket
				_append("  + %s (%s)" % [slug, kind])

func _on_cancel() -> void:
	if _api != null:
		_api.cancelled = true
	_append("Cancel requested.")

func _on_finished(summary: Dictionary) -> void:
	_busy = false
	_fetch_button.disabled = false
	_cancel_button.disabled = true
	_bar.value = 1.0
	_append("Done: %d new / %d total file(s)." % [summary.get("downloaded", 0), summary.get("total", 0)])
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		_append("Scanning project so Godot imports the new files ...")
		fs.scan()
		await get_tree().create_timer(1.0).timeout
		_on_tune()

func _on_tune() -> void:
	var touched := PolyHavenImportTuner.tune_all("res://assets/polyhaven", _append)
	_append("Tuned %d import file(s)." % touched.size())
	if touched.is_empty():
		return
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.reimport_files(touched)
		_append("Reimported.")

func _on_reload() -> void:
	AssetLibrary.reload_manifest()
	Materials.clear_cache()
	_append("AssetLibrary manifest reloaded (%d textures, %d HDRIs, %d models)." % [
		(AssetLibrary.manifest.get("textures", {}) as Dictionary).size(),
		(AssetLibrary.manifest.get("hdris", {}) as Dictionary).size(),
		(AssetLibrary.manifest.get("models", {}) as Dictionary).size()])
