class_name DemoDirector
extends Node3D
## 60秒シネマティックデモの監督 — 物語構成版。
##
## 【物語】平穏な雨の渋谷 → 上空に次元の裂け目が誕生 → モンスターが出現し街を侵略
##        → プレイヤー参戦 → ネオンリッパーを撃破 → カゲオニと激闘 → 増援と巨獣で絶望
##        → それでも構える主人公 → タイトル
##
## - 9ショット構成 (クレーン/ティルトアップ/トラッキング/バトルカム/ライズ/プッシュイン/オービット)
## - スポーンフラッシュ / 裂け目誕生 / 撃破ディゾルブなどのイベント演出
## - Movie Maker モード (--write-movie) では 60 秒で自動終了し MP4 化される

const DURATION := 60.0

var world: Node3D
var player: Player
var monsters: Dictionary = {}
var props: CityProps
var attrs: CameraAttributesPractical

var cam: Camera3D
var t := 0.0
var _shots: Array = []
var _events: Array = []
var _next_event := 0
var _fade: ColorRect
var _title: Label
var _subtitle: Label
var _chapter: Label
var _white := 0.0
var _last_look := Vector3.ZERO
var _cam_shake := 0.0
var _finished := false


func setup(p_world: Node3D, p_player: Player, p_monsters: Dictionary,
		env: Dictionary, p_props: CityProps) -> void:
	world = p_world
	player = p_player
	monsters = p_monsters
	props = p_props
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
	# タイムライン同期の劇伴 (tools/generate_audio.py 製)
	AudioKit.music(self, "music_demo", -3.0, false)
	print("[Demo] 60秒シネマティック (物語構成) 開始: %d ショット / %d イベント" % [_shots.size(), _events.size()])


# ------------------------------------------------------------------ ショット定義

func _mv(t0: float, t1: float, from: Vector3, to: Vector3, look_from: Vector3, look_to: Vector3,
		fov0: float, fov1: float, target: String = "", target_off := Vector3.ZERO) -> Dictionary:
	return {"type": "move", "t0": t0, "t1": t1, "from": from, "to": to,
			"look_from": look_from, "look_to": look_to, "fov0": fov0, "fov1": fov1,
			"target": target, "target_off": target_off}


func _build_shots() -> void:
	# 1.「平穏」雨の渋谷を見下ろすクレーンダウン (裂け目はまだ無い)
	_shots.append(_mv(0.0, 7.0, Vector3(-40, 220, 150), Vector3(0, 95, 70),
			Vector3(0, 10, 0), Vector3(0, 20, 0), 60, 52))
	# 2.「裂け目誕生」路上から空へティルトアップ → 8秒で裂け目が裂ける
	_shots.append(_mv(7.0, 13.0, Vector3(14, 2.2, 26), Vector3(9, 2.6, 18),
			Vector3(0, 3, -5), Vector3(0, 52, -30), 55, 50))
	# 3.「出現」カゲオニ降臨 → こちらへ歩いてくる / 背後をリッパーが疾走
	_shots.append(_mv(13.0, 19.5, Vector3(-4, 1.4, 6), Vector3(-10, 1.9, 0),
			Vector3.ZERO, Vector3.ZERO, 46, 44, "kage_oni", Vector3(0, 2.5, 0)))
	# 4.「参戦」プレイヤーが雨の中を疾走してくる (サイドから見送るトラッキング)
	_shots.append(_mv(19.5, 26.0, Vector3(17, 2.2, 19), Vector3(9.5, 1.7, 10),
			Vector3.ZERO, Vector3.ZERO, 44, 40, "player", Vector3(0, 1.15, 0)))
	# 5.「初撃破」リッパー vs 主人公: 両者が収まるサイドの二人ショット
	_shots.append(_mv(26.0, 33.5, Vector3(-3.5, 1.3, 3.0), Vector3(-1.0, 1.9, 6.5),
			Vector3(4.4, 1.2, 4.6), Vector3(4.4, 1.2, 4.4), 42, 40))
	# 6.「カゲオニ戦」鬼と主人公の対峙を横から (振り下ろし〜反撃)
	_shots.append(_mv(33.5, 41.5, Vector3(2.5, 1.6, 10.5), Vector3(0.5, 2.6, 8.5),
			Vector3(-2.8, 1.9, 3.2), Vector3(-3.0, 1.7, 3.6), 46, 44))
	# 7.「増援」カメラ上昇 — ゲンブ進撃 / スクランブラー滑空
	_shots.append(_mv(41.5, 46.0, Vector3(4, 1.8, 12), Vector3(2, 13, 22),
			Vector3(-10, 2, 8), Vector3(-14, 5, 10), 50, 52))
	# 8.「絶望」ビル群の谷の彼方から60mの三倍体トシクイが迫る
	_shots.append(_mv(46.0, 52.0, Vector3(0, 4, -55), Vector3(7, 24, -95),
			Vector3.ZERO, Vector3.ZERO, 46, 36, "toshikui", Vector3(0, 38, 0)))
	# 9.「決意」主人公の背中越しに巨獣を望むロー・オービット + タイトル
	_shots.append({"type": "orbit", "t0": 52.0, "t1": 60.0, "target": "player",
			"target_off": Vector3(0, 1.35, 0), "r0": 5.4, "r1": 3.4,
			"h0": 1.8, "h1": 1.3, "a0": 2.55, "a1": 0.95, "fov0": 46, "fov1": 40})


func _target_node(key: String) -> Node3D:
	if key == "player":
		return player
	var m: Node3D = monsters.get(key)
	return m if is_instance_valid(m) else null


# ------------------------------------------------------------------ 演技イベント

func _ev(at: float, fn: Callable) -> void:
	_events.append({"t": at, "fn": fn})


func _monster(key: String) -> MonsterBase:
	var m: Node3D = monsters.get(key)
	return m as MonsterBase if is_instance_valid(m) else null


func _build_events() -> void:
	# --- 0s ステージング: 裂け目を隠し、役者を袖へ ---
	_ev(0.05, func() -> void:
		props.set_rift_active(false)
		player.global_position = Vector3(30, 0.6, 34)
		var kage := _monster("kage_oni")
		if kage:
			kage.global_position = Vector3(-120, 0.5, -80)
		var ripper := _monster("neon_ripper")
		if ripper:
			ripper.global_position = Vector3(150, 0.5, 60)
		var genbu := _monster("genbu")
		if genbu:
			genbu.global_position = Vector3(-140, 0.5, 100)
		var scr := _monster("scrambler")
		if scr:
			scr.global_position = Vector3(190, 11, 90)
		_dof(false))

	# --- 8s 裂け目誕生 (白閃光 + 稲妻状に裂ける + braam) ---
	_ev(8.0, func() -> void:
		_white = 0.9
		_cam_shake = 0.9
		props.rift_birth(2.5)
		AudioKit.sfx(self, "rift", Vector3.INF, -1.0))
	_ev(8.1, func() -> void:
		_flash_burst(Vector3(0, 66, -30), Color(1.0, 0.3, 0.7), 22.0))

	# --- 13.6s カゲオニ降臨 / 16.2s リッパー疾走 ---
	_ev(13.6, func() -> void:
		var kage := _monster("kage_oni")
		if kage:
			kage.global_position = Vector3(-16, 0.5, -8)
			kage.demo_goto(Vector3(-8, 0.5, -3))
			_flash_burst(kage.global_position + Vector3(0, 2, 0), Color(1.0, 0.4, 0.1), 5.0)
			AudioKit.sfx(self, "spawn", kage.global_position, -2.0)
		_dof(true, 22.0))
	_ev(14.3, func() -> void:
		var kage := _monster("kage_oni")
		if kage:
			AudioKit.sfx(self, "roar_kage", kage.global_position + Vector3(0, 3, 0), 0.0))
	_ev(16.2, func() -> void:
		var ripper := _monster("neon_ripper")
		if ripper:
			ripper.global_position = Vector3(24, 0.5, -4)
			ripper.demo_goto(Vector3(4, 0.5, -5))
			_flash_burst(ripper.global_position + Vector3(0, 1.2, 0), Color(0.2, 1.0, 0.9), 4.0)
			AudioKit.sfx(self, "spawn", ripper.global_position, -3.0, 1.2)
			AudioKit.sfx(self, "screech_ripper", ripper.global_position + Vector3(0, 1.5, 0), -2.0))

	# --- 19.6s プレイヤー参戦 (全力疾走) ---
	_ev(19.6, func() -> void:
		player.command_move_to(Vector3(4, 0.5, 6), true)
		_dof(false))

	# --- 26〜33.5s リッパー戦: 対峙 → 3撃で撃破 ---
	_ev(26.2, func() -> void:
		var ripper := _monster("neon_ripper")
		if ripper:
			ripper.demo_goto(Vector3(4.5, 0.5, 3.2))   # プレイヤー(4,6)の目前へ
			player.command_face_target(ripper)          # 常に敵へ正対
		player.combat_mode = true                       # 戦闘構え
		_dof(true, 12.0))
	for atk in [[27.3, 45.0], [28.9, 45.0], [30.4, 400.0]]:
		_ev(atk[0], func() -> void:
			player.command_attack()
			var ripper := _monster("neon_ripper")
			if ripper:
				var dir := (ripper.global_position - player.global_position)
				dir.y = 0
				ripper.hit(atk[1], dir.normalized())
			_cam_shake = maxf(_cam_shake, 0.55))

	# --- 33.5〜41.5s カゲオニ戦: 密着距離で対峙・回避・反撃 ---
	_ev(33.6, func() -> void:
		var kage := _monster("kage_oni")
		if kage:
			kage.demo_goto(Vector3(-1.5, 0.5, 2.5))
			player.command_face_target(kage)
			AudioKit.sfx(self, "roar_kage", kage.global_position + Vector3(0, 3, 0), -1.0, 0.92)
		player.command_move_to(Vector3(-2, 0.5, 5))
		_dof(true, 16.0))
	_ev(35.0, func() -> void:
		var kage := _monster("kage_oni")
		if kage:
			kage.demo_attack(2.2))
	_ev(35.6, func() -> void:
		player.command_move_to(Vector3(-4.5, 0.5, 4.5), true))  # 間合いを保つ回避
	for atk2 in [36.9, 38.3, 39.7]:
		_ev(atk2, func() -> void:
			player.command_attack()
			var kage := _monster("kage_oni")
			if kage:
				var dir := (kage.global_position - player.global_position)
				dir.y = 0
				kage.hit(28.0, dir.normalized())
			_cam_shake = maxf(_cam_shake, 0.55))
	_ev(35.2, func() -> void:
		_cam_shake = maxf(_cam_shake, 0.45))  # 鬼の振り下ろし
	_ev(38.6, func() -> void:
		var kage := _monster("kage_oni")
		if kage:
			kage.demo_attack(1.8))
	_ev(38.8, func() -> void:
		_cam_shake = maxf(_cam_shake, 0.45))

	# --- 41.5s 増援 (ゲンブ進撃 / スクランブラー滑空) ---
	_ev(41.6, func() -> void:
		var genbu := _monster("genbu")
		if genbu:
			genbu.global_position = Vector3(-24, 0.5, 17)
			genbu.demo_goto(Vector3(-12, 0.5, 9))
			_flash_burst(genbu.global_position + Vector3(0, 1.5, 0), Color(0.2, 1.0, 0.5), 5.0)
			AudioKit.sfx(self, "spawn", genbu.global_position, -3.0, 0.8)
		var scr := _monster("scrambler")
		if scr:
			scr.global_position = Vector3(12, 14, 0)
			scr.demo_goto(Vector3(-18, 8, 8))
		var kage := _monster("kage_oni")
		if kage:
			kage.demo_goto(Vector3(-10, 0.5, -12))
		player.command_face_target(null)
		_dof(false))

	# --- 46s 三倍体トシクイ接近 (60m級) ---
	_ev(46.1, func() -> void:
		var kaiju := _monster("toshikui")
		if kaiju:
			kaiju.global_position = Vector3(0, 0.5, -195)
			kaiju.demo_goto(Vector3(0, 0.5, -120))
			AudioKit.sfx(self, "roar_kaiju", Vector3.INF, -1.0))

	# --- 52s 決意: 巨獣と対峙する構えの主人公 + タイトル ---
	_ev(52.1, func() -> void:
		player.global_position = Vector3(0, 0.6, 8)
		player.has_move_target = false
		player.set_visual_yaw(PI)  # トシクイの方 (-Z) を向く
		player.command_face_target(_monster("toshikui"))
		var pose := player.anim_for("combat_idle")
		if pose == "":
			pose = player.anim_for("idle")
		if pose != "":
			player.command_play(pose, 8.0)
		_hero_lights(Vector3(0, 1.6, 8))
		_dof(true, 9.0))
	_ev(56.5, func() -> void:
		AudioKit.sfx(self, "roar_kaiju", Vector3.INF, -6.0, 0.9))

	_events.sort_custom(func(a, b) -> bool: return a["t"] < b["t"])


# ------------------------------------------------------------------ 演出ヘルパ

## スポーン/衝撃の閃光: 膨張して消える発光球 + ライト
func _flash_burst(pos: Vector3, color: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MatLib.sphere(1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.3
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 12.0
	l.omni_range = size * 3.0
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, 0.55).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "transparency", 1.0, 0.55)
	tw.tween_property(l, "light_energy", 0.0, 0.6)
	tw.chain().tween_callback(func() -> void:
		mi.queue_free()
		l.queue_free())


## ヒーローショット用の簡易2灯 (キー / リム)
func _hero_lights(center: Vector3) -> void:
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.75)
	key.light_energy = 1.6
	key.omni_range = 10.0
	key.position = center + Vector3(2.5, 1.2, -3.0)
	add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.4, 0.7, 1.0)
	rim.light_energy = 2.4
	rim.omni_range = 9.0
	rim.position = center + Vector3(-1.5, 2.2, 3.0)
	add_child(rim)


func _dof(enabled: bool, dist: float = 30.0) -> void:
	if attrs == null:
		return
	attrs.dof_blur_far_enabled = enabled
	attrs.dof_blur_far_distance = dist
	attrs.dof_blur_far_transition = dist * 1.5


# ------------------------------------------------------------------ 進行

var _dbg_next := 0.0


func _process(delta: float) -> void:
	if _finished:
		return
	t += delta
	if OS.is_stdout_verbose() and t >= _dbg_next:
		_dbg_next = t + 1.0
		var anim_name: String = player._anim.current_animation if player._anim else "-"
		print("[dbg] t=%.1f anim=%s spd=%.1f yaw=%.2f pos=%v" % [
			t, anim_name, Vector3(player.velocity.x, 0, player.velocity.z).length(),
			player._visual.rotation.y, player.global_position])
	while _next_event < _events.size() and _events[_next_event]["t"] <= t:
		(_events[_next_event]["fn"] as Callable).call()
		_next_event += 1
	# 巨獣接近中は地響きの微振動
	if t >= 46.0:
		_cam_shake = maxf(_cam_shake, 0.09)
	_update_camera()
	# カメラシェイク (打撃・轟音の衝撃)
	if _cam_shake > 0.004:
		cam.h_offset = randf_range(-1, 1) * _cam_shake * 0.06
		cam.v_offset = randf_range(-1, 1) * _cam_shake * 0.06
		_cam_shake = maxf(_cam_shake - delta * 2.2, 0.0)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	_update_overlay(delta)
	if t >= DURATION + 0.2:
		_finished = true
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
		var center := _last_look
		var node := _target_node(shot["target"])
		if node:
			center = node.global_position + shot["target_off"]
			_last_look = center
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
			if node:
				look = node.global_position + shot["target_off"]
				_last_look = look
			else:
				look = _last_look  # 撃破直後などはその場を見続ける
		else:
			look = (shot["look_from"] as Vector3).lerp(shot["look_to"], e)
			_last_look = look
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

	# 章ラベル (物語の進行を明示)
	_chapter = Label.new()
	_chapter.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_chapter.anchor_left = 0.04
	_chapter.anchor_right = 0.6
	_chapter.anchor_top = 0.865
	_chapter.anchor_bottom = 0.91
	_chapter.add_theme_font_size_override("font_size", 26)
	_chapter.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 0.9))
	_chapter.add_theme_constant_override("outline_size", 6)
	_chapter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	layer.add_child(_chapter)


const CHAPTERS := [
	[0.5, 6.0, "AM 2:47 — 渋谷、いつもの雨"],
	[7.5, 12.5, "空が、裂けた"],
	[13.5, 19.0, "\"それら\" は街に降りた"],
	[20.0, 25.5, "迎え撃つ者、ただひとり"],
	[27.0, 33.0, "一体目、撃破"],
	[34.0, 41.0, "鬼との死闘"],
	[42.0, 51.5, "だが、奴らは止まらない"],
	[52.5, 58.0, "それでも、渋谷を守る"],
]


func _update_overlay(delta: float) -> void:
	# 黒フェード (冒頭/最後) + 白閃光 (裂け目誕生)
	var black_a := 0.0
	if t < 2.0:
		black_a = 1.0 - t / 2.0
	elif t > 58.3:
		black_a = (t - 58.3) / 1.7
	if _white > 0.0:
		_white = maxf(_white - delta * 1.1, 0.0)
	if _white > black_a:
		_fade.color = Color(1, 1, 1, clampf(_white, 0.0, 1.0))
	else:
		_fade.color = Color(0, 0, 0, clampf(black_a, 0.0, 1.0))
	# タイトル
	_title.modulate.a = clampf((t - 54.5) / 1.5, 0.0, 1.0)
	_subtitle.modulate.a = clampf((t - 55.5) / 1.5, 0.0, 1.0)
	# 章ラベル (フェードイン/アウト)
	var ch_alpha := 0.0
	var ch_text := ""
	for ch in CHAPTERS:
		if t >= ch[0] - 0.5 and t <= ch[1] + 0.5:
			ch_text = ch[2]
			ch_alpha = clampf((t - ch[0] + 0.5) / 0.6, 0.0, 1.0) * clampf((ch[1] + 0.5 - t) / 0.6, 0.0, 1.0)
			break
	_chapter.text = ch_text
	_chapter.modulate.a = ch_alpha
