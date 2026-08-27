class_name MonsterFactory
extends Object
## 5種のモンスターの造形 (プリミティブ彫刻 + 専用シェーダー) と個体アニメーション。
##  1. カゲオニ      : 黒曜石の肌にマグマが脈打つ 4m の鬼
##  2. ネオンリッパー : 玉虫色の外殻を持つ高速ラプトル
##  3. ゲンブ        : ルーンが輝く石造りの巨亀ゴーレム
##  4. スクランブラー : 交差点上空を漂う半透明の浮遊体
##  5. トシクイ      : ビル群の向こうを歩く 20m 級の怪獣

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
	var _hip_l: Node3D
	var _hip_r: Node3D
	var _head: Node3D
	var _chest: MeshInstance3D

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
		var eye := MatLib.emissive(Color(1.0, 0.45, 0.1), 8.0)

		var pelvis := joint(root, "PelvisJ", Vector3(0, 2.05, 0))
		part(pelvis, MatLib.capsule(0.62, 1.5), m, Vector3(0, 0.55, 0), Vector3(6, 0, 0), "Torso")
		_chest = part(pelvis, MatLib.sphere(0.68, Vector3(1, 0.85, 1)), m,
				Vector3(0, 1.08, 0.12), Vector3.ZERO, "Chest")
		for i in 3:
			part(pelvis, MatLib.cone(0.14 - i * 0.03, 0.55 - i * 0.1), m,
					Vector3(0, 1.35 - i * 0.42, -0.5 - i * 0.06), Vector3(-35, 0, 0), "Spike%d" % i)

		_head = joint(pelvis, "HeadJ", Vector3(0, 1.42, 0.38))
		part(_head, MatLib.sphere(0.30, Vector3(1, 0.9, 1)), m, Vector3(0, 0.05, 0.05), Vector3.ZERO, "Skull")
		part(_head, MatLib.box(Vector3(0.34, 0.14, 0.30)), m, Vector3(0, -0.12, 0.14), Vector3.ZERO, "Jaw")
		for side in [-1.0, 1.0]:
			part(_head, MatLib.sphere(0.045), eye, Vector3(side * 0.13, 0.06, 0.28), Vector3.ZERO, "Eye")
			part(_head, MatLib.cone(0.09, 0.55), m,
					Vector3(side * 0.18, 0.35, 0.0), Vector3(-12, 0, side * -24.0), "Horn")

		for side in [-1.0, 1.0]:
			var sj := joint(pelvis, "ShoulderJ", Vector3(side * 0.95, 1.0, 0.1))
			part(sj, MatLib.sphere(0.44), m, Vector3.ZERO, Vector3.ZERO, "Pauldron")
			part(sj, MatLib.capsule(0.23, 1.0), m, Vector3(side * 0.1, -0.55, 0), Vector3(0, 0, side * -10.0), "UpperArm")
			part(sj, MatLib.capsule(0.19, 1.1), m, Vector3(side * 0.18, -1.4, 0.08), Vector3(8, 0, 0), "ForeArm")
			part(sj, MatLib.sphere(0.30), m, Vector3(side * 0.2, -2.0, 0.14), Vector3.ZERO, "Fist")
			if side < 0:
				_sh_l = sj
			else:
				_sh_r = sj
			var hj := joint(pelvis, "HipJ", Vector3(side * 0.42, -0.05, 0))
			part(hj, MatLib.capsule(0.28, 0.95), m, Vector3(0, -0.5, 0), Vector3.ZERO, "Thigh")
			part(hj, MatLib.capsule(0.21, 0.85), m, Vector3(0, -1.28, 0.08), Vector3(-8, 0, 0), "Shin")
			part(hj, MatLib.box(Vector3(0.45, 0.24, 0.72)), m, Vector3(0, -1.85, 0.18), Vector3.ZERO, "Foot")
			if side < 0:
				_hip_l = hj
			else:
				_hip_r = hj

		glow_light(root, Color(1.0, 0.4, 0.08), 2.5, 9.0, Vector3(0, 2.6, 0.6))

	func _animate(_delta: float, speed01: float) -> void:
		var ph := anim_time * 4.6
		var swing := sin(ph) * 0.55 * speed01
		_hip_l.rotation.x = swing
		_hip_r.rotation.x = -swing
		if state == State.ATTACK:
			var smash := absf(sin(anim_time * 5.0))
			_sh_l.rotation.x = -2.4 + smash * 2.2
			_sh_r.rotation.x = -2.4 + smash * 2.2
		else:
			_sh_l.rotation.x = -swing * 0.6
			_sh_r.rotation.x = swing * 0.6
		visual.position.y = absf(cos(ph)) * 0.12 * speed01
		_chest.scale = Vector3.ONE * (1.0 + sin(anim_time * 1.5) * 0.03)
		_head.rotation.y = sin(anim_time * 0.5) * 0.3 * (1.0 - speed01)


# ================================================================= 2. ネオンリッパー
class NeonRipper extends MonsterBase:
	var _tail: Array = []
	var _hip_l: Node3D
	var _hip_r: Node3D
	var _neck: Node3D
	var _body: Node3D

	func _init() -> void:
		display_name = "ネオンリッパー"
		max_hp = 90.0
		move_speed = 8.5
		turn_speed = 8.0
		aggro_range = 42.0
		attack_range = 2.2
		attack_damage = 15.0
		body_radius = 0.7
		body_height = 1.9

	func _build_visual(root: Node3D) -> void:
		var m := shader_mat(SH_IRIDESCENT)
		var eye := MatLib.emissive(Color(0.2, 1.0, 0.9), 9.0)
		var tooth := MatLib.metal(Color(0.9, 0.92, 0.9), 0.25)

		_body = joint(root, "BodyJ", Vector3(0, 1.15, 0))
		part(_body, MatLib.capsule(0.36, 1.7), m, Vector3.ZERO, Vector3(90, 0, 0), "Body")
		part(_body, MatLib.sphere(0.34, Vector3(1, 0.8, 1)), m, Vector3(0, 0.12, 0.55), Vector3.ZERO, "ChestPlate")

		_neck = joint(_body, "NeckJ", Vector3(0, 0.12, 0.8))
		part(_neck, MatLib.capsule(0.15, 0.65), m, Vector3(0, 0.2, 0.16), Vector3(35, 0, 0), "Neck")
		var head := joint(_neck, "HeadJ", Vector3(0, 0.42, 0.38))
		part(head, MatLib.box(Vector3(0.24, 0.2, 0.6)), m, Vector3(0, 0.02, 0.22), Vector3.ZERO, "Skull")
		part(head, MatLib.box(Vector3(0.2, 0.07, 0.5)), m, Vector3(0, -0.12, 0.24), Vector3(8, 0, 0), "Jaw")
		part(head, MatLib.cone(0.05, 0.35, 0.01), m, Vector3(0, 0.2, -0.05), Vector3(40, 0, 0), "Crest")
		for side in [-1.0, 1.0]:
			part(head, MatLib.sphere(0.04), eye, Vector3(side * 0.1, 0.06, 0.3), Vector3.ZERO, "Eye")
			for i in 3:
				part(head, MatLib.cone(0.015, 0.07), tooth,
						Vector3(side * 0.07, -0.085, 0.2 + i * 0.12), Vector3(180, 0, 0), "Tooth")
			var aj := joint(_body, "ArmJ", Vector3(side * 0.3, -0.05, 0.5))
			part(aj, MatLib.capsule(0.07, 0.45), m, Vector3(0, -0.18, 0.08), Vector3(-30, 0, 0), "Arm")
			part(aj, MatLib.cone(0.03, 0.15), tooth, Vector3(0, -0.42, 0.2), Vector3(160, 0, 0), "Claw")

		var t_parent: Node3D = _body
		var sizes := [[0.24, 0.8], [0.16, 0.7], [0.09, 0.6]]
		var offset := Vector3(0, 0, -0.95)
		for i in 3:
			var tj := joint(t_parent, "TailJ%d" % i, offset)
			part(tj, MatLib.cone(sizes[i][0], sizes[i][1], sizes[i][0] * 0.5), m,
					Vector3(0, 0, -sizes[i][1] * 0.4), Vector3(-90, 0, 0), "Tail")
			_tail.append(tj)
			t_parent = tj
			offset = Vector3(0, 0, -sizes[i][1] * 0.85)

		for side in [-1.0, 1.0]:
			var hj := joint(_body, "HipJ", Vector3(side * 0.32, -0.08, -0.3))
			part(hj, MatLib.capsule(0.17, 0.62), m, Vector3(0, -0.26, 0.06), Vector3(12, 0, 0), "Thigh")
			part(hj, MatLib.capsule(0.10, 0.58), m, Vector3(0, -0.68, -0.04), Vector3(-18, 0, 0), "Shin")
			part(hj, MatLib.box(Vector3(0.14, 0.06, 0.4)), m, Vector3(0, -1.02, 0.1), Vector3.ZERO, "Foot")
			if side < 0:
				_hip_l = hj
			else:
				_hip_r = hj

		glow_light(root, Color(0.15, 0.9, 0.8), 1.8, 7.0, Vector3(0, 1.2, 0))

	func _animate(_delta: float, speed01: float) -> void:
		var ph := anim_time * 9.0
		var swing := sin(ph) * 0.9 * speed01
		_hip_l.rotation.x = swing
		_hip_r.rotation.x = -swing
		for i in _tail.size():
			var t: Node3D = _tail[i]
			t.rotation.y = sin(anim_time * 3.0 - i * 0.9) * (0.18 + 0.1 * i) * (0.4 + speed01)
		_body.rotation.x = -0.06 * speed01 + sin(ph * 2.0) * 0.02 * speed01
		_body.position.y = 1.15 + absf(cos(ph)) * 0.1 * speed01
		_neck.rotation.x = sin(ph) * 0.08 * speed01 + (0.35 if state == State.ATTACK else 0.0)


# ================================================================= 3. ゲンブ
class Genbu extends MonsterBase:
	var _legs: Array = []
	var _head: Node3D
	var _shell: MeshInstance3D

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
		var eye := MatLib.emissive(Color(0.3, 1.0, 0.5), 7.0)

		var base := joint(root, "BaseJ", Vector3(0, 1.35, 0))
		_shell = part(base, MatLib.sphere(1.95, Vector3(1, 0.6, 1)), m,
				Vector3(0, 0.35, 0), Vector3.ZERO, "Shell")
		var rim := TorusMesh.new()
		rim.inner_radius = 1.55
		rim.outer_radius = 2.05
		var rim_mi := part(base, rim, m, Vector3(0, -0.05, 0), Vector3.ZERO, "ShellRim")
		rim_mi.scale = Vector3(1, 0.55, 1)
		part(base, MatLib.sphere(1.35, Vector3(1, 0.55, 1)), m, Vector3(0, -0.55, 0), Vector3.ZERO, "Belly")
		for i in 6:
			var ang := TAU * i / 6.0
			part(base, MatLib.cone(0.18, 0.5), m,
					Vector3(cos(ang) * 1.1, 1.15, sin(ang) * 1.1), Vector3.ZERO, "ShellSpike")
		part(base, MatLib.cone(0.16, 0.9, 0.03), m, Vector3(0, -0.5, -2.1), Vector3(-110, 0, 0), "Tail")

		_head = joint(base, "HeadJ", Vector3(0, -0.15, 1.95))
		part(_head, MatLib.capsule(0.28, 0.8), m, Vector3(0, 0.05, -0.15), Vector3(75, 0, 0), "NeckM")
		part(_head, MatLib.sphere(0.42, Vector3(1, 0.85, 1.15)), m, Vector3(0, 0.1, 0.35), Vector3.ZERO, "Skull")
		part(_head, MatLib.cone(0.1, 0.25, 0.02), m, Vector3(0, 0.0, 0.75), Vector3(75, 0, 0), "Beak")
		for side in [-1.0, 1.0]:
			part(_head, MatLib.sphere(0.06), eye, Vector3(side * 0.18, 0.2, 0.6), Vector3.ZERO, "Eye")

		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var lj := joint(root, "LegJ", Vector3(sx * 1.25, 1.0, sz * 0.95))
				part(lj, MatLib.cone(0.34, 1.1, 0.42), m, Vector3(0, -0.5, 0), Vector3.ZERO, "Leg")
				part(lj, MatLib.sphere(0.4, Vector3(1, 0.35, 1)), m, Vector3(0, -1.0, 0), Vector3.ZERO, "Foot")
				_legs.append(lj)

		glow_light(root, Color(0.2, 1.0, 0.5), 2.0, 10.0, Vector3(0, 1.4, 0))

	func _animate(_delta: float, speed01: float) -> void:
		var ph := anim_time * 2.2
		for i in _legs.size():
			var phase: float = ph + (PI if i in [1, 2] else 0.0)
			var l: Node3D = _legs[i]
			l.position.y = 1.0 + maxf(0.0, sin(phase)) * 0.22 * speed01
		_shell.scale = Vector3.ONE * (1.0 + sin(anim_time * 0.9) * 0.008)
		_head.rotation.y = sin(anim_time * 0.7) * 0.35
		_head.rotation.x = (0.3 if state == State.ATTACK else sin(anim_time * 1.1) * 0.08)


# ================================================================= 4. スクランブラー
class Scrambler extends MonsterBase:
	var _tentacles: Array = []
	var _core: MeshInstance3D
	var _ring: MeshInstance3D

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
		var center := joint(root, "CenterJ", Vector3(0, 1.0, 0))
		part(center, MatLib.sphere(0.95, Vector3(1, 1.1, 1)), shell, Vector3.ZERO, Vector3.ZERO, "Shell")
		_core = part(center, MatLib.sphere(0.42), MatLib.emissive(Color(1.0, 0.25, 0.7), 6.0),
				Vector3.ZERO, Vector3.ZERO, "Core")
		var ring := TorusMesh.new()
		ring.inner_radius = 1.0
		ring.outer_radius = 1.18
		_ring = part(center, ring, MatLib.metal(Color(0.6, 0.65, 0.75), 0.2),
				Vector3.ZERO, Vector3(12, 0, 0), "Ring")

		for i in 6:
			var ang := TAU * i / 6.0
			var tj := joint(center, "TentJ%d" % i, Vector3(cos(ang) * 0.55, -0.7, sin(ang) * 0.55))
			var seg_parent: Node3D = tj
			for s in 3:
				var r := 0.05 - s * 0.013
				var length := 0.5 - s * 0.06
				part(seg_parent, MatLib.capsule(r, length), shell, Vector3(0, -length * 0.5, 0),
						Vector3.ZERO, "Seg")
				var nj := joint(seg_parent, "SegJ", Vector3(0, -length, 0))
				seg_parent = nj
			part(seg_parent, MatLib.sphere(0.05), MatLib.emissive(Color(0.4, 0.8, 1.0), 5.0),
					Vector3.ZERO, Vector3.ZERO, "Tip")
			_tentacles.append(tj)

		glow_light(root, Color(1.0, 0.3, 0.7), 3.0, 14.0, Vector3(0, 1.0, 0))

	func _animate(delta: float, _speed01: float) -> void:
		_ring.rotation.y += delta * 0.8
		_core.scale = Vector3.ONE * (1.0 + sin(anim_time * 2.4) * 0.12)
		for i in _tentacles.size():
			var t: Node3D = _tentacles[i]
			var ph := anim_time * 2.0 + i * 1.05
			t.rotation.x = sin(ph) * 0.3
			t.rotation.z = cos(ph * 0.8) * 0.3
			var seg: Node3D = t
			var depth := 0
			while seg.get_child_count() > 0 and depth < 3:
				for c in seg.get_children():
					if c.name.begins_with("SegJ"):
						seg = c
						seg.rotation.x = sin(ph - depth * 0.7) * 0.35
						break
				depth += 1


# ================================================================= 5. トシクイ
class Toshikui extends MonsterBase:
	var _hip_l: Node3D
	var _hip_r: Node3D
	var _head: Node3D
	var _torso: Node3D
	var _tail: Node3D

	func _init() -> void:
		display_name = "トシクイ"
		max_hp = 2000.0
		move_speed = 1.4
		turn_speed = 0.7
		aggro_range = 0.0   # プレイヤーを追わない超大型のセットピース
		attack_range = 8.0
		attack_damage = 50.0
		body_radius = 4.5
		body_height = 21.0

	func _build_visual(root: Node3D) -> void:
		var m := shader_mat(SH_KAIJU)
		var spine_mat := MatLib.emissive(Color(1.0, 0.12, 0.3), 3.5)
		var eye := MatLib.emissive(Color(1.0, 0.15, 0.15), 12.0)

		var pelvis := joint(root, "PelvisJ", Vector3(0, 10.0, 0))
		_torso = joint(pelvis, "TorsoJ", Vector3.ZERO)
		part(_torso, MatLib.capsule(3.3, 8.0), m, Vector3(0, 3.0, 0), Vector3(7, 0, 0), "Torso")
		part(_torso, MatLib.sphere(3.5, Vector3(1, 0.9, 1)), m, Vector3(0, 6.6, 0.6), Vector3.ZERO, "Chest")

		_head = joint(_torso, "HeadJ", Vector3(0, 9.2, 1.4))
		part(_head, MatLib.box(Vector3(2.2, 1.8, 3.4)), m, Vector3(0, 0.4, 0.8), Vector3.ZERO, "Skull")
		part(_head, MatLib.box(Vector3(1.9, 0.7, 2.8)), m, Vector3(0, -0.7, 0.9), Vector3(6, 0, 0), "Jaw")
		for side in [-1.0, 1.0]:
			part(_head, MatLib.sphere(0.28), eye, Vector3(side * 0.85, 0.7, 2.2), Vector3.ZERO, "Eye")
			part(_head, MatLib.cone(0.35, 1.6), m, Vector3(side * 0.9, 1.6, -0.4),
					Vector3(-20, 0, side * -25.0), "Horn")

		# 背ビレ (首→尾へ)
		for i in 7:
			var s := 2.2 - absf(i - 3.0) * 0.45
			part(_torso, MatLib.cone(s * 0.28, s), spine_mat,
					Vector3(0, 8.0 - i * 1.6, -2.4 - i * 0.25), Vector3(-30, 0, 0), "Fin%d" % i)

		_tail = joint(pelvis, "TailJ", Vector3(0, -0.5, -3.0))
		part(_tail, MatLib.cone(2.2, 9.0, 0.3), m, Vector3(0, -0.5, -4.0), Vector3(-100, 0, 0), "Tail")

		for side in [-1.0, 1.0]:
			var aj := joint(_torso, "ArmJ", Vector3(side * 3.6, 6.2, 0.5))
			part(aj, MatLib.capsule(1.0, 4.5), m, Vector3(side * 0.3, -2.2, 0), Vector3(0, 0, side * -8.0), "Arm")
			part(aj, MatLib.sphere(1.2), m, Vector3(side * 0.5, -4.6, 0.3), Vector3.ZERO, "Claw")
			var hj := joint(pelvis, "HipJ", Vector3(side * 2.0, -0.2, 0))
			part(hj, MatLib.capsule(1.75, 5.5), m, Vector3(0, -2.6, 0), Vector3.ZERO, "Thigh")
			part(hj, MatLib.capsule(1.35, 5.0), m, Vector3(0, -6.9, 0.5), Vector3(-6, 0, 0), "Shin")
			part(hj, MatLib.box(Vector3(2.7, 1.3, 4.2)), m, Vector3(0, -9.4, 0.8), Vector3.ZERO, "Foot")
			if side < 0:
				_hip_l = hj
			else:
				_hip_r = hj

		glow_light(root, Color(1.0, 0.15, 0.3), 4.0, 40.0, Vector3(0, 14, 0))

	func _animate(_delta: float, speed01: float) -> void:
		var ph := anim_time * 1.15
		var swing := sin(ph) * 0.38 * maxf(speed01, 0.3)
		_hip_l.rotation.x = swing
		_hip_r.rotation.x = -swing
		_torso.rotation.z = sin(ph) * 0.025
		_torso.rotation.y = sin(ph) * 0.04
		_tail.rotation.y = sin(anim_time * 0.8) * 0.25
		_head.rotation.y = sin(anim_time * 0.35) * 0.4
		visual.position.y = absf(cos(ph)) * 0.5 * maxf(speed01, 0.3)
