class_name MonsterFactory
extends Object
## 5種のモンスターの造形 (多層プリミティブ彫刻 + 専用シェーダー + 常時エフェクト) と
## 多関節の手続きアニメーション。
##  1. カゲオニ      : 黒曜石の肌にマグマが脈打つ 4m の鬼。装甲・鎖・残り火
##  2. ネオンリッパー : 玉虫色の外殻 + ネオン管が走る高速ラプトル。顎・尾5節・トレイル
##  3. ゲンブ        : ルーンが輝く石造りの巨亀。甲羅の六角板・回転ルーン環・苔
##  4. スクランブラー : 二重リングと軌道球を持つ半透明浮遊体。触手8本×4節
##  5. トシクイ      : 装甲板と炉心を持つ 20m 級怪獣。背ビレ2列・尾3節・火の粉

const SH_OBSIDIAN := "res://shaders/monster_obsidian.gdshader"
const SH_IRIDESCENT := "res://shaders/monster_iridescent.gdshader"
const SH_JELLY := "res://shaders/monster_jelly.gdshader"
const SH_KAIJU := "res://shaders/monster_kaiju.gdshader"

const SPAWNS := {
	"kage_oni": Vector3(-30, 0.5, -22),
	"neon_ripper": Vector3(42, 0.5, 12),
	"genbu": Vector3(-46, 0.5, 38),
	"scrambler": Vector3(14, 11, -20),
	"toshikui": Vector3(40, 0.5, -300),
}


static func create(kind: String) -> MonsterBase:
	match kind:
		"kage_oni":
			return KageOni.new()
		"neon_ripper":
			return NeonRipper.new()
		"genbu":
			return Genbu.new()
		"scrambler":
			return Scrambler.new()
		"toshikui":
			return Toshikui.new()
	return null


static func spawn_all(parent: Node3D) -> Dictionary:
	var out := {}
	for kind in SPAWNS:
		var m := create(kind)
		m.name = kind.to_pascal_case()
		parent.add_child(m)
		m.global_position = SPAWNS[kind]
		out[kind] = m
	print("[Monsters] 5種を配置: ", ", ".join(out.keys()))
	return out


# ================================================================= 1. カゲオニ
class KageOni extends MonsterBase:
	var _sh_l: Node3D
	var _sh_r: Node3D
	var _el_l: Node3D
	var _el_r: Node3D
	var _hip_l: Node3D
	var _hip_r: Node3D
	var _kn_l: Node3D
	var _kn_r: Node3D
	var _head: Node3D
	var _jaw: Node3D
	var _chest: MeshInstance3D
	var _chain: Node3D
	var _core_mat: StandardMaterial3D

	func _init() -> void:
		display_name = "カゲオニ"
		max_hp = 220.0
		move_speed = 3.4
		aggro_range = 32.0
		attack_range = 3.2
		attack_damage = 25.0
		body_radius = 1.1
		body_height = 4.2

	func _build_visual(root: Node3D) -> void:
		var m := shader_mat(SH_OBSIDIAN)
		var eye := MatLib.emissive(Color(1.0, 0.45, 0.1), 9.0)
		var core := MatLib.emissive(Color(1.0, 0.3, 0.05), 5.0)
		var iron := MatLib.metal(Color(0.22, 0.21, 0.23), 0.55)
		var tusk := MatLib.metal(Color(0.85, 0.8, 0.72), 0.6)

		var pelvis := joint(root, "PelvisJ", Vector3(0, 2.05, 0))
		# 腰回りの装甲 (前垂れ + 側面)
		part(pelvis, MatLib.box(Vector3(0.7, 0.55, 0.16)), iron, Vector3(0, -0.25, 0.5), Vector3(12, 0, 0), "LoinFront")
		for side in [-1.0, 1.0]:
			part(pelvis, MatLib.box(Vector3(0.2, 0.5, 0.6)), iron,
					Vector3(side * 0.62, -0.2, 0.1), Vector3(0, 0, side * 14.0), "LoinSide")

		# 胴体: 主胴 + 胸郭 + 肋骨装甲 + 炉心
		part(pelvis, MatLib.capsule(0.62, 1.5), m, Vector3(0, 0.55, 0), Vector3(6, 0, 0), "Torso")
		_chest = part(pelvis, MatLib.sphere(0.68, Vector3(1, 0.85, 1)), m,
				Vector3(0, 1.08, 0.12), Vector3.ZERO, "Chest")
		for i in 3:
			for side in [-1.0, 1.0]:
				part(pelvis, MatLib.box(Vector3(0.5, 0.1, 0.35)), m,
						Vector3(side * 0.35, 0.35 + i * 0.28, 0.42), Vector3(0, side * -12.0, side * -18.0), "Rib%d" % i)
		_core_mat = core
		part(pelvis, MatLib.sphere(0.17), core, Vector3(0, 0.95, 0.62), Vector3.ZERO, "Core")
		for k in 4:
			var ca := TAU * k / 4.0 + 0.4
			part(pelvis, MatLib.box(Vector3(0.16, 0.28, 0.07)), m,
					Vector3(cos(ca) * 0.25, 0.95 + sin(ca) * 0.25, 0.6),
					Vector3(0, 0, rad_to_deg(ca)), "CorePetal")
		# 装甲のリベット (鍛造感)
		var rivet := MatLib.metal(Color(0.55, 0.52, 0.5), 0.4)
		for rv in [Vector3(-0.25, -0.1, 0.56), Vector3(0.25, -0.1, 0.56),
				Vector3(-0.3, -0.42, 0.5), Vector3(0.3, -0.42, 0.5)]:
			part(pelvis, MatLib.sphere(0.035), rivet, rv, Vector3.ZERO, "Rivet")

		# 背中の棘 (5本グラデーション) + 肩甲骨フィン
		for i in 5:
			var s := 0.55 - absf(i - 2.0) * 0.12
			part(pelvis, MatLib.cone(s * 0.28, s), m,
					Vector3(0, 1.45 - i * 0.38, -0.52 - i * 0.05), Vector3(-38, 0, 0), "Spike%d" % i)
		for side in [-1.0, 1.0]:
			part(pelvis, MatLib.box(Vector3(0.1, 0.6, 0.4)), m,
					Vector3(side * 0.45, 1.15, -0.45), Vector3(-20, side * 20.0, 0), "ScapFin")

		# 頭部: 顎 (可動) + 牙 + 角2段 + 王冠角
		_head = joint(pelvis, "HeadJ", Vector3(0, 1.42, 0.38))
		part(_head, MatLib.sphere(0.30, Vector3(1, 0.9, 1)), m, Vector3(0, 0.05, 0.05), Vector3.ZERO, "Skull")
		part(_head, MatLib.box(Vector3(0.5, 0.1, 0.2)), m, Vector3(0, 0.14, 0.22), Vector3(-10, 0, 0), "Brow")
		_jaw = joint(_head, "JawJ", Vector3(0, -0.08, 0.1))
		part(_jaw, MatLib.box(Vector3(0.34, 0.13, 0.32)), m, Vector3(0, -0.05, 0.08), Vector3.ZERO, "Jaw")
		for side in [-1.0, 1.0]:
			part(_jaw, MatLib.cone(0.035, 0.22), tusk,
					Vector3(side * 0.13, 0.08, 0.2), Vector3(8, 0, side * -8.0), "Tusk")
			part(_head, MatLib.sphere(0.05), eye, Vector3(side * 0.13, 0.06, 0.28), Vector3.ZERO, "Eye")
			# 主角 (2段: 根本 + 先端)
			part(_head, MatLib.cone(0.09, 0.4, 0.05), m,
					Vector3(side * 0.18, 0.3, 0.0), Vector3(-12, 0, side * -24.0), "Horn")
			part(_head, MatLib.cone(0.05, 0.3), tusk,
					Vector3(side * 0.28, 0.58, 0.06), Vector3(-8, 0, side * -34.0), "HornTip")
			# 王冠の小角
			part(_head, MatLib.cone(0.04, 0.16), m,
					Vector3(side * 0.1, 0.32, 0.14), Vector3(-25, 0, side * -10.0), "CrownHorn")

		# 腕: 肩+肘の2関節、篭手、拳とナックルスパイク、左腕に鎖枷
		for side in [-1.0, 1.0]:
			var sj := joint(pelvis, "ShoulderJ", Vector3(side * 0.95, 1.0, 0.1))
			part(sj, MatLib.sphere(0.44), m, Vector3.ZERO, Vector3.ZERO, "Pauldron")
			for k in 3:
				part(sj, MatLib.cone(0.06, 0.28), m,
						Vector3(side * (0.18 + k * 0.1), 0.3 - k * 0.12, 0),
						Vector3(0, 0, side * -(20.0 + k * 18.0)), "PauldronSpike")
			part(sj, MatLib.capsule(0.23, 1.0), m, Vector3(side * 0.1, -0.55, 0), Vector3(0, 0, side * -10.0), "UpperArm")
			var ej := joint(sj, "ElbowJ", Vector3(side * 0.18, -1.05, 0))
			part(ej, MatLib.sphere(0.2), m, Vector3.ZERO, Vector3.ZERO, "ElbowBall")
			part(ej, MatLib.capsule(0.19, 1.0), m, Vector3(0, -0.5, 0.06), Vector3(6, 0, 0), "ForeArm")
			part(ej, MatLib.box(Vector3(0.3, 0.4, 0.3)), iron, Vector3(0, -0.45, 0.08), Vector3(4, 0, 0), "Bracer")
			part(ej, MatLib.box(Vector3(0.28, 0.3, 0.28)), iron, Vector3(0, -0.75, 0.1), Vector3(4, 0, 0), "Bracer2")
			# 前腕のマグマ排熱ベント
			for vk in 2:
				part(ej, MatLib.box(Vector3(0.03, 0.22, 0.06)), core,
						Vector3(side * 0.17, -0.42 - vk * 0.3, 0.12), Vector3(4, 0, side * -8.0), "Vent")
			part(ej, MatLib.sphere(0.30), m, Vector3(0, -1.05, 0.12), Vector3.ZERO, "Fist")
			for k in 4:
				part(ej, MatLib.cone(0.035, 0.16), tusk,
						Vector3((k - 1.5) * 0.13, -1.1, 0.38), Vector3(70, 0, 0), "Knuckle")
			if side < 0:
				_sh_l = sj
				_el_l = ej
				# 鎖枷: 手首の環 + 垂れ下がる鎖
				var cuff := TorusMesh.new()
				cuff.inner_radius = 0.2
				cuff.outer_radius = 0.29
				part(ej, cuff, iron, Vector3(0, -0.9, 0.08), Vector3(90, 0, 0), "Cuff")
				_chain = joint(ej, "ChainJ", Vector3(-0.1, -0.95, 0))
				for k in 4:
					var link := TorusMesh.new()
					link.inner_radius = 0.05
					link.outer_radius = 0.1
					part(_chain, link, iron, Vector3(0, -0.12 - k * 0.19, 0),
							Vector3(90, (k % 2) * 90.0, 0), "Link%d" % k)
			else:
				_sh_r = sj
				_el_r = ej

		# 脚: 股+膝の2関節、腿当て・脛当て、足 + 爪先3本 + 踵スパイク
		for side in [-1.0, 1.0]:
			var hj := joint(pelvis, "HipJ", Vector3(side * 0.42, -0.05, 0))
			part(hj, MatLib.capsule(0.28, 0.95), m, Vector3(0, -0.5, 0), Vector3.ZERO, "Thigh")
			part(hj, MatLib.box(Vector3(0.4, 0.6, 0.2)), iron, Vector3(0, -0.45, 0.26), Vector3(8, 0, 0), "ThighGuard")
			var kj := joint(hj, "KneeJ", Vector3(0, -0.95, 0.02))
			part(kj, MatLib.sphere(0.22), m, Vector3.ZERO, Vector3.ZERO, "KneeBall")
			part(kj, MatLib.capsule(0.21, 0.8), m, Vector3(0, -0.42, 0.06), Vector3(-6, 0, 0), "Shin")
			part(kj, MatLib.box(Vector3(0.3, 0.55, 0.14)), iron, Vector3(0, -0.4, 0.26), Vector3(-6, 0, 0), "ShinGuard")
			part(kj, MatLib.box(Vector3(0.45, 0.24, 0.72)), m, Vector3(0, -0.88, 0.16), Vector3.ZERO, "Foot")
			for k in 3:
				part(kj, MatLib.cone(0.06, 0.22), tusk,
						Vector3((k - 1) * 0.15, -0.9, 0.55), Vector3(75, 0, 0), "Toe")
			part(kj, MatLib.cone(0.05, 0.2), m, Vector3(0, -0.82, -0.28), Vector3(-115, 0, 0), "HeelSpike")
			if side < 0:
				_hip_l = hj
				_kn_l = kj
			else:
				_hip_r = hj
				_kn_r = kj

		glow_light(root, Color(1.0, 0.4, 0.08), 2.8, 10.0, Vector3(0, 2.6, 0.6))
		fx_particles(root, Color(1.0, 0.45, 0.1), 40, Vector3(0.9, 1.6, 0.9),
				Vector3(0, 1.2, 0), 0.06, 1.8, Vector3(0, 2.2, 0))

	func _animate(_delta: float, speed01: float) -> void:
		var ph := anim_time * 4.6
		var swing := sin(ph) * 0.55 * speed01
		_hip_l.rotation.x = swing
		_hip_r.rotation.x = -swing
		_kn_l.rotation.x = -maxf(0.0, -sin(ph + 0.5)) * 0.9 * speed01
		_kn_r.rotation.x = -maxf(0.0, sin(ph + 0.5)) * 0.9 * speed01
		if state == State.ATTACK:
			var smash := absf(sin(anim_time * 5.0))
			_sh_l.rotation.x = -2.4 + smash * 2.2
			_sh_r.rotation.x = -2.4 + smash * 2.2
			_el_l.rotation.x = -0.6 + smash * 0.5
			_el_r.rotation.x = -0.6 + smash * 0.5
			_jaw.rotation.x = 0.5
		else:
			_sh_l.rotation.x = -swing * 0.6
			_sh_r.rotation.x = swing * 0.6
			_el_l.rotation.x = -0.35 - maxf(0.0, sin(ph)) * 0.3 * speed01
			_el_r.rotation.x = -0.35 - maxf(0.0, -sin(ph)) * 0.3 * speed01
			_jaw.rotation.x = 0.1 + sin(anim_time * 1.1) * 0.06
		visual.position.y = absf(cos(ph)) * 0.12 * speed01
		visual.rotation.z = sin(ph) * 0.03 * speed01
		_chest.scale = Vector3.ONE * (1.0 + sin(anim_time * 1.5) * 0.03)
		_head.rotation.y = sin(anim_time * 0.5) * 0.3 * (1.0 - speed01)
		_chain.rotation.x = sin(ph * 0.9) * 0.35 * (0.3 + speed01)
		_chain.rotation.z = cos(ph * 0.7) * 0.25 * (0.3 + speed01)
		# 炉心の脈動 (呼吸する熱)
		if _core_mat:
			_core_mat.emission_energy_multiplier = 5.0 + 2.5 * sin(anim_time * 2.6)


# ================================================================= 2. ネオンリッパー
class NeonRipper extends MonsterBase:
	var _tail: Array = []
	var _fins: Array = []
	var _hip_l: Node3D
	var _hip_r: Node3D
	var _an_l: Node3D
	var _an_r: Node3D
	var _neck1: Node3D
	var _neck2: Node3D
	var _jaw: Node3D
	var _body: Node3D

	func _init() -> void:
		display_name = "ネオンリッパー"
		max_hp = 90.0
		move_speed = 8.5
		turn_speed = 8.0
		aggro_range = 30.0
		attack_range = 2.2
		attack_damage = 15.0
		body_radius = 0.7
		body_height = 1.9

	func _build_visual(root: Node3D) -> void:
		var m := shader_mat(SH_IRIDESCENT)
		var carbon := MatLib.leather(Color(0.05, 0.06, 0.08))
		var tube := MatLib.emissive(Color(0.1, 1.0, 0.85), 7.0)
		var eye := MatLib.emissive(Color(0.2, 1.0, 0.9), 10.0)
		var tooth := MatLib.metal(Color(0.9, 0.92, 0.9), 0.25)

		_body = joint(root, "BodyJ", Vector3(0, 1.15, 0))
		part(_body, MatLib.capsule(0.36, 1.7), m, Vector3.ZERO, Vector3(90, 0, 0), "Body")
		part(_body, MatLib.sphere(0.34, Vector3(1, 0.8, 1)), m, Vector3(0, 0.12, 0.55), Vector3.ZERO, "ChestPlate")
		part(_body, MatLib.sphere(0.3, Vector3(1, 0.7, 1)), carbon, Vector3(0, -0.18, 0.1), Vector3.ZERO, "BellyPlate")
		part(_body, MatLib.box(Vector3(0.42, 0.12, 0.5)), m, Vector3(0, 0.28, -0.5), Vector3(8, 0, 0), "HipPlate")
		# 背ビレ列 (5枚) + 背骨のバイオルミネセンス点列
		for i in 5:
			var s := 0.3 - absf(i - 2.0) * 0.055
			var fin := part(_body, MatLib.box(Vector3(0.03, s, s * 1.3)), m,
					Vector3(0, 0.36, 0.5 - i * 0.32), Vector3(-15, 0, 0), "Fin%d" % i)
			_fins.append(fin)
		for i in 6:
			part(_body, MatLib.sphere(0.035), tube,
					Vector3(0, 0.34, 0.62 - i * 0.28), Vector3.ZERO, "GlowDot%d" % i)
		# 尻のスラスター (疾走の推進器)
		for side_t in [-1.0, 1.0]:
			part(_body, MatLib.cone(0.07, 0.16, 0.05), MatLib.metal(Color(0.35, 0.37, 0.4), 0.4),
					Vector3(side_t * 0.2, 0.18, -0.85), Vector3(70, 0, 0), "ThrusterHousing")
			part(_body, MatLib.sphere(0.05), tube,
					Vector3(side_t * 0.2, 0.14, -0.92), Vector3.ZERO, "ThrusterGlow")
		# フランクのネオン管 (左右各2本)
		for side in [-1.0, 1.0]:
			part(_body, MatLib.box(Vector3(0.03, 0.03, 1.4)), tube,
					Vector3(side * 0.34, 0.1, -0.05), Vector3(0, 0, 0), "TubeUp")
			part(_body, MatLib.box(Vector3(0.03, 0.03, 1.1)), tube,
					Vector3(side * 0.3, -0.12, -0.1), Vector3(0, side * 4.0, 0), "TubeLow")

		# 首2節 + 頭 (可動顎 + 歯列 + クレスト + 頬フィン)
		_neck1 = joint(_body, "NeckJ1", Vector3(0, 0.1, 0.78))
		part(_neck1, MatLib.capsule(0.16, 0.5), m, Vector3(0, 0.12, 0.12), Vector3(38, 0, 0), "Neck1")
		_neck2 = joint(_neck1, "NeckJ2", Vector3(0, 0.26, 0.26))
		part(_neck2, MatLib.capsule(0.13, 0.4), m, Vector3(0, 0.1, 0.1), Vector3(30, 0, 0), "Neck2")
		for side_f in [-1.0, 1.0]:
			part(_neck2, MatLib.box(Vector3(0.02, 0.16, 0.22)), m,
					Vector3(side_f * 0.12, 0.12, 0.02), Vector3(-20, side_f * -30.0, side_f * 20.0), "NeckFrill")
		var head := joint(_neck2, "HeadJ", Vector3(0, 0.22, 0.24))
		part(head, MatLib.box(Vector3(0.24, 0.2, 0.42)), m, Vector3(0, 0.02, 0.12), Vector3.ZERO, "Skull")
		part(head, MatLib.box(Vector3(0.17, 0.14, 0.34)), m, Vector3(0, 0.0, 0.42), Vector3.ZERO, "Snout")
		part(head, MatLib.cone(0.05, 0.35, 0.01), m, Vector3(0, 0.2, -0.02), Vector3(40, 0, 0), "Crest")
		part(head, MatLib.cone(0.035, 0.25, 0.01), m, Vector3(0, 0.24, -0.16), Vector3(60, 0, 0), "Crest2")
		_jaw = joint(head, "JawJ", Vector3(0, -0.1, 0.14))
		part(_jaw, MatLib.box(Vector3(0.15, 0.06, 0.42)), m, Vector3(0, -0.03, 0.2), Vector3(4, 0, 0), "Jaw")
		for side in [-1.0, 1.0]:
			part(head, MatLib.sphere(0.045), eye, Vector3(side * 0.1, 0.07, 0.24), Vector3.ZERO, "Eye")
			part(head, MatLib.box(Vector3(0.02, 0.12, 0.16)), m,
					Vector3(side * 0.14, -0.02, 0.02), Vector3(0, side * -25.0, side * 30.0), "CheekFin")
			for i in 4:
				part(head, MatLib.cone(0.013, 0.06), tooth,
						Vector3(side * 0.06, -0.08, 0.28 + i * 0.09), Vector3(180, 0, 0), "ToothU")
			for i in 3:
				part(_jaw, MatLib.cone(0.011, 0.05), tooth,
						Vector3(side * 0.05, 0.02, 0.16 + i * 0.1), Vector3.ZERO, "ToothL")
			# 小さな前肢 (2節 + 鉤爪2本)
			var aj := joint(_body, "ArmJ", Vector3(side * 0.3, -0.05, 0.5))
			part(aj, MatLib.capsule(0.06, 0.3), m, Vector3(0, -0.12, 0.05), Vector3(-30, 0, 0), "ArmU")
			var wj := joint(aj, "WristJ", Vector3(0, -0.24, 0.12))
			part(wj, MatLib.capsule(0.045, 0.22), m, Vector3(0, -0.08, 0.05), Vector3(-50, 0, 0), "ArmL")
			for k in 2:
				part(wj, MatLib.cone(0.02, 0.11), tooth,
						Vector3((k - 0.5) * 0.06, -0.18, 0.14), Vector3(150, 0, 0), "Claw")

		# 尾5節 (各節にフィンブレード)
		var t_parent: Node3D = _body
		var offset := Vector3(0, 0, -0.95)
		for i in 5:
			var radius := 0.22 - i * 0.038
			var length := 0.62 - i * 0.06
			var tj := joint(t_parent, "TailJ%d" % i, offset)
			part(tj, MatLib.cone(radius, length, radius * 0.55), m,
					Vector3(0, 0, -length * 0.4), Vector3(-90, 0, 0), "Tail")
			part(tj, MatLib.box(Vector3(0.02, 0.14 - i * 0.02, 0.2)), m,
					Vector3(0, radius + 0.04, -length * 0.35), Vector3(-20, 0, 0), "TailFin")
			if i >= 3:
				part(tj, MatLib.box(Vector3(0.02, 0.02, length * 0.8)), tube,
						Vector3(0, 0, -length * 0.4), Vector3.ZERO, "TailTube")
			_tail.append(tj)
			t_parent = tj
			offset = Vector3(0, 0, -length * 0.85)

		# 後肢: 股+膝+踵の3関節、腿プレート、鎌爪
		for side in [-1.0, 1.0]:
			var hj := joint(_body, "HipJ", Vector3(side * 0.32, -0.08, -0.3))
			part(hj, MatLib.capsule(0.17, 0.55), m, Vector3(0, -0.22, 0.06), Vector3(14, 0, 0), "Thigh")
			part(hj, MatLib.box(Vector3(0.06, 0.4, 0.3)), carbon, Vector3(side * 0.14, -0.2, 0.05), Vector3(12, 0, 0), "ThighPlate")
			var kj := joint(hj, "KneeJ", Vector3(0, -0.46, 0.14))
			part(kj, MatLib.capsule(0.1, 0.5), m, Vector3(0, -0.2, -0.08), Vector3(-28, 0, 0), "Shin")
			var an := joint(kj, "AnkleJ", Vector3(0, -0.42, -0.2))
			part(an, MatLib.capsule(0.07, 0.3), m, Vector3(0, -0.1, 0.07), Vector3(30, 0, 0), "Metatarsal")
			part(an, MatLib.box(Vector3(0.13, 0.05, 0.32)), m, Vector3(0, -0.22, 0.12), Vector3.ZERO, "Foot")
			for k in 3:
				part(an, MatLib.cone(0.02, 0.12), tooth,
						Vector3((k - 1) * 0.06, -0.23, 0.32), Vector3(100, 0, 0), "ToeClaw")
			part(an, MatLib.cone(0.035, 0.2), tooth,
					Vector3(side * 0.08, -0.12, 0.1), Vector3(140, 0, side * 15.0), "SickleClaw")
			if side < 0:
				_hip_l = hj
				_an_l = an
			else:
				_hip_r = hj
				_an_r = an

		glow_light(root, Color(0.15, 0.9, 0.8), 2.2, 8.0, Vector3(0, 1.2, 0))
		fx_particles(root, Color(0.15, 1.0, 0.85), 30, Vector3(0.3, 0.3, 1.2),
				Vector3(0, 0.3, -1.5), 0.05, 0.8, Vector3(0, 1.0, -0.8))

	func _animate(_delta: float, speed01: float) -> void:
		var ph := anim_time * 9.0
		var swing := sin(ph) * 0.9 * speed01
		_hip_l.rotation.x = swing + 0.1
		_hip_r.rotation.x = -swing + 0.1
		_an_l.rotation.x = maxf(0.0, -sin(ph - 0.4)) * 0.7 * speed01
		_an_r.rotation.x = maxf(0.0, sin(ph - 0.4)) * 0.7 * speed01
		for i in _tail.size():
			var t: Node3D = _tail[i]
			t.rotation.y = sin(anim_time * 3.2 - i * 0.8) * (0.14 + 0.08 * i) * (0.4 + speed01)
			t.rotation.x = sin(anim_time * 2.1 - i * 0.6) * 0.06
		for i in _fins.size():
			(_fins[i] as Node3D).rotation.x = deg_to_rad(-15) + sin(anim_time * 2.5 - i * 0.5) * 0.1
		_body.rotation.x = -0.06 * speed01 + sin(ph * 2.0) * 0.02 * speed01
		_body.position.y = 1.15 + absf(cos(ph)) * 0.1 * speed01
		_neck1.rotation.x = sin(ph) * 0.06 * speed01
		_neck2.rotation.x = sin(ph + 0.5) * 0.08 * speed01 + (0.3 if state == State.ATTACK else 0.0)
		_neck2.rotation.y = sin(anim_time * 0.9) * 0.2 * (1.0 - speed01)
		_jaw.rotation.x = (0.55 + sin(anim_time * 8.0) * 0.15) if state == State.ATTACK \
				else 0.06 + sin(anim_time * 1.3) * 0.04


# ================================================================= 3. ゲンブ
class Genbu extends MonsterBase:
	var _legs: Array = []
	var _ankles: Array = []
	var _neck: Node3D
	var _head: Node3D
	var _jaw: Node3D
	var _shell: MeshInstance3D
	var _rune_ring: MeshInstance3D
	var _tail1: Node3D
	var _tail2: Node3D

	func _init() -> void:
		display_name = "ゲンブ"
		max_hp = 420.0
		move_speed = 1.7
		turn_speed = 2.2
		aggro_range = 22.0
		attack_range = 3.6
		attack_damage = 32.0
		body_radius = 1.7
		body_height = 2.6

	func _build_visual(root: Node3D) -> void:
		var m := shader_mat(SH_OBSIDIAN, {
			"rock_color": Color(0.14, 0.15, 0.13),
			"magma_color": Color(0.15, 0.9, 0.5),
			"magma_emission": 3.0,
			"crack_scale": 1.3,
		})
		var dark := MatLib.concrete_fallback()
		dark.albedo_color = Color(0.2, 0.21, 0.19)
		var moss := MatLib.fabric(Color(0.16, 0.34, 0.12), 1.0)
		var rune := MatLib.emissive(Color(0.3, 1.0, 0.55), 4.5)
		var eye := MatLib.emissive(Color(0.3, 1.0, 0.5), 8.0)

		var base := joint(root, "BaseJ", Vector3(0, 1.35, 0))
		_shell = part(base, MatLib.sphere(1.95, Vector3(1, 0.6, 1)), m,
				Vector3(0, 0.35, 0), Vector3.ZERO, "Shell")
		# 甲羅の六角板 (2周 + 頂部)
		for ring_i in 2:
			var count := 6 if ring_i == 0 else 8
			var lat := 0.9 - ring_i * 0.42
			for k in count:
				var a := TAU * k / count + ring_i * 0.3
				var r := cos(asin(lat * 0.9)) * 1.85
				var pos := Vector3(cos(a) * r, 0.35 + lat * 1.05, sin(a) * r)
				var plate := part(base, MatLib.box(Vector3(0.75 - ring_i * 0.1, 0.14, 0.65 - ring_i * 0.1)), dark,
						pos, Vector3.ZERO, "HexPlate")
				plate.look_at_from_position(plate.position, plate.position * 2.0, Vector3.UP)
				plate.rotate_object_local(Vector3.RIGHT, PI / 2)
		part(base, MatLib.box(Vector3(0.8, 0.16, 0.8)), dark, Vector3(0, 1.52, 0), Vector3(0, 22, 0), "TopPlate")
		# 頂部クリスタル + 回転ルーン環
		part(base, MatLib.cone(0.16, 0.65, 0.02), rune, Vector3(0, 1.95, 0), Vector3.ZERO, "Crystal")
		var ring := TorusMesh.new()
		ring.inner_radius = 1.0
		ring.outer_radius = 1.06
		_rune_ring = part(base, ring, rune, Vector3(0, 1.55, 0), Vector3.ZERO, "RuneRing")
		# 縁 + 縁スパイク + 苔
		var rim := TorusMesh.new()
		rim.inner_radius = 1.55
		rim.outer_radius = 2.05
		var rim_mi := part(base, rim, m, Vector3(0, -0.05, 0), Vector3.ZERO, "ShellRim")
		rim_mi.scale = Vector3(1, 0.55, 1)
		for i in 8:
			var a := TAU * i / 8.0 + 0.2
			part(base, MatLib.cone(0.14, 0.45), m,
					Vector3(cos(a) * 1.95, -0.02, sin(a) * 1.95),
					Vector3(0, 0, rad_to_deg(-a) + 90.0), "RimSpike")
		for i in 5:
			var a := TAU * i / 5.0 + 0.7
			var mp := part(base, MatLib.sphere(0.4, Vector3(1, 0.25, 1)), moss,
					Vector3(cos(a) * 1.2, 0.75 + sin(a * 2.0) * 0.25, sin(a) * 1.2), Vector3.ZERO, "Moss")
			mp.scale = Vector3(1.0, 0.5, 0.8)
		# 縁から垂れる苔蔓 + 甲羅のルーン刻印板
		for i in 3:
			var av := TAU * i / 3.0 + 0.4
			part(base, MatLib.cone(0.06, 0.7, 0.01), moss,
					Vector3(cos(av) * 1.85, -0.4, sin(av) * 1.85), Vector3(180, 0, 0), "Vine")
		for i in 4:
			var ar := TAU * i / 4.0 + 0.9
			var glyph := part(base, MatLib.box(Vector3(0.28, 0.2, 0.04)), rune,
					Vector3(cos(ar) * 1.6, 0.55, sin(ar) * 1.6), Vector3.ZERO, "Glyph")
			glyph.rotation.y = atan2(cos(ar), sin(ar))  # 刻印面を外向きに
		part(base, MatLib.sphere(1.35, Vector3(1, 0.55, 1)), dark, Vector3(0, -0.55, 0), Vector3.ZERO, "Belly")

		# 首2節 + 頭 (可動顎 + 嘴 + 角 + 頬ヒゲ石)
		_neck = joint(base, "NeckJ", Vector3(0, -0.25, 1.7))
		part(_neck, MatLib.capsule(0.3, 0.9), m, Vector3(0, 0.1, 0.2), Vector3(70, 0, 0), "NeckM")
		_head = joint(_neck, "HeadJ", Vector3(0, 0.28, 0.75))
		part(_head, MatLib.sphere(0.42, Vector3(1, 0.85, 1.15)), m, Vector3(0, 0.08, 0.1), Vector3.ZERO, "Skull")
		part(_head, MatLib.box(Vector3(0.5, 0.12, 0.3)), m, Vector3(0, 0.32, 0.15), Vector3(-8, 0, 0), "BrowPlate")
		part(_head, MatLib.cone(0.1, 0.28, 0.02), m, Vector3(0, 0.12, 0.52), Vector3(75, 0, 0), "Beak")
		_jaw = joint(_head, "JawJ", Vector3(0, -0.12, 0.2))
		part(_jaw, MatLib.box(Vector3(0.3, 0.1, 0.34)), m, Vector3(0, -0.04, 0.12), Vector3.ZERO, "Jaw")
		for side in [-1.0, 1.0]:
			part(_head, MatLib.sphere(0.06), eye, Vector3(side * 0.18, 0.18, 0.38), Vector3.ZERO, "Eye")
			part(_head, MatLib.cone(0.05, 0.25), m,
					Vector3(side * 0.22, 0.42, -0.05), Vector3(-30, 0, side * -30.0), "HeadHorn")
			part(_head, MatLib.cone(0.03, 0.2), dark,
					Vector3(side * 0.3, -0.05, 0.3), Vector3(120, 0, side * 40.0), "Whisker")

		# 尾2節
		_tail1 = joint(base, "TailJ1", Vector3(0, -0.45, -1.9))
		part(_tail1, MatLib.cone(0.18, 0.7, 0.08), m, Vector3(0, -0.1, -0.3), Vector3(-105, 0, 0), "Tail1")
		_tail2 = joint(_tail1, "TailJ2", Vector3(0, -0.2, -0.6))
		part(_tail2, MatLib.cone(0.08, 0.5, 0.01), m, Vector3(0, -0.05, -0.2), Vector3(-100, 0, 0), "Tail2")

		# 脚4本: 2関節 (柱 + 足首) + 足 + 爪先3本
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var lj := joint(root, "LegJ", Vector3(sx * 1.25, 1.0, sz * 0.95))
				part(lj, MatLib.cone(0.3, 0.7, 0.38), m, Vector3(0, -0.3, 0), Vector3.ZERO, "LegUpper")
				var aj := joint(lj, "AnkleJ", Vector3(0, -0.62, 0))
				part(aj, MatLib.cone(0.34, 0.45, 0.3), dark, Vector3(0, -0.2, 0), Vector3.ZERO, "LegLower")
				part(aj, MatLib.sphere(0.42, Vector3(1, 0.32, 1)), m, Vector3(0, -0.42, 0.05), Vector3.ZERO, "Foot")
				for k in 3:
					part(aj, MatLib.cone(0.06, 0.2), dark,
							Vector3((k - 1) * 0.2 * sx, -0.45, 0.38), Vector3(80, 0, 0), "Toe")
				_legs.append(lj)
				_ankles.append(aj)

		glow_light(root, Color(0.2, 1.0, 0.5), 2.2, 11.0, Vector3(0, 1.6, 0))
		fx_particles(root, Color(0.3, 1.0, 0.55), 24, Vector3(1.6, 0.8, 1.6),
				Vector3(0, 0.5, 0), 0.055, 2.5, Vector3(0, 1.4, 0))

	func _animate(delta: float, speed01: float) -> void:
		var ph := anim_time * 2.2
		for i in _legs.size():
			var phase: float = ph + (PI if i in [1, 2] else 0.0)
			var lift := maxf(0.0, sin(phase)) * speed01
			(_legs[i] as Node3D).position.y = 1.0 + lift * 0.22
			(_ankles[i] as Node3D).rotation.x = lift * 0.3
		_shell.scale = Vector3.ONE * (1.0 + sin(anim_time * 0.9) * 0.008)
		_rune_ring.rotation.y += delta * 0.5
		_rune_ring.position.y = 1.55 + sin(anim_time * 1.2) * 0.05
		_neck.rotation.y = sin(anim_time * 0.7) * 0.3
		_head.rotation.x = (0.25 if state == State.ATTACK else sin(anim_time * 1.1) * 0.07)
		_jaw.rotation.x = (0.5 + sin(anim_time * 6.0) * 0.1) if state == State.ATTACK \
				else 0.05 + sin(anim_time * 0.8) * 0.04
		_tail1.rotation.y = sin(anim_time * 0.9) * 0.2
		_tail2.rotation.y = sin(anim_time * 0.9 - 0.7) * 0.3


# ================================================================= 4. スクランブラー
class Scrambler extends MonsterBase:
	var _tentacles: Array = []
	var _core: MeshInstance3D
	var _cage: Array = []
	var _ring1: MeshInstance3D
	var _ring2: MeshInstance3D
	var _orb_pivot: Node3D
	var _skirt: MeshInstance3D

	func _init() -> void:
		display_name = "スクランブラー"
		max_hp = 70.0
		move_speed = 5.0
		aggro_range = 38.0
		attack_range = 3.0
		attack_damage = 10.0
		body_radius = 1.0
		body_height = 2.0
		flying = true
		hover_height = 11.0

	func _build_visual(root: Node3D) -> void:
		var shell := shader_mat(SH_JELLY)
		var chrome := MatLib.metal(Color(0.6, 0.65, 0.75), 0.15)
		var center := joint(root, "CenterJ", Vector3(0, 1.0, 0))
		part(center, MatLib.sphere(0.95, Vector3(1, 1.1, 1)), shell, Vector3.ZERO, Vector3.ZERO, "Shell")
		_core = part(center, MatLib.sphere(0.42), MatLib.emissive(Color(1.0, 0.25, 0.7), 6.0),
				Vector3.ZERO, Vector3.ZERO, "Core")
		# コアを囲む4本の湾曲ケージ
		for k in 4:
			var a := TAU * k / 4.0
			var strip := part(center, MatLib.box(Vector3(0.06, 1.0, 0.02)), chrome,
					Vector3(cos(a) * 0.55, 0, sin(a) * 0.55),
					Vector3(0, rad_to_deg(-a), 0), "Cage%d" % k)
			_cage.append(strip)
		# 二重リング (逆回転)
		var r1 := TorusMesh.new()
		r1.inner_radius = 1.0
		r1.outer_radius = 1.16
		_ring1 = part(center, r1, chrome, Vector3.ZERO, Vector3(12, 0, 0), "Ring1")
		var r2 := TorusMesh.new()
		r2.inner_radius = 1.25
		r2.outer_radius = 1.33
		_ring2 = part(center, r2, MatLib.emissive(Color(0.4, 0.8, 1.0), 2.5),
				Vector3.ZERO, Vector3(-18, 0, 30), "Ring2")
		# 軌道球3つ
		_orb_pivot = joint(center, "OrbPivot", Vector3.ZERO)
		for k in 3:
			var a := TAU * k / 3.0
			part(_orb_pivot, MatLib.sphere(0.09), MatLib.emissive(Color(1.0, 0.5, 0.8), 6.0),
					Vector3(cos(a) * 1.5, sin(a * 2.0) * 0.2, sin(a) * 1.5), Vector3.ZERO, "Orb%d" % k)
		# 上部アンテナフィン + 天冠ヘイロー + 殻フィン4枚 + 膜スカート
		part(center, MatLib.cone(0.06, 0.6, 0.01), chrome, Vector3(0, 1.25, 0), Vector3.ZERO, "Antenna")
		part(center, MatLib.sphere(0.05), MatLib.emissive(Color(1.0, 0.3, 0.6), 8.0),
				Vector3(0, 1.55, 0), Vector3.ZERO, "AntennaTip")
		var halo := TorusMesh.new()
		halo.inner_radius = 0.32
		halo.outer_radius = 0.38
		part(center, halo, MatLib.emissive(Color(0.6, 0.85, 1.0), 3.5),
				Vector3(0, 1.42, 0), Vector3.ZERO, "Halo")
		for i in 4:
			var af := TAU * i / 4.0 + 0.5
			part(center, MatLib.box(Vector3(0.03, 0.5, 0.28)), shell,
					Vector3(cos(af) * 0.82, 0.55, sin(af) * 0.82),
					Vector3(0, rad_to_deg(-af) + 90.0, 20), "ShellFin%d" % i)
		_skirt = part(center, MatLib.cone(0.95, 0.7, 0.55), shell, Vector3(0, -0.75, 0), Vector3.ZERO, "Skirt")

		# 触手8本 × 4節 + 先端クロー
		for i in 8:
			var a := TAU * i / 8.0
			var tj := joint(center, "TentJ%d" % i, Vector3(cos(a) * 0.6, -0.75, sin(a) * 0.6))
			var seg_parent: Node3D = tj
			for s in 4:
				var radius := 0.05 - s * 0.01
				var length := 0.45 - s * 0.05
				part(seg_parent, MatLib.capsule(radius, length), shell, Vector3(0, -length * 0.5, 0),
						Vector3.ZERO, "Seg")
				var nj := joint(seg_parent, "SegJ", Vector3(0, -length, 0))
				seg_parent = nj
			part(seg_parent, MatLib.cone(0.035, 0.14), chrome, Vector3(0, -0.05, 0), Vector3(180, 0, 0), "TipClaw")
			part(seg_parent, MatLib.sphere(0.045), MatLib.emissive(Color(0.4, 0.8, 1.0), 5.0),
					Vector3(0, -0.16, 0), Vector3.ZERO, "Tip")
			_tentacles.append(tj)

		glow_light(root, Color(1.0, 0.3, 0.7), 3.2, 15.0, Vector3(0, 1.0, 0))
		fx_particles(root, Color(0.5, 0.8, 1.0), 26, Vector3(0.8, 0.4, 0.8),
				Vector3(0, -1.0, 0), 0.045, 2.2, Vector3(0, 0.2, 0))

	func _animate(delta: float, _speed01: float) -> void:
		_ring1.rotation.y += delta * 0.9
		_ring2.rotation.y -= delta * 0.6
		_orb_pivot.rotation.y += delta * 1.4
		_core.scale = Vector3.ONE * (1.0 + sin(anim_time * 2.4) * 0.12)
		_skirt.scale = Vector3(1.0 + sin(anim_time * 1.8) * 0.08, 1.0, 1.0 + cos(anim_time * 1.8) * 0.08)
		for k in _cage.size():
			(_cage[k] as Node3D).rotation.x = sin(anim_time * 1.5 + k) * 0.12
		visual.rotation.y += delta * 0.25
		for i in _tentacles.size():
			var t: Node3D = _tentacles[i]
			var ph := anim_time * 2.0 + i * 0.79
			t.rotation.x = sin(ph) * 0.28
			t.rotation.z = cos(ph * 0.8) * 0.28
			var seg: Node3D = t
			var depth := 0
			while seg.get_child_count() > 0 and depth < 4:
				var next: Node3D = null
				for c in seg.get_children():
					if c.name.begins_with("SegJ"):
						next = c
						break
				if next == null:
					break
				next.rotation.x = sin(ph - (depth + 1) * 0.6) * 0.3
				next.rotation.z = cos(ph * 0.8 - (depth + 1) * 0.5) * 0.15
				seg = next
				depth += 1


# ================================================================= 5. トシクイ
class Toshikui extends MonsterBase:
	var _hip_l: Node3D
	var _hip_r: Node3D
	var _kn_l: Node3D
	var _kn_r: Node3D
	var _arm_l: Node3D
	var _arm_r: Node3D
	var _el_l: Node3D
	var _el_r: Node3D
	var _head: Node3D
	var _jaw: Node3D
	var _torso: Node3D
	var _tails: Array = []

	const GIANT_SCALE := 3.0  # 三倍体: 約60mの超巨大種

	func _init() -> void:
		display_name = "トシクイ"
		max_hp = 6000.0
		move_speed = 2.4
		turn_speed = 0.5
		aggro_range = 0.0   # プレイヤーを追わない超大型のセットピース
		attack_range = 20.0
		attack_damage = 50.0
		body_radius = 13.0
		body_height = 62.0

	func _build_visual(root: Node3D) -> void:
		root.scale = Vector3.ONE * GIANT_SCALE
		var m := shader_mat(SH_KAIJU)
		var plate := MatLib.concrete_fallback()
		plate.albedo_color = Color(0.13, 0.14, 0.16)
		plate.roughness = 0.7
		var spine_mat := MatLib.emissive(Color(1.0, 0.12, 0.3), 3.5)
		var furnace := MatLib.emissive(Color(1.0, 0.25, 0.1), 4.5)
		var eye := MatLib.emissive(Color(1.0, 0.15, 0.15), 14.0)
		var bone := MatLib.metal(Color(0.75, 0.72, 0.66), 0.65)

		var pelvis := joint(root, "PelvisJ", Vector3(0, 10.0, 0))
		part(pelvis, MatLib.box(Vector3(5.2, 2.2, 4.4)), plate, Vector3(0, -0.4, 0), Vector3.ZERO, "PelvisPlate")
		_torso = joint(pelvis, "TorsoJ", Vector3.ZERO)
		part(_torso, MatLib.capsule(3.3, 8.0), m, Vector3(0, 3.0, 0), Vector3(7, 0, 0), "Torso")
		part(_torso, MatLib.sphere(3.5, Vector3(1, 0.9, 1)), m, Vector3(0, 6.6, 0.6), Vector3.ZERO, "Chest")
		# 前面の装甲板 (4段) + 炉心 + 炉格子
		for i in 4:
			part(_torso, MatLib.box(Vector3(3.6 - i * 0.35, 1.15, 0.7)), plate,
					Vector3(0, 1.2 + i * 1.45, 2.6 + i * 0.16), Vector3(-6 - i * 2.0, 0, 0), "ArmorFront%d" % i)
		part(_torso, MatLib.box(Vector3(1.7, 2.2, 0.5)), furnace, Vector3(0, 6.2, 3.05), Vector3(-12, 0, 0), "FurnaceCore")
		for i in 3:
			part(_torso, MatLib.box(Vector3(1.9, 0.22, 0.6)), plate,
					Vector3(0, 5.5 + i * 0.75, 3.15), Vector3(-12, 0, 0), "FurnaceBar%d" % i)
		# 側面装甲
		for side in [-1.0, 1.0]:
			for i in 3:
				part(_torso, MatLib.box(Vector3(0.6, 1.6, 3.2 - i * 0.4)), plate,
						Vector3(side * (3.1 - i * 0.15), 1.5 + i * 1.8, 0), Vector3(0, 0, side * -6.0), "ArmorSide")

		# 頭部: 顎可動 + 歯 + 角6本 + 首ガード
		_head = joint(_torso, "HeadJ", Vector3(0, 9.2, 1.4))
		part(_head, MatLib.box(Vector3(2.2, 1.8, 3.4)), m, Vector3(0, 0.4, 0.8), Vector3.ZERO, "Skull")
		part(_head, MatLib.box(Vector3(2.4, 0.5, 1.6)), plate, Vector3(0, 1.35, 0.6), Vector3(-10, 0, 0), "BrowPlate")
		_jaw = joint(_head, "JawJ", Vector3(0, -0.5, 0.6))
		part(_jaw, MatLib.box(Vector3(1.9, 0.7, 2.6)), m, Vector3(0, -0.25, 0.5), Vector3(4, 0, 0), "Jaw")
		for side in [-1.0, 1.0]:
			part(_head, MatLib.sphere(0.28), eye, Vector3(side * 0.85, 0.7, 2.2), Vector3.ZERO, "Eye")
			part(_head, MatLib.sphere(0.14), eye, Vector3(side * 1.05, 1.0, 1.7), Vector3.ZERO, "Eye2")
			part(_head, MatLib.cone(0.35, 1.8), m, Vector3(side * 0.9, 1.7, -0.4),
					Vector3(-20, 0, side * -28.0), "Horn")
			part(_head, MatLib.cone(0.2, 1.1), m, Vector3(side * 1.15, 1.2, 0.4),
					Vector3(10, 0, side * -55.0), "Horn2")
			part(_head, MatLib.cone(0.14, 0.8), m, Vector3(side * 0.5, 1.6, 0.6),
					Vector3(-40, 0, side * -12.0), "Horn3")
			for i in 4:
				part(_head, MatLib.cone(0.09, 0.5), bone,
						Vector3(side * 0.75, -0.15, 0.6 + i * 0.55), Vector3(180, 0, 0), "ToothU%d" % i)
			for i in 3:
				part(_jaw, MatLib.cone(0.08, 0.45), bone,
						Vector3(side * 0.7, 0.2, 0.5 + i * 0.6), Vector3.ZERO, "ToothL%d" % i)
		part(_torso, MatLib.cone(1.6, 1.4, 2.0), plate, Vector3(0, 8.4, 0.8), Vector3.ZERO, "NeckGuard")

		# 背ビレ2列 (主列7枚 + 副列6枚)
		for i in 7:
			var s := 2.4 - absf(i - 3.0) * 0.45
			part(_torso, MatLib.cone(s * 0.28, s), spine_mat,
					Vector3(0, 8.0 - i * 1.55, -2.4 - i * 0.22), Vector3(-32, 0, 0), "Fin%d" % i)
		for i in 6:
			var s2 := 1.2 - absf(i - 2.5) * 0.2
			for side in [-1.0, 1.0]:
				part(_torso, MatLib.cone(s2 * 0.22, s2), m,
						Vector3(side * 1.1, 7.4 - i * 1.5, -2.2 - i * 0.2), Vector3(-30, 0, side * -18.0), "FinSub")

		# 尾3節 (側面スパイク付き)
		var t_parent: Node3D = pelvis
		var t_off := Vector3(0, -0.5, -3.0)
		for i in 3:
			var tj := joint(t_parent, "TailJ%d" % i, t_off)
			var radius := 2.0 - i * 0.6
			var length := 4.5 - i * 0.8
			part(tj, MatLib.cone(radius, length, radius * 0.5), m,
					Vector3(0, -0.3, -length * 0.4), Vector3(-100, 0, 0), "Tail%d" % i)
			for side in [-1.0, 1.0]:
				part(tj, MatLib.cone(0.25 - i * 0.05, 1.1 - i * 0.25), m,
						Vector3(side * radius * 0.7, 0, -length * 0.4),
						Vector3(0, 0, side * -75.0), "TailSpike")
			_tails.append(tj)
			t_parent = tj
			t_off = Vector3(0, -0.4, -length * 0.85)

		# 腕: 肩パウルドロン2段 + 2関節 + 3本爪
		# 肩の排煙塔 (稼働する火の粉と連動)
		for side_s in [-1.0, 1.0]:
			part(_torso, MatLib.cone(0.5, 2.4, 0.42), plate,
					Vector3(side_s * 2.4, 8.6, -1.2), Vector3(side_s * -8.0, 0, side_s * 12.0), "Stack")
			part(_torso, MatLib.sphere(0.4, Vector3(1, 0.4, 1)), spine_mat,
					Vector3(side_s * 2.65, 9.8, -1.45), Vector3.ZERO, "StackGlow")
		for side in [-1.0, 1.0]:
			var aj := joint(_torso, "ArmJ", Vector3(side * 3.6, 6.4, 0.5))
			part(aj, MatLib.sphere(1.3, Vector3(1, 0.8, 1)), plate, Vector3(side * 0.2, 0.5, 0), Vector3.ZERO, "Pauldron")
			part(aj, MatLib.box(Vector3(1.8, 0.5, 2.2)), plate, Vector3(side * 0.3, 1.1, 0), Vector3(0, 0, side * -12.0), "PauldronTop")
			part(aj, MatLib.capsule(1.0, 3.6), m, Vector3(side * 0.3, -1.8, 0), Vector3(0, 0, side * -8.0), "ArmU")
			for sk in 3:
				part(aj, MatLib.cone(0.18, 0.8), bone,
						Vector3(side * (0.9 + sk * 0.1), -0.8 - sk * 0.9, -0.3),
						Vector3(0, 0, side * -70.0), "ArmSpike")
			var ej := joint(aj, "ElbowJ", Vector3(side * 0.55, -3.6, 0))
			part(ej, MatLib.capsule(0.8, 3.2), m, Vector3(0, -1.5, 0.3), Vector3(10, 0, 0), "ArmL")
			part(ej, MatLib.sphere(1.05), m, Vector3(0, -3.2, 0.6), Vector3.ZERO, "Hand")
			for k in 3:
				part(ej, MatLib.cone(0.22, 1.3), bone,
						Vector3((k - 1) * 0.6, -3.9, 0.9), Vector3(150, 0, 0), "Finger%d" % k)
			if side < 0:
				_arm_l = aj
				_el_l = ej
			else:
				_arm_r = aj
				_el_r = ej

		# 脚: 股+膝の2関節 + 装甲 + 爪先3本
		for side in [-1.0, 1.0]:
			var hj := joint(pelvis, "HipJ", Vector3(side * 2.0, -0.2, 0))
			part(hj, MatLib.capsule(1.75, 5.0), m, Vector3(0, -2.4, 0), Vector3.ZERO, "Thigh")
			part(hj, MatLib.box(Vector3(1.6, 3.0, 0.8)), plate, Vector3(0, -2.2, 1.5), Vector3(6, 0, 0), "ThighArmor")
			var kj := joint(hj, "KneeJ", Vector3(0, -4.9, 0.2))
			part(kj, MatLib.sphere(1.35), m, Vector3.ZERO, Vector3.ZERO, "KneeBall")
			part(kj, MatLib.capsule(1.3, 4.4), m, Vector3(0, -2.1, 0.3), Vector3(-4, 0, 0), "Shin")
			part(kj, MatLib.box(Vector3(2.7, 1.3, 4.2)), m, Vector3(0, -4.4, 0.7), Vector3.ZERO, "Foot")
			for k in 3:
				part(kj, MatLib.cone(0.35, 1.4), bone,
						Vector3((k - 1) * 0.9, -4.5, 2.8), Vector3(100, 0, 0), "ToeClaw")
			if side < 0:
				_hip_l = hj
				_kn_l = kj
			else:
				_hip_r = hj
				_kn_r = kj

		glow_light(root, Color(1.0, 0.15, 0.3), 4.5, 140.0, Vector3(0, 14, 0))
		fx_particles(root, Color(1.0, 0.25, 0.15), 60, Vector3(2.0, 4.0, 2.5),
				Vector3(0, 3.0, -1.0), 0.22, 2.5, Vector3(0, 14, -2))

	var _step_side := 1

	func _animate(_delta: float, speed01: float) -> void:
		var ph := anim_time * 0.85
		var stride := maxf(speed01, 0.3)
		# 足の接地 (sin の符号反転) に同期した震脚
		var side := 1 if sin(ph) >= 0.0 else -1
		if side != _step_side:
			_step_side = side
			AudioKit.sfx(self, "footstep_kaiju", global_position + Vector3(side * 6, 0, 0),
					2.0, randf_range(0.9, 1.05), 60.0)
		var swing := sin(ph) * 0.38 * stride
		_hip_l.rotation.x = swing
		_hip_r.rotation.x = -swing
		_kn_l.rotation.x = -maxf(0.0, -sin(ph + 0.5)) * 0.5 * stride
		_kn_r.rotation.x = -maxf(0.0, sin(ph + 0.5)) * 0.5 * stride
		_arm_l.rotation.x = -swing * 0.5
		_arm_r.rotation.x = swing * 0.5
		_el_l.rotation.x = -0.2 - maxf(0.0, sin(ph)) * 0.15 * stride
		_el_r.rotation.x = -0.2 - maxf(0.0, -sin(ph)) * 0.15 * stride
		_torso.rotation.z = sin(ph) * 0.025
		_torso.rotation.y = sin(ph) * 0.04
		for i in _tails.size():
			(_tails[i] as Node3D).rotation.y = sin(anim_time * 0.8 - i * 0.7) * (0.12 + 0.08 * i)
		_head.rotation.y = sin(anim_time * 0.35) * 0.4
		_jaw.rotation.x = 0.08 + sin(anim_time * 0.6) * 0.06
		visual.position.y = absf(cos(ph)) * 0.5 * stride
