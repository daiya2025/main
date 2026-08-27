class_name DemoDirector
extends Node3D
## 60秒シネマティックデモの監督。
## - 8ショット構成のカメラワーク (クレーン / ドリー / トラッキング / オービット)
## - モンスターとプレイヤーへの演技指示 (タイムラインイベント)
## - レターボックス / タイトル / フェード
## - Movie Maker モード (--write-movie) では 60 秒で自動終了し、
##   tools/make_demo_mp4.py が MP4 に変換する。

const DURATION := 60.0

var world: Node3D
var player: Player
var monsters: Dictionary = {}
var attrs: CameraAttributesPractical

var cam: Camera3D
var t := 0.0
var _shots: Array = []
var _events: Array = []
var _next_event := 0
var _fade: ColorRect
var _title: Label
var _subtitle: Label
var _finished := false


func setup(p_world: Node3D, p_player: Player, p_monsters: Dictionary, env: Dictionary) -> void:
	world = p_world
	player = p_player
	monsters = p_monsters
	attrs = env.get("attributes")

	cam = Camera3D.new()
	cam.name = "DemoCamera"
	cam.fov = 55.0
	cam.near = 0.15
	cam.far = 6000.0
	add_child(cam)
	cam.current = true

	player.external_control = true
	for m in monsters.values():
		m.demo_mode = true

	_build_overlay()
	_build_shots()
	_build_events()
	print("[Demo] 60秒シネマティック開始 (%d ショット / %d イベント)" % [_shots.size(), _events.size()])


# ------------------------------------------------------------------ ショット定義

func _mv(t0: float, t1: float, from: Vector3, to: Vector3, look_from: Vector3, look_to: Vector3,
		fov0: float, fov1: float, target: String = "") -> Dictionary:
	return {"type": "move", "t0": t0, "t1": t1, "from": from, "to": to,
			"look_from": look_from, "look_to": look_to, "fov0": fov0, "fov1": fov1,
			"target": target, "target_off": Vector3.ZERO}


func _build_shots() -> void:
	# 1. 夜景クレーン: 上空から街と裂け目を見せる
	_shots.append(_mv(0.0, 9.0, Vector3(-45, 240, 160), Vector3(0, 115, 85),
			Vector3(0, 15, 0), Vector3(0, 45, -30), 62, 50))
	# 2. ストリートドリー: 濡れた路面から裂け目へティルトアップ
	_shots.append(_mv(9.0, 15.5, Vector3(22, 2.6, 36), Vector3(9, 2.0, 17),
			Vector3(0, 2, 8), Vector3(0, 42, -30), 55, 50))
	# 3. ネオンリッパー疾走トラッキング
	var s3 := _mv(15.5, 22.5, Vector3(48, 2.6, 22), Vector3(34, 1.1, 4),
			Vector3.ZERO, Vector3.ZERO, 46, 38, "neon_ripper")
	s3["target_off"] = Vector3(0, 1.2, 0)
	_shots.append(s3)
	# 4. カゲオニ戦闘 ローアングル
	var s4 := _mv(22.5, 30.5, Vector3(-17, 1.6, -6), Vector3(-23, 3.4, -14),
			Vector3.ZERO, Vector3.ZERO, 46, 42, "kage_oni")
	s4["target_off"] = Vector3(0, 2.6, 0)
	_shots.append(s4)
	# 5. スクランブラー ティルトアップ
	var s5 := _mv(30.5, 37.5, Vector3(7, 1.6, -8), Vector3(11, 5.5, -12),
			Vector3.ZERO, Vector3.ZERO, 50, 44, "scrambler")
	s5["target_off"] = Vector3(0, 1.0, 0)
	_shots.append(s5)
	# 6. ゲンブ進撃ワイド
	var s6 := _mv(37.5, 45.5, Vector3(-25, 1.4, 14), Vector3(-33, 2.8, 22),
			Vector3.ZERO, Vector3.ZERO, 46, 42, "genbu")
	s6["target_off"] = Vector3(0, 1.8, 0)
	_shots.append(s6)
	# 7. トシクイ シルエット プッシュイン
	var s7 := _mv(45.5, 54.0, Vector3(0, 3, -48), Vector3(3, 13, -86),
			Vector3.ZERO, Vector3.ZERO, 42, 32, "toshikui")
	s7["target_off"] = Vector3(0, 14, 0)
	_shots.append(s7)
	# 8. ヒーローショット (プレイヤー周回) + タイトル
	_shots.append({"type": "orbit", "t0": 54.0, "t1": 60.0, "target": "player",
			"target_off": Vector3(0, 1.4, 0), "r0": 5.5, "r1": 3.2,
			"h0": 1.9, "h1": 1.5, "a0": 0.4, "a1": 2.6, "fov0": 46, "fov1": 40})


func _target_node(key: String) -> Node3D:
	if key == "player":
		return player
	var m: Node3D = monsters.get(key)
	return m if is_instance_valid(m) else null


# ------------------------------------------------------------------ 演技イベント

func _ev(at: float, fn: Callable) -> void:
	_events.append({"t": at, "fn": fn})


func _build_events() -> void:
	_ev(0.1, func() -> void:
		player.global_position = Vector3(14, 0.5, 26)
		_dof(false))
	_ev(9.0, func() -> void:
		player.command_move_to(Vector3(4, 0.5, 12)))
	_ev(15.4, func() -> void:
		var r: MonsterBase = monsters.get("neon_ripper")
		if r:
			r.global_position = Vector3(44, 0.5, 16)
			r.demo_goto(Vector3(28, 0.5, -2))
		_dof(true, 25.0))
	_ev(19.0, func() -> void:
		var r: MonsterBase = monsters.get("neon_ripper")
		if r:
			r.demo_goto(Vector3(12, 0.5, -14)))
	_ev(22.4, func() -> void:
		var k: MonsterBase = monsters.get("kage_oni")
		if k:
			k.global_position = Vector3(-30, 0.5, -22)
			k.demo_goto(Vector3(-27, 0.5, -17))
		player.global_position = Vector3(-23, 0.5, -13)
		_dof(true, 18.0))
	for at in [24.5, 26.0, 27.5, 29.0]:
		_ev(at, func() -> void:
			player.command_attack()
			var k: MonsterBase = monsters.get("kage_oni")
			if k:
				k.hit(1.0))  # 被弾フラッシュ演出 (HPは十分残る)
	_ev(30.4, func() -> void:
		var s: MonsterBase = monsters.get("scrambler")
		if s:
			s.global_position = Vector3(10, 11, -16)
			s.demo_goto(Vector3(14, 11, -24))
		_dof(false))
	_ev(37.4, func() -> void:
		var g: MonsterBase = monsters.get("genbu")
		if g:
			g.global_position = Vector3(-40, 0.5, 29)
			g.demo_goto(Vector3(-30, 0.5, 20)))
	_ev(45.4, func() -> void:
		var k: MonsterBase = monsters.get("toshikui")
		if k:
			k.global_position = Vector3(14, 0.5, -175)
			k.demo_goto(Vector3(-8, 0.5, -125))
		_dof(false))
	_ev(53.9, func() -> void:
		player.global_position = Vector3(0, 0.5, 16)
		player.command_move_to(Vector3(0, 0.5, 10))
		_hero_lights(Vector3(0, 1.6, 10))
		_dof(true, 8.0))
	_events.sort_custom(func(a, b) -> bool: return a["t"] < b["t"])


## ヒーローショット用の簡易3灯 (キー / リム)
func _hero_lights(center: Vector3) -> void:
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.75)
	key.light_energy = 1.4
	key.omni_range = 10.0
	key.position = center + Vector3(2.5, 1.2, 3.0)
	add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.4, 0.7, 1.0)
	rim.light_energy = 2.2
	rim.omni_range = 9.0
	rim.position = center + Vector3(-1.5, 2.0, -3.0)
	add_child(rim)


func _dof(enabled: bool, dist: float = 30.0) -> void:
	if attrs == null:
		return
	attrs.dof_blur_far_enabled = enabled
	attrs.dof_blur_far_distance = dist
	attrs.dof_blur_far_transition = dist * 1.5


# ------------------------------------------------------------------ 進行

func _process(delta: float) -> void:
	if _finished:
		return
	t += delta
	while _next_event < _events.size() and _events[_next_event]["t"] <= t:
		(_events[_next_event]["fn"] as Callable).call()
		_next_event += 1
	_update_camera()
	_update_overlay()
	if t >= DURATION + 0.2:
		_finished = true
		if OS.has_feature("movie"):
			get_tree().quit()
		else:
			print("[Demo] 60秒デモ終了")
			get_tree().quit()


func _update_camera() -> void:
	var shot: Dictionary = {}
	for s in _shots:
		if t >= s["t0"] and t < s["t1"]:
			shot = s
			break
	if shot.is_empty():
		shot = _shots.back()
	var u := clampf((t - shot["t0"]) / maxf(shot["t1"] - shot["t0"], 0.001), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)

	if shot["type"] == "orbit":
		var center := Vector3.ZERO
		var node := _target_node(shot["target"])
		if node:
			center = node.global_position + shot["target_off"]
		var ang := lerpf(shot["a0"], shot["a1"], e)
		var radius := lerpf(shot["r0"], shot["r1"], e)
		var h := lerpf(shot["h0"], shot["h1"], e)
		var pos := center + Vector3(cos(ang) * radius, h - shot["target_off"].y + 0.2, sin(ang) * radius)
		cam.fov = lerpf(shot["fov0"], shot["fov1"], e)
		cam.look_at_from_position(pos, center, Vector3.UP)
	else:
		var pos: Vector3 = (shot["from"] as Vector3).lerp(shot["to"], e)
		var look: Vector3
		if shot["target"] != "":
			var node := _target_node(shot["target"])
			look = (node.global_position + shot["target_off"]) if node else Vector3.ZERO
		else:
			look = (shot["look_from"] as Vector3).lerp(shot["look_to"], e)
		cam.fov = lerpf(shot["fov0"], shot["fov1"], e)
		if pos.distance_to(look) > 0.5:
			cam.look_at_from_position(pos, look, Vector3.UP)


# ------------------------------------------------------------------ オーバーレイ

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CineOverlay"
	layer.layer = 50
	add_child(layer)

	for at_top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		if at_top:
			bar.anchor_top = 0.0
			bar.anchor_bottom = 0.085
		else:
			bar.anchor_top = 0.915
			bar.anchor_bottom = 1.0
		layer.add_child(bar)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.anchor_right = 1.0
	_fade.anchor_bottom = 1.0
	layer.add_child(_fade)

	_title = Label.new()
	_title.text = "SHIBUYA RIFT"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.anchor_top = 0.40
	_title.anchor_bottom = 0.52
	_title.add_theme_font_size_override("font_size", 110)
	_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.95))
	_title.add_theme_constant_override("outline_size", 18)
	_title.add_theme_color_override("font_outline_color", Color(0.9, 0.02, 0.4, 0.9))
	_title.modulate.a = 0.0
	layer.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "SHIBUYA STATION  ×  PLATEAU  ×  GODOT 4"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.anchor_left = 0.0
	_subtitle.anchor_right = 1.0
	_subtitle.anchor_top = 0.565
	_subtitle.anchor_bottom = 0.62
	_subtitle.add_theme_font_size_override("font_size", 28)
	_subtitle.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.9))
	_subtitle.modulate.a = 0.0
	layer.add_child(_subtitle)


func _update_overlay() -> void:
	# 冒頭フェードイン / 最後フェードアウト
	var a := 0.0
	if t < 2.0:
		a = 1.0 - t / 2.0
	elif t > 58.2:
		a = (t - 58.2) / 1.8
	_fade.color.a = clampf(a, 0.0, 1.0)
	# タイトル 54.5→56 フェードイン
	var ta := clampf((t - 54.5) / 1.5, 0.0, 1.0)
	_title.modulate.a = ta
	_subtitle.modulate.a = clampf((t - 55.5) / 1.5, 0.0, 1.0)
