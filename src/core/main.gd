extends Node3D
## Game director: builds the level, spawns the hero and runs the wave loop.

const WAVE_PAUSE := 5.0
const ARENA_RADIUS := 21.0

var sky: SkyEnv
var player: Player
var camera_rig: CameraRig
var hud: HUD
var world_root: Node3D
var world_stats: Dictionary = {}

var _wave_timer: float = 0.0
var _wave_active: bool = false
var _ready_to_play: bool = false
var _restart_timer: float = 0.0

func _ready() -> void:
	randomize()
	Game.reset()

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)

	sky = SkyEnv.new("golden_hour")
	add_child(sky)

	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)

	_boot()

func _boot() -> void:
	var seed_value := int(Settings.get_value("world_seed", 20250825))
	world_stats = await WorldBuilder.build_staged(world_root, seed_value)

	# Build the hero and pre-warm every creature mesh while the loading screen
	# is still up. Without this the first spawn of each archetype would stall
	# mid-fight on its one-off sculpt.
	Signals.world_build_progress.emit("hero", 0.93)
	await get_tree().process_frame
	player = Player.new()
	player.name = "DigiHariMan"
	add_child(player)
	player.global_position = Vector3(0, 1.2, ARENA_RADIUS * 0.55)

	Signals.world_build_progress.emit("creatures", 0.97)
	await get_tree().process_frame
	for kind in [Monster.Kind.SWARMER, Monster.Kind.STALKER, Monster.Kind.BRUTE]:
		var warm := Monster.create_node(kind, {"quality": 1.0})
		warm.free()
		await get_tree().process_frame

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = player
	add_child(camera_rig)
	player.camera_rig = camera_rig

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	Signals.world_build_finished.emit()
	Signals.toast.emit("デジハリマン起動。ノイズ体を排除せよ。", 4.0)
	print_rich("[color=orange]WORLD[/color] %d buildings / %d props / %d plants / %d lights"
		% [world_stats.get("buildings", 0), world_stats.get("props", 0),
			world_stats.get("plants", 0), world_stats.get("lights", 0)])

	_ready_to_play = true
	_wave_timer = 2.5

func _process(delta: float) -> void:
	if not _ready_to_play:
		return
	if player != null and not player.alive:
		_restart_timer += delta
		if _restart_timer > 3.0:
			_restart()
		return

	if _wave_active:
		if Game.enemies_alive <= 0:
			_wave_active = false
			_wave_timer = WAVE_PAUSE
			Signals.toast.emit("WAVE %d 制圧完了" % Game.wave_index, 3.0)
	else:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_start_wave()

# ------------------------------------------------------------------- waves --

func _start_wave() -> void:
	Game.wave_index += 1
	_wave_active = true
	var index := Game.wave_index

	# Composition ramps: swarmers early, stalkers from wave 2, a brute every
	# third wave. Total pressure grows but never all at once.
	var spawn_list: Array = []
	var swarmers := clampi(2 + index, 2, 9)
	var stalkers := clampi(index - 1, 0, 6)
	var brutes := 1 if index % 3 == 0 else 0
	for i in swarmers:
		spawn_list.append(Monster.Kind.SWARMER)
	for i in stalkers:
		spawn_list.append(Monster.Kind.STALKER)
	for i in brutes:
		spawn_list.append(Monster.Kind.BRUTE)

	Game.enemies_alive = spawn_list.size()
	Signals.wave_changed.emit(index, Game.enemies_alive)
	Signals.toast.emit("WAVE %d — 敵性体 %d" % [index, spawn_list.size()], 3.0)

	for i in spawn_list.size():
		var angle := TAU * float(i) / float(spawn_list.size()) + randf() * 0.5
		var radius := ARENA_RADIUS + randf_range(4.0, 16.0)
		var position := Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
		_spawn(spawn_list[i], position)

func _spawn(kind: Monster.Kind, at: Vector3) -> void:
	var agent := MonsterAgent.new()
	agent.setup(kind)
	agent.target = player
	world_root.add_child(agent)
	agent.global_position = at
	VFX.dissolve(world_root, at + Vector3(0, 1.0, 0), 0.8)

# ------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("free_cursor"):
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("photo_mode"):
		Game.photo_mode = not Game.photo_mode
		get_tree().paused = Game.photo_mode
		Signals.photo_mode_toggled.emit(Game.photo_mode)
		Signals.toast.emit("フォトモード: %s" % ("ON" if Game.photo_mode else "OFF"), 2.0)
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_R:
		if player != null and not player.alive:
			_restart()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
