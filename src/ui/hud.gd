class_name HUD
extends CanvasLayer
## Heads-up display, damage numbers and the loading screen.
##
## Drawn entirely in code. Text uses a SystemFont chain that resolves to the
## Japanese UI faces shipped with Windows 11 first, so the Japanese labels
## render natively on the target machine without bundling a font.

const ORANGE := Color(1.0, 0.45, 0.08)
const ORANGE_DIM := Color(0.55, 0.20, 0.03)
const INK := Color(0.05, 0.045, 0.05, 0.72)
const WHITE := Color(0.96, 0.94, 0.92)

var font: SystemFont

var _health_ratio: float = 1.0
var _health_lag: float = 1.0
var _energy_ratio: float = 1.0
var _combo: int = 0
var _combo_timer: float = 0.0
var _wave: int = 0
var _remaining: int = 0
var _toast_text: String = ""
var _toast_time: float = 0.0
var _hit_flash: float = 0.0
var _visible_hud: bool = true
var _help_countdown: float = 12.0

var _bars: Control
var _center: Control
var _post: ColorRect
var _post_material: ShaderMaterial
var _loading: Control
var _loading_label: Label
var _loading_bar: ProgressBar
var _help: Control
var _numbers: Node2D
var _damage_pool: Array = []

func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS

	font = SystemFont.new()
	# Windows 11 Japanese UI faces first, then common Linux/macOS CJK fallbacks.
	font.font_names = PackedStringArray([
		"Yu Gothic UI", "Meiryo UI", "Yu Gothic", "Meiryo", "MS Gothic",
		"Noto Sans CJK JP", "Noto Sans JP", "Hiragino Sans", "sans-serif"])
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO

	_build_post_process()
	_build_bars()
	_build_center()
	_build_help()
	_build_loading()

	_numbers = Node2D.new()
	_numbers.name = "DamageNumbers"
	add_child(_numbers)
	_build_death_overlay()

	Signals.player_died.connect(_show_death_overlay)
	Signals.player_health_changed.connect(func(c: float, m: float) -> void:
		if c < _health_ratio * m:
			_hit_flash = 1.0
		_health_ratio = c / maxf(m, 0.001))
	Signals.player_energy_changed.connect(func(c: float, m: float) -> void: _energy_ratio = c / maxf(m, 0.001))
	Signals.combo_changed.connect(func(count: int, timer: float) -> void:
		_combo = count
		_combo_timer = timer)
	Signals.wave_changed.connect(func(index: int, remaining: int) -> void:
		_wave = index
		_remaining = remaining)
	Signals.enemy_damaged.connect(_on_enemy_damaged)
	Signals.toast.connect(_show_toast)
	Signals.world_build_progress.connect(_on_build_progress)
	Signals.world_build_finished.connect(func() -> void: _hide_loading())

# ---------------------------------------------------------------------------

func _build_post_process() -> void:
	var layer_node := CanvasLayer.new()
	layer_node.name = "PostProcess"
	layer_node.layer = 1
	add_child(layer_node)

	_post = ColorRect.new()
	_post.name = "PostRect"
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_material = ShaderMaterial.new()
	_post_material.shader = load("res://shaders/post_process.gdshader")
	_post_material.set_shader_parameter("film_grain", float(Settings.get_value("film_grain", 0.35)))
	_post_material.set_shader_parameter("chromatic_aberration", float(Settings.get_value("chromatic_aberration", 0.45)))
	_post_material.set_shader_parameter("vignette", float(Settings.get_value("vignette", 0.42)))
	_post_material.set_shader_parameter("lens_dirt", float(Settings.get_value("lens_dirt", 0.5)))
	_post.material = _post_material
	layer_node.add_child(_post)

func _build_bars() -> void:
	_bars = Control.new()
	_bars.name = "Bars"
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	add_child(_bars)

func _build_center() -> void:
	_center = Control.new()
	_center.name = "Reticle"
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.draw.connect(_draw_center)
	add_child(_center)

func _build_help() -> void:
	_help = PanelContainer.new()
	_help.name = "Help"
	_help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help.offset_right = -28.0
	_help.offset_top = 24.0
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = Color(1.0, 0.45, 0.08, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_help.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", WHITE)
	label.text = """DIGIHARIMAN — ORANGE PROTOCOL

WASD  移動        Shift  ダッシュ走行
Space ジャンプ／二段ジャンプ
Ctrl  回避ダッシュ（無敵）
左クリック 連続斬撃（3段）
右クリック エナジーボルト
中クリック ロックオン
P     フォトモード    H  この表示
F1    画質プリセット切替
Esc   マウスカーソル解放"""
	_help.add_child(label)
	add_child(_help)

func _build_loading() -> void:
	_loading = ColorRect.new()
	_loading.name = "Loading"
	_loading.color = Color(0.035, 0.030, 0.028)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-260, -60)
	box.custom_minimum_size = Vector2(520, 120)
	box.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", ORANGE)
	title.text = "DIGIHARIMAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.add_theme_font_override("font", font)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", WHITE)
	subtitle.text = "ORANGE PROTOCOL"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	_loading_bar = ProgressBar.new()
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 1.0
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(0, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ORANGE
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.10, 0.09)
	bg.set_corner_radius_all(4)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	_loading_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_loading_bar)

	_loading_label = Label.new()
	_loading_label.add_theme_font_override("font", font)
	_loading_label.add_theme_font_size_override("font_size", 14)
	_loading_label.add_theme_color_override("font_color", Color(0.65, 0.62, 0.60))
	_loading_label.text = "世界を生成中..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loading_label)

	_loading.add_child(box)
	add_child(_loading)

var _death: Control = null

func _build_death_overlay() -> void:
	_death = ColorRect.new()
	_death.name = "DeathOverlay"
	(_death as ColorRect).color = Color(0.10, 0.01, 0.0, 0.0)
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-260, -50)
	box.custom_minimum_size = Vector2(520, 100)
	box.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.30, 0.10))
	title.text = "機能停止"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := Label.new()
	hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", WHITE)
	hint.text = "R キーで再起動"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_death.add_child(box)
	_death.hide()
	add_child(_death)

func _show_death_overlay() -> void:
	if _death == null:
		return
	_death.modulate.a = 0.0
	_death.show()
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(_death, "modulate:a", 1.0, 1.2)
	tween.parallel().tween_property(_death, "color", Color(0.10, 0.01, 0.0, 0.55), 1.2)

func _on_build_progress(stage: String, ratio: float) -> void:
	const LABELS := {
		"terrain": "地形を生成中...",
		"streets": "街路を敷設中...",
		"buildings": "建築を生成中...",
		"plaza": "中央広場を構築中...",
		"props": "小物を配置中...",
		"nature": "植生を散布中...",
		"background": "遠景を描画中...",
		"signage": "ネオンを点灯中...",
		"hero": "デジハリマンを構築中...",
		"creatures": "ノイズ体を生成中...",
		"done": "起動しています...",
	}
	if _loading_label != null:
		_loading_label.text = String(LABELS.get(stage, stage))
	if _loading_bar != null:
		_loading_bar.value = ratio

func _hide_loading() -> void:
	if _loading == null:
		return
	var tween := create_tween()
	tween.tween_property(_loading, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tween.tween_callback(_loading.hide)

# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# The controls card earns its screen space for the first few seconds only;
	# H brings it back.
	if _help_countdown > 0.0 and _help.visible:
		_help_countdown -= delta
		if _help_countdown <= 0.0:
			var tween := create_tween()
			tween.tween_property(_help, "modulate:a", 0.0, 0.8)
			tween.tween_callback(func() -> void:
				_help.hide()
				_help.modulate.a = 1.0)
	_health_lag = move_toward(_health_lag, _health_ratio, delta * 0.55)
	_hit_flash = maxf(0.0, _hit_flash - delta * 2.2)
	_combo_timer = maxf(0.0, _combo_timer - delta)
	_toast_time = maxf(0.0, _toast_time - delta)
	if _post_material != null:
		_post_material.set_shader_parameter("hit_flash", _hit_flash * 0.7)
	_bars.queue_redraw()
	_center.queue_redraw()
	_update_damage_numbers(delta)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ui"):
		if not _help.visible:
			# First H after the card auto-hid: just bring the card back.
			_help_countdown = 20.0
			_help.show()
		else:
			_visible_hud = not _visible_hud
			_bars.visible = _visible_hud
			_center.visible = _visible_hud
			_help.visible = _visible_hud

# ------------------------------------------------------------------ drawing --

func _draw_bars() -> void:
	var size := _bars.size
	var x := 42.0
	var y := size.y - 92.0
	var width := 420.0

	_draw_meter(Rect2(x, y, width, 16.0), _health_ratio, _health_lag, ORANGE, "生命力")
	_draw_meter(Rect2(x, y + 30.0, width * 0.78, 10.0), _energy_ratio, _energy_ratio,
		Color(0.35, 0.75, 1.0), "エナジー")

	if _combo > 1:
		var alpha := clampf(_combo_timer / 2.6, 0.0, 1.0)
		var scale := 1.0 + clampf(float(_combo) / 30.0, 0.0, 0.8)
		var text := "%d COMBO" % _combo
		var pos := Vector2(size.x - 260.0, size.y * 0.42)
		_bars.draw_string(font, pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(34 * scale), Color(0, 0, 0, 0.55 * alpha))
		_bars.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(34 * scale), Color(ORANGE, alpha))

	var wave_text := "WAVE %d   残り %d" % [_wave, _remaining]
	_bars.draw_string(font, Vector2(x, 52.0), wave_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, WHITE)
	_bars.draw_string(font, Vector2(x, 78.0), "SCORE %d" % Game.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(0.72, 0.70, 0.68))

	if _toast_time > 0.0:
		var alpha := clampf(_toast_time, 0.0, 1.0)
		_bars.draw_string(font, Vector2(size.x * 0.5 - 200.0, size.y * 0.26), _toast_text,
			HORIZONTAL_ALIGNMENT_CENTER, 400, 22, Color(WHITE, alpha))

func _draw_meter(rect: Rect2, value: float, lag: float, color: Color, label: String) -> void:
	_bars.draw_rect(Rect2(rect.position - Vector2(2, 2), rect.size + Vector2(4, 4)), INK)
	# The lag bar drains behind the real value, so a big hit is legible.
	if lag > value:
		_bars.draw_rect(Rect2(rect.position, Vector2(rect.size.x * lag, rect.size.y)),
			Color(1.0, 0.25, 0.15, 0.55))
	_bars.draw_rect(Rect2(rect.position, Vector2(rect.size.x * value, rect.size.y)), color)
	# Tick marks every 25% keep the bar readable at a glance.
	for i in range(1, 4):
		var tx := rect.position.x + rect.size.x * 0.25 * float(i)
		_bars.draw_line(Vector2(tx, rect.position.y), Vector2(tx, rect.position.y + rect.size.y),
			Color(0, 0, 0, 0.45), 1.0)
	_bars.draw_string(font, rect.position + Vector2(0, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.75, 0.73, 0.71))

func _draw_center() -> void:
	var c := _center.size * 0.5
	var player := Game.player as Player
	var locked := player != null and is_instance_valid(player) and player.lock_on_target != null

	if locked:
		var camera := get_viewport().get_camera_3d()
		var target: Node3D = player.lock_on_target
		if camera != null and is_instance_valid(target) and not camera.is_position_behind(target.global_position):
			var screen := camera.unproject_position(target.global_position + Vector3.UP)
			var r := 22.0 + sin(Time.get_ticks_msec() * 0.004) * 2.5
			# Four corner brackets rather than a full box: less occlusion.
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p: Vector2 = screen + corner * r
				_center.draw_line(p, p - Vector2(corner.x * 8.0, 0), ORANGE, 2.0)
				_center.draw_line(p, p - Vector2(0, corner.y * 8.0), ORANGE, 2.0)
	# Reticle
	_center.draw_circle(c, 2.4, Color(WHITE, 0.85))
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_center.draw_line(c + d * 9.0, c + d * 15.0, Color(WHITE, 0.55), 1.5)

# ---------------------------------------------------------- damage numbers --

func _on_enemy_damaged(_enemy: Node3D, amount: float, crit: bool, world_pos: Vector3) -> void:
	_damage_pool.append({
		"pos": world_pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.6), randf_range(-0.3, 0.3)),
		"text": "%d" % roundi(amount),
		"life": 0.95,
		"crit": crit,
		"rise": 0.0,
	})

func _update_damage_numbers(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var alive: Array = []
	for entry in _damage_pool:
		entry["life"] = float(entry["life"]) - delta
		entry["rise"] = float(entry["rise"]) + delta * 1.4
		if float(entry["life"]) > 0.0:
			alive.append(entry)
	_damage_pool = alive
	_numbers.queue_redraw()
	if camera == null:
		return
	if not _numbers.draw.is_connected(_draw_numbers):
		_numbers.draw.connect(_draw_numbers)

func _draw_numbers() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for entry in _damage_pool:
		var world: Vector3 = entry["pos"] + Vector3(0, float(entry["rise"]), 0)
		if camera.is_position_behind(world):
			continue
		var screen := camera.unproject_position(world)
		var life := float(entry["life"])
		var alpha := clampf(life / 0.95, 0.0, 1.0)
		var crit: bool = entry["crit"]
		var size := 30 if crit else 21
		var color := Color(1.0, 0.86, 0.35) if crit else Color(1.0, 0.62, 0.28)
		_numbers.draw_string(font, screen + Vector2(2, 2), entry["text"], HORIZONTAL_ALIGNMENT_CENTER, -1,
			size, Color(0, 0, 0, 0.5 * alpha))
		_numbers.draw_string(font, screen, entry["text"], HORIZONTAL_ALIGNMENT_CENTER, -1,
			size, Color(color, alpha))

func _show_toast(text: String, seconds: float) -> void:
	_toast_text = text
	_toast_time = seconds
