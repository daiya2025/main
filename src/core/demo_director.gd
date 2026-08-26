class_name DemoDirector
extends Node
## 60-second attract mode.
##
## A deterministic, seekable timeline: every camera shot is a pure function of
## demo time, so the whole reel can be scrubbed (which is also how it is
## tested and screenshotted without playing it through in real time). The hero
## is driven by a bot writing the same inputs a player would produce.
##
## Start it with `--demo` on the command line or F9 in game; any real input
## ends it (except in looping kiosk mode).

signal demo_finished()

const DURATION := 60.0

var time: float = 0.0
var active: bool = false
var kiosk: bool = false          # loop forever, ignore input-to-exit

var _main: Node3D
var _player: Player
var _camera: Camera3D
var _bot_attack_cooldown: float = 0.0
var _bot_dash_cooldown: float = 0.0
var _bot_jump_cooldown: float = 3.0
var _bot_strafe_sign: float = 1.0
var _bot_strafe_timer: float = 0.0
var _spawned_extra: bool = false

## The reel. Each shot: start time, name, and a Callable(t01, T) -> Transform3D
## producing the camera transform (t01 = 0..1 within the shot; T = demo time).
var _shots: Array = []

func _init(main: Node3D) -> void:
	name = "DemoDirector"
	_main = main

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "DemoCamera"
	_camera.fov = 38.0
	add_child(_camera)
	_build_reel()
	set_process(false)
	set_physics_process(false)

static func _look(pos: Vector3, target: Vector3, roll: float = 0.0) -> Transform3D:
	var direction := target - pos
	if direction.length_squared() < 0.000001:
		direction = Vector3.FORWARD
	var xform := Transform3D.IDENTITY.looking_at(direction)
	if absf(roll) > 0.0001:
		# dutch: rotate about the view axis after aiming
		xform.basis = xform.basis * Basis(Vector3.BACK, roll)
	return xform.translated(pos)

## Where the hero is heading — used to lead the frame like a camera operator.
func _hero_lead() -> Vector3:
	if _player != null and is_instance_valid(_player):
		var v: Vector3 = _player.velocity
		v.y = 0.0
		if v.length() > 1.0:
			return v.normalized()
		return -_player.global_transform.basis.z
	return Vector3.FORWARD

func _build_reel() -> void:
	var arena := WorldBuilder.ARENA_RADIUS
	_shots = [
		# 0-8 s: descending aerial orbit over the lit district.
		[0.0, "establish", func(t: float, _T: float) -> Transform3D:
			var angle := lerpf(-0.5, 0.7, t)
			var radius := lerpf(126.0, 88.0, t)
			var height := lerpf(86.0, 46.0, t)
			return _look(Vector3(cos(angle) * radius, height, sin(angle) * radius),
				Vector3(0, lerpf(14.0, 8.0, t), 0), 0.05 * sin(t * PI))],
		# 8-14 s: fast low dolly down the avenue toward the plaza.
		[8.0, "street", func(t: float, _T: float) -> Transform3D:
			var z := lerpf(arena + 40.0, arena + 7.0, t)
			return _look(Vector3(lerpf(-6.0, -1.2, t), lerpf(1.6, 3.2, t), z),
				Vector3(0, lerpf(5.5, 2.6, t), 0), -0.035)],
		# 14-24 s: tracking shot running WITH the hero, camera leading him.
		[14.0, "chase", func(t: float, T: float) -> Transform3D:
			var hero := _hero_pos()
			var lead := _hero_lead()
			var side := lead.cross(Vector3.UP)
			var pos := hero + lead * 2.6 + side * lerpf(2.2, 1.2, t) + Vector3(0, 1.35 + 0.1 * sin(T * 1.7), 0)
			return _look(pos, hero + Vector3(0, 1.25, 0) + lead * 0.8, 0.03)],
		# 24-38 s: close combat orbit, height breathing with the action.
		[24.0, "combat_orbit", func(_t: float, T: float) -> Transform3D:
			var hero := _hero_pos()
			var angle := T * 0.55
			var radius := 4.0 + 0.7 * sin(T * 0.8)
			return _look(hero + Vector3(cos(angle) * radius, 1.7 + 0.45 * sin(T * 1.1), sin(angle) * radius),
				hero + Vector3(0, 1.15, 0), 0.05 * sin(T * 0.7))],
		# 38-46 s: low frontal tracking — the hero charges the lens.
		[38.0, "combat_low", func(t: float, _T: float) -> Transform3D:
			var hero := _hero_pos()
			var lead := _hero_lead()
			var pos := hero + lead * lerpf(4.2, 2.8, t) + Vector3(0, 0.55, 0)
			return _look(pos, hero + Vector3(0, 1.45, 0), -0.045)],
		# 46-52 s: slow-motion over-the-shoulder push-in (time runs at 0.35x).
		[46.0, "slowmo", func(t: float, _T: float) -> Transform3D:
			var hero := _hero_pos()
			var lead := _hero_lead()
			var side := lead.cross(Vector3.UP)
			var pos := hero - lead * lerpf(2.0, 1.2, t) + side * 0.75 + Vector3(0, lerpf(1.8, 1.5, t), 0)
			return _look(pos, hero + lead * 3.0 + Vector3(0, 1.15, 0), 0.06)],
		# 52-60 s: crane away and up to the title framing.
		[52.0, "outro", func(t: float, _T: float) -> Transform3D:
			var e := t * t
			return _look(Vector3(lerpf(3.0, 30.0, e), lerpf(1.8, 22.0, e), lerpf(12.0, 55.0, e)),
				Vector3(0, lerpf(2.0, 10.5, e), 0), 0.02 * (1.0 - t))],
	]

func _hero_pos() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return Vector3(0, 1, 8)

# ---------------------------------------------------------------- control --

func start(loop_forever: bool = false) -> void:
	if active:
		return
	active = true
	kiosk = loop_forever
	time = 0.0
	_player = Game.alive_player() as Player
	if _player != null:
		_player.bot_enabled = true
	Game.demo_mode = true
	# Bring the first wave in quickly so the fight starts while the reel is on
	# its hero coverage instead of after it.
	if Game.enemies_alive <= 0 and _main != null:
		_main.set("_wave_timer", minf(float(_main.get("_wave_timer")), 3.0))
	_camera.current = true
	set_process(true)
	set_physics_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Signals.demo_mode_changed.emit(true)

func stop() -> void:
	if not active:
		return
	active = false
	Game.demo_mode = false
	if _player != null and is_instance_valid(_player):
		_player.bot_enabled = false
	set_process(false)
	set_physics_process(false)
	Game.set_base_time_scale(1.0)
	# hand the view back to the gameplay rig
	var rig := _main.get_node_or_null("CameraRig") as CameraRig
	if rig != null:
		rig.camera().current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	Signals.demo_outro.emit(false)
	Signals.demo_mode_changed.emit(false)
	demo_finished.emit()

## Places the camera (and bot clock) at an arbitrary demo time — used by the
## screenshot tests to sample the reel without playing 60 real-time seconds.
func seek(to_time: float) -> void:
	time = clampf(to_time, 0.0, DURATION)
	_update_outro()
	_apply_camera()

var _outro_shown := false

func _update_outro() -> void:
	var in_outro := time >= 52.0
	if in_outro != _outro_shown:
		_outro_shown = in_outro
		Signals.demo_outro.emit(in_outro)

func shot_name_at(t: float) -> String:
	var current: Array = _shots[0]
	for shot in _shots:
		if t >= float(shot[0]):
			current = shot
	return String(current[1])

func _apply_camera() -> void:
	var current: Array = _shots[0]
	var next_start := DURATION
	for i in _shots.size():
		if time >= float(_shots[i][0]):
			current = _shots[i]
			next_start = float(_shots[i + 1][0]) if i + 1 < _shots.size() else DURATION
	var t01 := clampf((time - float(current[0])) / maxf(next_start - float(current[0]), 0.001), 0.0, 1.0)
	# ease shot-local time so every cut starts and ends calm
	var eased := t01 * t01 * (3.0 - 2.0 * t01)
	_camera.transform = (current[2] as Callable).call(eased, time)

func _process(delta: float) -> void:
	# The reel clock runs in REAL seconds: _process delta shrinks under the
	# slow-mo Engine.time_scale, so divide it back out — the demo stays a true
	# 60 seconds while the world moves at 0.35x inside the kill-cam shot.
	time += delta / maxf(Engine.time_scale, 0.05)
	Game.set_base_time_scale(0.35 if (time >= 46.5 and time < 51.0) else 1.0)
	if time >= DURATION:
		if kiosk:
			time = 0.0
			_outro_shown = false
			Signals.demo_outro.emit(false)
		else:
			stop()
			return
	_update_outro()
	_apply_camera()

var _spawn_cooldown: float = 0.0

func _physics_process(delta: float) -> void:
	_ensure_combat(delta)
	_drive_bot(delta)

## The wave system paces itself for play, not for film — between waves the
## reel would show an empty plaza. From the chase shot to the outro the demo
## keeps at least two creatures alive near the hero at all times.
func _ensure_combat(delta: float) -> void:
	_spawn_cooldown = maxf(0.0, _spawn_cooldown - delta)
	if time < 13.0 or time > 50.0 or _spawn_cooldown > 0.0:
		return
	if _player == null or not is_instance_valid(_player):
		return
	var alive := 0
	for node in _player.get_tree().get_nodes_in_group("enemy"):
		if node.has_method("is_alive") and node.call("is_alive"):
			alive += 1
	if alive >= 2:
		return
	_spawn_cooldown = 2.2
	var kind := Monster.Kind.SWARMER
	if time > 36.0:
		kind = Monster.Kind.STALKER
	elif randf() < 0.4:
		kind = Monster.Kind.STALKER
	var agent := MonsterAgent.new()
	agent.setup(kind)
	agent.target = _player
	var angle := randf() * TAU
	var at := _player.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(8.0, 12.0)
	at.y = 1.0
	# keep spawns inside the plaza so the fight stays in frame
	var flat := Vector2(at.x, at.z)
	if flat.length() > WorldBuilder.ARENA_RADIUS - 2.0:
		flat = flat.normalized() * (WorldBuilder.ARENA_RADIUS - 4.0)
		at = Vector3(flat.x, 1.0, flat.y)
	_main.add_child(agent)
	agent.global_position = at
	Game.enemies_alive += 1
	VFX.dissolve(_main, at + Vector3(0, 1.0, 0), 0.8)

func _unhandled_input(event: InputEvent) -> void:
	if not active or kiosk:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			or event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		stop()

# -------------------------------------------------------------------- bot --

## Writes the same intent structure the input layer produces, so the player
## code runs unmodified: walk to the plaza early, then fight whatever is close.
func _drive_bot(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.alive:
		return
	_bot_attack_cooldown = maxf(0.0, _bot_attack_cooldown - delta)
	_bot_dash_cooldown = maxf(0.0, _bot_dash_cooldown - delta)
	_bot_jump_cooldown = maxf(0.0, _bot_jump_cooldown - delta)
	_bot_strafe_timer -= delta
	if _bot_strafe_timer <= 0.0:
		# change circling direction every few seconds so the footwork varies
		_bot_strafe_sign = -_bot_strafe_sign
		_bot_strafe_timer = randf_range(1.6, 3.2)
	var bot := {"move": Vector3.ZERO, "attack": false, "special": false,
		"dash": false, "sprint": false, "jump": false}

	var enemy := _nearest_enemy()
	if time < 20.0:
		# sprint into the plaza so the street shot has a moving subject
		var to_centre := Vector3.ZERO - _player.global_position
		to_centre.y = 0.0
		if to_centre.length() > 6.0:
			bot["move"] = to_centre.normalized()
			bot["sprint"] = true
			if _bot_jump_cooldown <= 0.0:
				bot["jump"] = true
				_bot_jump_cooldown = 3.5
	elif enemy != null:
		var to_enemy := enemy.global_position - _player.global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		var toward := to_enemy.normalized()
		var strafe := toward.rotated(Vector3.UP, PI * 0.5) * _bot_strafe_sign
		if dist > 14.0 and _bot_attack_cooldown <= 0.0:
			bot["special"] = true
			_bot_attack_cooldown = 1.2
		if dist > 2.2:
			# angle in rather than beeline: reads as footwork, not homing
			bot["move"] = (toward * 0.75 + strafe * 0.65).normalized()
			bot["sprint"] = dist > 7.0
			if dist > 4.5 and dist < 10.0 and _bot_dash_cooldown <= 0.0:
				bot["dash"] = true
				_bot_dash_cooldown = 2.2
			if dist < 6.0 and _bot_jump_cooldown <= 0.0 and randf() < delta * 0.5:
				bot["jump"] = true
				_bot_jump_cooldown = 4.0
		else:
			# in range: keep circling between swings instead of standing still
			bot["move"] = strafe * 0.5
			if _bot_attack_cooldown <= 0.0:
				bot["attack"] = true
				_bot_attack_cooldown = 0.28
	else:
		# between waves: lap the monolith at a run
		var orbit := Vector3(-_player.global_position.z, 0, _player.global_position.x)
		if orbit.length() > 0.1:
			bot["move"] = (orbit.normalized() * 0.85 + (Vector3.ZERO - _player.global_position).normalized() * 0.1).normalized()
			bot["sprint"] = true
	_player.bot_input = bot

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in _player.get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_alive") and not enemy.call("is_alive"):
			continue
		var d := _player.global_position.distance_squared_to(enemy.global_position)
		if d < best_distance:
			best_distance = d
			best = enemy
	return best
