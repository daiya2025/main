class_name Player
extends CharacterBody3D
## 三人称プレイヤー。
## - CharacterRig が用意する実3Dモデル (Godette / Mannequiny / カスタムglb) を
##   スケルタルアニメーション (idle/walk/run/jump/land/attack) で駆動。
##   モデルが無い環境では HumanBuilder のパラメトリック人体+手続きアニメにフォールバック。
## - SpringArm カメラ + マウスルック + スプリント / ジャンプ / 近接攻撃
## - DemoDirector からの外部制御 (external_control) に対応

signal kills_changed(kills: int)
signal hp_changed(hp: float)

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.6
const ACCEL := 12.0
const JUMP_VELOCITY := 6.2
const GRAVITY := 17.0
const ATTACK_RANGE := 3.4
const ATTACK_DAMAGE := 40.0
const ATTACK_COOLDOWN := 0.45

var hp := 100.0
var kills := 0
var external_control := false
var move_target: Vector3
var has_move_target := false
var demo_sprint := false
var combat_mode := false          # 戦闘構え (combat_idle を基本姿勢に)
var _demo_face_dir := Vector3.ZERO
var _face_target: Node3D          # 常にこの相手の方を向く (デモ戦闘用)

var _joints: Dictionary = {}
var _anim: AnimationPlayer
var _anim_map: Dictionary = {}
var _anim_lock := 0.0
var _air_prev := false
var _attack_idx := 0
var rig_kind := "parametric"
var _walk_phase := 0.0
var _idle_time := 0.0
var _attack_cd := 0.0
var _attack_anim := 0.0
var _shake := 0.0

var cam_yaw: Node3D
var cam_pitch: SpringArm3D
var camera: Camera3D
var _visual: Node3D


func _ready() -> void:
	add_to_group("player")
	# 当たり判定
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)

	# 外見 (実3Dモデル優先 / CharacterRig 参照)
	var rig := CharacterRig.build()
	_visual = rig["root"]
	_joints = rig["joints"]
	_anim = rig["anim"]
	_anim_map = rig["map"]
	rig_kind = rig["kind"]
	add_child(_visual)

	# カメラリグ
	cam_yaw = Node3D.new()
	cam_yaw.name = "CamYaw"
	cam_yaw.position = Vector3(0, 1.58, 0)
	cam_yaw.top_level = false
	add_child(cam_yaw)
	cam_pitch = SpringArm3D.new()
	cam_pitch.name = "CamPitch"
	cam_pitch.spring_length = 3.4
	cam_pitch.collision_mask = 1
	cam_pitch.margin = 0.25
	cam_pitch.rotation.x = -0.12
	cam_yaw.add_child(cam_pitch)
	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.fov = 68.0
	camera.near = 0.1
	camera.far = 4000.0
	cam_pitch.add_child(camera)
	if not external_control:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if external_control:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw.rotation.y -= event.relative.x * 0.0028
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - event.relative.y * 0.0022, -1.1, 0.55)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_try_attack()


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_attack_anim = maxf(_attack_anim - delta * 3.0, 0.0)
	_shake = maxf(_shake - delta * 4.0, 0.0)

	var input_dir := Vector2.ZERO
	var sprinting := false
	if external_control:
		sprinting = demo_sprint
		if has_move_target:
			var to_target := move_target - global_position
			to_target.y = 0
			if to_target.length() > 0.4:
				var dir3 := to_target.normalized()
				input_dir = Vector2(dir3.x, dir3.z)
			else:
				has_move_target = false
				demo_sprint = false
	else:
		var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		sprinting = Input.is_action_pressed("sprint")
		# カメラ基準の移動方向
		var basis_yaw := cam_yaw.global_transform.basis
		var dir := (basis_yaw * Vector3(raw.x, 0, raw.y))
		dir.y = 0
		input_dir = Vector2(dir.x, dir.z).normalized() * raw.length()
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			if _anim and _anim_map.has("jump_up"):
				_play_once(_anim_map["jump_up"], 0.3)
		if Input.is_action_just_pressed("attack"):
			_try_attack()

	var target_speed := SPRINT_SPEED if sprinting else WALK_SPEED
	var desired := Vector3(input_dir.x, 0, input_dir.y) * target_speed
	velocity.x = move_toward(velocity.x, desired.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, desired.z, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# キャラクターの向き: 対峙相手 > デモ指定向き > 進行方向 (フレームレート非依存の平滑化)
	var planar := Vector3(velocity.x, 0, velocity.z)
	var prev_yaw := _visual.rotation.y
	if external_control and is_instance_valid(_face_target):
		var to_t := _face_target.global_position - global_position
		to_t.y = 0
		if to_t.length() > 0.2:
			_visual.rotation.y = lerp_angle(prev_yaw, atan2(to_t.x, to_t.z), 1.0 - exp(-9.0 * delta))
	elif external_control and _demo_face_dir.length() > 0.1 and planar.length() <= 0.5:
		var face_yaw := atan2(_demo_face_dir.x, _demo_face_dir.z)
		_visual.rotation.y = lerp_angle(prev_yaw, face_yaw, 1.0 - exp(-6.0 * delta))
	elif planar.length() > 0.5:
		var yaw := atan2(planar.x, planar.z)
		_visual.rotation.y = lerp_angle(prev_yaw, yaw, 1.0 - exp(-10.0 * delta))
	# 旋回バンク: ヨー角速度に応じて内側へ傾く (走りの精密感)
	var yaw_rate := angle_difference(prev_yaw, _visual.rotation.y) / maxf(delta, 0.001)
	var target_roll := clampf(-yaw_rate * 0.055, -0.22, 0.22) * clampf(planar.length() / WALK_SPEED, 0.0, 1.0)
	_visual.rotation.z = lerpf(_visual.rotation.z, target_roll, 1.0 - exp(-8.0 * delta))

	_animate(delta, planar.length())
	_apply_camera_shake()


# ------------------------------------------------------------------ アニメーション

func _animate(delta: float, speed: float) -> void:
	if _anim and not _anim_map.is_empty():
		_animate_rigged(delta, speed)
		return
	if _joints.is_empty():
		return
	_idle_time += delta
	var moving := speed > 0.4
	var freq := 2.4 * clampf(speed / WALK_SPEED, 0.5, 1.9)
	if moving:
		_walk_phase += delta * freq * TAU * 0.5
	var blend := clampf(speed / WALK_SPEED, 0.0, 1.0)
	var swing := sin(_walk_phase) * 0.62 * blend
	var breath := sin(_idle_time * 1.7) * 0.02

	_joints["hip_l"].rotation.x = swing
	_joints["hip_r"].rotation.x = -swing
	# 膝は遊脚期のみ曲がる
	_joints["knee_l"].rotation.x = -maxf(0.0, -sin(_walk_phase + 0.6)) * 1.1 * blend
	_joints["knee_r"].rotation.x = -maxf(0.0, sin(_walk_phase + 0.6)) * 1.1 * blend
	# 腕は脚と逆位相 + 攻撃モーション上書き
	_joints["shoulder_l"].rotation.x = -swing * 0.75
	_joints["shoulder_r"].rotation.x = swing * 0.75 - _attack_anim * 2.2
	_joints["shoulder_r"].rotation.z = -_attack_anim * 0.6
	_joints["elbow_l"].rotation.x = -0.25 - maxf(0.0, sin(_walk_phase)) * 0.4 * blend
	_joints["elbow_r"].rotation.x = -0.25 - maxf(0.0, -sin(_walk_phase)) * 0.4 * blend - _attack_anim * 0.8
	# 体幹: バウンス + 呼吸 + 前傾
	_joints["pelvis"].position.y = HumanBuilder.H_PELVIS + absf(cos(_walk_phase)) * 0.045 * blend
	_joints["spine"].rotation.x = 0.06 * blend + breath * 0.5
	_joints["spine"].rotation.y = sin(_walk_phase) * 0.08 * blend
	_joints["chest"].scale = Vector3.ONE * (1.0 + breath)
	_joints["head"].rotation.x = -0.04 * blend - breath * 0.4
	_joints["head"].rotation.y = sin(_idle_time * 0.4) * 0.06 * (1.0 - blend)


## 実モデルのアニメーションステートマシン
func _animate_rigged(delta: float, speed: float) -> void:
	_anim_lock = maxf(_anim_lock - delta, 0.0)
	var on_floor := is_on_floor()
	if on_floor and _air_prev and _anim_map.has("land"):
		_play_once(_anim_map["land"], 0.3)
	_air_prev = not on_floor
	if _anim_lock > 0.0:
		return
	var target: String
	var cadence := 1.0
	if not on_floor:
		target = _anim_map.get("jump_air", "")
	elif speed > WALK_SPEED * 1.25:
		target = _anim_map.get("run", "")
		cadence = clampf(speed / SPRINT_SPEED, 0.85, 1.25)
	elif speed > 0.5:
		target = _anim_map.get("walk", "")
		cadence = clampf(speed / WALK_SPEED, 0.7, 1.4)
	elif combat_mode and _anim_map.has("combat_idle"):
		target = _anim_map["combat_idle"]
	else:
		target = _anim_map.get("idle", "")
	if target != "" and _anim.has_animation(target):
		if _anim.current_animation != target:
			_anim.play(target, 0.25)
		_anim.speed_scale = cadence


func _play_once(anim_name: String, lock: float) -> void:
	if _anim and _anim.has_animation(anim_name):
		_anim.speed_scale = 1.0
		_anim.play(anim_name, 0.12)
		_anim_lock = lock


# ------------------------------------------------------------------ 戦闘

func _try_attack() -> void:
	if _attack_cd > 0.0:
		return
	_attack_cd = ATTACK_COOLDOWN
	_attack_anim = 1.0
	if _anim and _anim_map.has("attack"):
		var attacks: Array = _anim_map["attack"]
		_play_once(attacks[_attack_idx % attacks.size()], 0.45)
		_attack_idx += 1
	# デモ中は対峙相手へ即座に正対し、一歩踏み込む (斬撃が「当たって見える」ように)
	if external_control and is_instance_valid(_face_target):
		var to_t := _face_target.global_position - global_position
		to_t.y = 0
		if to_t.length() > 0.2:
			_visual.rotation.y = atan2(to_t.x, to_t.z)
			velocity += to_t.normalized() * 3.0
	AudioKit.sfx(self, "slash", global_position, -6.0, randf_range(0.95, 1.1))
	_spawn_slash_vfx()
	var fwd := _visual.global_transform.basis.z  # キャラは +Z 前
	for m in get_tree().get_nodes_in_group("monsters"):
		var monster := m as Node3D
		if monster == null or not monster.has_method("hit"):
			continue
		var to_m := monster.global_position - global_position
		var dist := to_m.length()
		var reach: float = ATTACK_RANGE + float(monster.get("body_radius"))
		if dist > reach:
			continue
		to_m.y = 0
		if to_m.normalized().dot(fwd) < 0.25:
			continue
		var killed: bool = monster.call("hit", ATTACK_DAMAGE, to_m.normalized())
		_shake = 0.35
		if killed:
			kills += 1
			kills_changed.emit(kills)


func _spawn_slash_vfx() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 1.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.4, 0.9, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.9, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	add_child(mi)
	mi.position = Vector3(0, 1.3, 0)
	mi.rotation = _visual.rotation + Vector3(0, 0, randf_range(-0.5, 0.5))
	mi.translate_object_local(Vector3(0, 0, -1.4))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_property(mi, "rotation:y", mi.rotation.y + 2.6, 0.3)
	tw.tween_property(mi, "scale", Vector3(1.35, 1.2, 1.35), 0.3)
	tw.chain().tween_callback(mi.queue_free)


func take_damage(dmg: float) -> void:
	hp = maxf(hp - dmg, 0.0)
	hp_changed.emit(hp)
	_shake = 0.5
	if hp <= 0.0:
		hp = 100.0  # デモ用: リスポーン
		hp_changed.emit(hp)
		global_position = Vector3(0, 1, 25)


func _apply_camera_shake() -> void:
	if camera == null:
		return
	if _shake > 0.001:
		camera.h_offset = randf_range(-1, 1) * _shake * 0.08
		camera.v_offset = randf_range(-1, 1) * _shake * 0.08
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## DemoDirector 用
func command_move_to(pos: Vector3, sprint: bool = false) -> void:
	move_target = pos
	has_move_target = true
	demo_sprint = sprint


func command_attack() -> void:
	_attack_cd = 0.0
	_try_attack()


func command_face(dir: Vector3) -> void:
	_demo_face_dir = dir


## この相手と対峙し続ける (null で解除)
func command_face_target(node: Node3D) -> void:
	_face_target = node


func set_visual_yaw(yaw: float) -> void:
	_visual.rotation.y = yaw


## 指定アニメを一定時間再生 (構えポーズ等)
func command_play(anim_name: String, lock: float) -> void:
	_play_once(anim_name, lock)


func anim_for(key: String) -> String:
	var v: Variant = _anim_map.get(key, "")
	return v if v is String else ""
