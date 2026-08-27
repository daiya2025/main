extends Node3D
## エントリポイント。
## 起動引数:
##   --preset=night|dusk|day  ライティングプリセット (既定 night)
##   --demo                   60秒シネマティックデモを再生
##   --screenshot=3,12,26     指定秒で PNG を user://shots/ に保存 (画作りの自己評価用)
## Movie Maker モード (--write-movie) では自動でデモになる。

var city: CityLoader
var props: CityProps
var player: Player
var monsters: Dictionary = {}
var env: Dictionary = {}

var _shot_times: Array = []
var _elapsed := 0.0


func _ready() -> void:
	_register_inputs()
	var args := OS.get_cmdline_user_args()
	var preset := "night"
	var demo := OS.has_feature("movie")
	for a in args:
		if a.begins_with("--preset="):
			preset = a.get_slice("=", 1)
		elif a == "--demo":
			demo = true
		elif a.begins_with("--screenshot="):
			for t in a.get_slice("=", 1).split(","):
				_shot_times.append(float(t))
			_shot_times.sort()

	print("[Main] SHIBUYA RIFT 起動 preset=%s demo=%s" % [preset, demo])
	env = EnvironmentSetup.setup(self, preset)
	var night: float = env.get("night_factor", 1.0)

	city = CityLoader.new()
	city.name = "City"
	add_child(city)
	city.build(night)

	props = CityProps.new()
	props.name = "Props"
	add_child(props)
	props.build(night)

	player = Player.new()
	player.name = "Player"
	player.external_control = demo
	add_child(player)
	player.global_position = Vector3(6, 0.6, 28)

	monsters = MonsterFactory.spawn_all(self)

	if demo:
		var director := DemoDirector.new()
		director.name = "DemoDirector"
		add_child(director)
		director.setup(self, player, monsters, env, props)
	else:
		var hud := HUD.new()
		hud.name = "HUD"
		add_child(hud)
		hud.setup(player)

	QualityAudit.run(self, city, env, monsters)


func _process(delta: float) -> void:
	if _shot_times.is_empty():
		return
	_elapsed += delta
	if _elapsed >= float(_shot_times[0]):
		var t: float = _shot_times.pop_front()
		DirAccess.make_dir_recursive_absolute("user://shots")
		var img := get_viewport().get_texture().get_image()
		var path := "user://shots/t%05.1f.png" % t
		img.save_png(path)
		print("[Shot] ", ProjectSettings.globalize_path(path))


func _register_inputs() -> void:
	var bindings := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"jump": [KEY_SPACE],
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key in bindings[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)
