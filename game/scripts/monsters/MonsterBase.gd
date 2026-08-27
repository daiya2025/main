class_name MonsterBase
extends CharacterBody3D
## モンスター共通基盤: ステートマシンAI (徘徊/追跡/攻撃/死亡)、
## 被弾フラッシュ、ディゾルブ消滅、手続きアニメーションのフック。

enum State { IDLE, CHASE, ATTACK, DEAD }

var display_name := "Monster"
var max_hp := 100.0
var hp := 100.0
var move_speed := 3.0
var turn_speed := 6.0
var aggro_range := 26.0
var attack_range := 2.2
var attack_damage := 12.0
var body_radius := 0.8
var body_height := 2.0
var flying := false
var hover_height := 0.0
var demo_mode := false          # true の間はプレイヤーに反応しない (撮影用)

var state: int = State.IDLE
var anim_time := 0.0
var visual: Node3D

var _spawn_pos: Vector3
var _wander_target: Vector3
var _wander_timer := 0.0
var _attack_timer := 0.0
var _flash := 0.0
var _mats: Array[ShaderMaterial] = []
var _move_dir := Vector3.ZERO
var _demo_target: Vector3
var _demo_has_target := false
var _demo_attack_until := 0.0


func _ready() -> void:
	add_to_group("monsters")
	hp = max_hp
	_spawn_pos = global_position
	_wander_target = _spawn_pos

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_build_visual(visual)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = body_radius
	cap.height = maxf(body_height, body_radius * 2.05)
	cs.shape = cap
	cs.position.y = body_height * 0.5
	add_child(cs)


## 派生クラスが外見を構築する
func _build_visual(_root: Node3D) -> void:
	pass


## 派生クラスの手続きアニメーション (speed01 = 移動量 0..1)
func _animate(_delta: float, _speed01: float) -> void:
	pass


# ------------------------------------------------------------------ 共通ヘルパ

func shader_mat(shader_path: String, params: Dictionary = {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	for key in params:
		mat.set_shader_parameter(key, params[key])
	_mats.append(mat)
	return mat


func part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot_deg: Vector3 = Vector3.ZERO, part_name: String = "Part") -> MeshInstance3D:
	var mi := MatLib.mesh_node(mesh, mat, pos, rot_deg, part_name)
	parent.add_child(mi)
	return mi


func joint(parent: Node3D, joint_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = joint_name
	n.position = pos
	parent.add_child(n)
	return n


func glow_light(parent: Node3D, color: Color, energy: float, range_m: float,
		pos: Vector3 = Vector3.ZERO) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.position = pos
	l.shadow_enabled = false
	parent.add_child(l)
	return l


func set_param(param: String, value: Variant) -> void:
	for m in _mats:
		m.set_shader_parameter(param, value)


## 常時エフェクト (残り火 / 雫 / 光の粒)。加算合成の小さなクアッドを漂わせる。
func fx_particles(parent: Node3D, color: Color, amount: int, extents: Vector3,
		velocity: Vector3, size: float, life: float, pos: Vector3 = Vector3.ZERO) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.visibility_aabb = AABB(-extents * 2.0 - Vector3.ONE * 4.0, extents * 4.0 + Vector3.ONE * 8.0)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = extents
	mat.direction = velocity.normalized() if velocity.length() > 0.01 else Vector3.UP
	mat.initial_velocity_min = velocity.length() * 0.6
	mat.initial_velocity_max = velocity.length() * 1.3
	mat.gravity = Vector3.ZERO
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.6
	mat.turbulence_noise_scale = 4.0
	mat.scale_min = 0.7
	mat.scale_max = 1.4
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.albedo_color = Color(color.r, color.g, color.b, 0.35)
	qmat.emission_enabled = true
	qmat.emission = color
	qmat.emission_energy_multiplier = 2.0
	quad.material = qmat
	p.draw_pass_1 = quad
	p.position = pos
	parent.add_child(p)
	return p


# ------------------------------------------------------------------ AI

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	anim_time += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		set_param("hit_flash", _flash)

	var player := _get_player()
	var to_player := Vector3.ZERO
	var dist := INF
	if player:
		to_player = player.global_position - global_position
		dist = to_player.length()

	# デモ演出: 指定時間だけ攻撃モーションを強制
	if demo_mode:
		state = State.ATTACK if anim_time < _demo_attack_until else \
				(State.IDLE if state == State.ATTACK else state)

	var desired := Vector3.ZERO
	match state:
		State.IDLE:
			desired = _do_wander(delta)
			if not demo_mode and dist < aggro_range:
				state = State.CHASE
		State.CHASE:
			if demo_mode:
				state = State.IDLE
			elif dist < attack_range + body_radius + 0.6:
				state = State.ATTACK
				_attack_timer = 0.5
			elif dist > aggro_range * 1.6:
				state = State.IDLE
			else:
				desired = to_player.normalized() * move_speed
		State.ATTACK:
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				if dist < attack_range + body_radius + 1.0 and player and player.has_method("take_damage"):
					player.call("take_damage", attack_damage)
				_attack_timer = 1.3
			if demo_mode:
				if anim_time >= _demo_attack_until:
					state = State.IDLE
			elif dist > attack_range + body_radius + 1.4:
				state = State.CHASE

	desired.y = 0
	velocity.x = move_toward(velocity.x, desired.x, move_speed * 3.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, move_speed * 3.0 * delta)

	if flying:
		var target_y: float = hover_height + sin(anim_time * 1.3) * 0.5
		velocity.y = (target_y - global_position.y) * 1.5
	elif not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()

	# 向き: 移動方向 or 攻撃対象
	var face := Vector3(velocity.x, 0, velocity.z)
	if state in [State.CHASE, State.ATTACK] and dist < aggro_range * 2.0:
		face = Vector3(to_player.x, 0, to_player.z)
	if face.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), turn_speed * delta)

	var speed01 := clampf(Vector3(velocity.x, 0, velocity.z).length() / maxf(move_speed, 0.01), 0.0, 1.0)
	_animate(delta, speed01)


func _do_wander(delta: float) -> Vector3:
	_wander_timer -= delta
	if _demo_has_target:
		_wander_target = _demo_target
	elif _wander_timer <= 0.0:
		_wander_timer = randf_range(3.0, 7.0)
		var ang := randf() * TAU
		_wander_target = _spawn_pos + Vector3(cos(ang), 0, sin(ang)) * randf_range(3.0, 14.0)
	var to_t := _wander_target - global_position
	to_t.y = 0
	if to_t.length() < 1.0:
		if _demo_has_target:
			_demo_has_target = false
		return Vector3.ZERO
	return to_t.normalized() * move_speed * (1.0 if _demo_has_target else 0.55)


func _get_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null


# ------------------------------------------------------------------ 戦闘

func hit(dmg: float) -> bool:
	if state == State.DEAD:
		return false
	hp -= dmg
	_flash = 1.0
	set_param("hit_flash", 1.0)
	AudioKit.sfx(self, "impact", global_position + Vector3(0, body_height * 0.5, 0),
			-4.0, randf_range(0.9, 1.15))
	if not demo_mode and state == State.IDLE:
		state = State.CHASE
	if hp <= 0.0:
		_die()
		return true
	return false


func _die() -> void:
	state = State.DEAD
	AudioKit.sfx(get_parent(), "dissolve", global_position + Vector3(0, 1, 0), -2.0)
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: set_param("dissolve", v), 0.0, 1.0, 1.6)
	# シェーダー以外のパーツ (牙・金属など) は最後に縮んで消える
	tw.parallel().tween_property(visual, "scale", Vector3.ONE * 0.02, 0.5).set_delay(1.15)
	tw.tween_callback(queue_free)


# ------------------------------------------------------------------ デモ制御

func demo_goto(pos: Vector3) -> void:
	_demo_target = pos
	_demo_has_target = true
	state = State.IDLE


func demo_attack(duration: float = 2.0) -> void:
	_demo_attack_until = anim_time + duration
	_attack_timer = 0.6
