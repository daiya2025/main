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

static func _look(pos: Vector3, target: Vector3) -> Transform3D:
	var direction := target - pos
	if direction.length_squared() < 0.000001:
		direction = Vector3.FORWARD
	return Transform3D.IDENTITY.looking_at(direction).translated(pos)

func _build_reel() -> void:
	var arena := WorldBuilder.ARENA_RADIUS
	_shots = [
		# 0-10 s: high establishing orbit over the district, monolith centred.
		[0.0, "establish", func(t: float, _T: float) -> Transform3D:
			var angle := lerpf(-0.4, 0.9, t)
			var radius := lerpf(95.0, 62.0, t)
			var height := lerpf(58.0, 30.0, t)
			return _look(Vector3(cos(angle) * radius, height, sin(angle) * radius), Vector3(0, 9, 0))],
		# 10-20 s: low crane through a street toward the plaza.
		[10.0, "street", func(t: float, _T: float) -> Transform3D:
			var z := lerpf(arena + 46.0, arena + 6.0, t)
			var height := lerpf(2.2, 4.6, t)
			return _look(Vector3(lerpf(-8.0, -2.0, t), height, z), Vector3(0, 6.5 - t * 3.0, 0))],
		# 20-32 s: slow arc around the hero as he walks in and wave 1 spawns.
		[20.0, "hero", func(t: float, _T: float) -> Transform3D:
			var hero := _hero_pos()
			var angle := lerpf(2.4, 0.6, t)
			var radius := lerpf(6.5, 4.2, t)
			return _look(hero + Vector3(cos(angle) * radius, lerpf(2.6, 1.5, t), sin(angle) * radius),
				hero + Vector3(0, 1.25, 0))],
		# 32-46 s: combat coverage — shoulder-height tracking shot.
		[32.0, "combat", func(t: float, T: float) -> Transform3D:
			var hero := _hero_pos()
			var angle := T * 0.35
			return _look(hero + Vector3(cos(angle) * 5.2, 2.1 + sin(T * 0.9) * 0.3, sin(angle) * 5.2),
				hero + Vector3(0, 1.1, 0))],
		# 46-54 s: low hero-worship angle against the monolith.
		[46.0, "low", func(t: float, _T: float) -> Transform3D:
			var hero := _hero_pos()
			var to_monolith := (Vector3.ZERO - hero).normalized()
			var pos := hero - to_monolith * lerpf(3.4, 2.6, t) + Vector3(0, 0.55, 0)
			return _look(pos, hero + Vector3(0, 1.3, 0) + to_monolith * 3.0)],
		# 54-60 s: pull away and rise to the title framing.
		[54.0, "outro", func(t: float, _T: float) -> Transform3D:
			var e := t * t
			return _look(Vector3(lerpf(4.0, 26.0, e), lerpf(2.0, 20.0, e), lerpf(14.0, 52.0, e)),
				Vector3(0, lerpf(2.0, 10.0, e), 0))],
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
	_player = Game.player as Player
	if _player != null:
		_player.bot_enabled = true
	Game.demo_mode = true
	_camera.current = true
	set_process(true)
	set_physics_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Signals.toast.emit("DEMO — 任意のキーで操作に戻る", 4.0)

func stop() -> void:
	if not active:
		return
	active = false
	Game.demo_mode = false
	if _player != null and is_instance_valid(_player):
		_player.bot_enabled = false
	set_process(false)
	set_physics_process(false)
	# hand the view back to the gameplay rig
	var rig := _main.get_node_or_null("CameraRig") as CameraRig
	if rig != null:
		rig.camera().current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	demo_finished.emit()

## Places the camera (and bot clock) at an arbitrary demo time — used by the
## screenshot tests to sample the reel without playing 60 real-time seconds.
func seek(to_time: float) -> void:
	time = clampf(to_time, 0.0, DURATION)
	_apply_camera()

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
	time += delta
	if time >= DURATION:
		if kiosk:
			time = 0.0
		else:
			stop()
			return
	_apply_camera()

func _physics_process(delta: float) -> void:
	_drive_bot(delta)

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
	var bot := {"move": Vector3.ZERO, "attack": false, "special": false, "dash": false, "sprint": false}

	var enemy := _nearest_enemy()
	if time < 20.0:
		# walk toward the plaza centre so the street shot has a subject
		var to_centre := Vector3.ZERO - _player.global_position
		to_centre.y = 0.0
		if to_centre.length() > 6.0:
			bot["move"] = to_centre.normalized()
	elif enemy != null:
		var to_enemy := enemy.global_position - _player.global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		if dist > 14.0 and _bot_attack_cooldown <= 0.0:
			bot["special"] = true
			_bot_attack_cooldown = 1.4
		if dist > 2.4:
			bot["move"] = to_enemy.normalized()
			bot["sprint"] = dist > 8.0
			if dist > 5.0 and dist < 9.0 and _bot_dash_cooldown <= 0.0:
				bot["dash"] = true
				_bot_dash_cooldown = 2.6
		elif _bot_attack_cooldown <= 0.0:
			bot["attack"] = true
			_bot_attack_cooldown = 0.32
	else:
		# idle flourish between waves: drift around the monolith
		var orbit := Vector3(-_player.global_position.z, 0, _player.global_position.x)
		if orbit.length() > 0.1:
			bot["move"] = orbit.normalized() * 0.4
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
