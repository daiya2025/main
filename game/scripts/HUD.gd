class_name HUD
extends CanvasLayer
## ゲームプレイ用 HUD: クロスヘア / HP / 討伐数 / 操作ガイド

var _hp_fill: ColorRect
var _kills_label: Label
var _hint: Label
var _hint_timer := 10.0


func setup(player: Player) -> void:
	layer = 10
	player.hp_changed.connect(_on_hp)
	player.kills_changed.connect(_on_kills)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -10
	crosshair.offset_top = -14
	crosshair.add_theme_font_size_override("font_size", 22)
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	add_child(crosshair)

	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.45)
	hp_bg.anchor_top = 1.0
	hp_bg.anchor_bottom = 1.0
	hp_bg.offset_left = 32
	hp_bg.offset_top = -52
	hp_bg.offset_right = 292
	hp_bg.offset_bottom = -32
	add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.15, 0.9, 0.55)
	_hp_fill.anchor_right = 1.0
	_hp_fill.anchor_bottom = 1.0
	_hp_fill.offset_left = 2
	_hp_fill.offset_top = 2
	_hp_fill.offset_right = -2
	_hp_fill.offset_bottom = -2
	hp_bg.add_child(_hp_fill)

	_kills_label = Label.new()
	_kills_label.text = "討伐 0 / 5"
	_kills_label.anchor_top = 1.0
	_kills_label.anchor_bottom = 1.0
	_kills_label.offset_left = 32
	_kills_label.offset_top = -84
	_kills_label.offset_right = 300
	_kills_label.offset_bottom = -56
	_kills_label.add_theme_font_size_override("font_size", 20)
	add_child(_kills_label)

	_hint = Label.new()
	_hint.text = "WASD 移動 / Shift 疾走 / Space ジャンプ / 左クリック 攻撃 / Esc マウス解放"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 0.92
	_hint.anchor_bottom = 0.97
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	add_child(_hint)


func _process(delta: float) -> void:
	if _hint and _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer < 3.0:
			_hint.modulate.a = maxf(_hint_timer / 3.0, 0.0)


func _on_hp(hp: float) -> void:
	_hp_fill.anchor_right = clampf(hp / 100.0, 0.0, 1.0)
	_hp_fill.color = Color(0.15, 0.9, 0.55).lerp(Color(0.95, 0.2, 0.2), 1.0 - hp / 100.0)


func _on_kills(kills: int) -> void:
	_kills_label.text = "討伐 %d / 5" % kills
