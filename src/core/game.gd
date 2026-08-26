extends Node
## Global game state, hit-stop and pacing. Autoloaded as `Game`.

var score: int = 0
var combo: int = 0
var combo_timer: float = 0.0
var wave_index: int = 0
var enemies_alive: int = 0
var photo_mode: bool = false
var demo_mode: bool = false
var player: Node3D = null

const COMBO_WINDOW := 2.6

var _hit_stop_remaining: float = 0.0
var _base_time_scale: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Signals.hit_stop_requested.connect(_on_hit_stop)
	Signals.player_spawned.connect(func(p: Node3D) -> void: player = p)
	Signals.enemy_died.connect(_on_enemy_died)

func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.0001)
	if _hit_stop_remaining > 0.0:
		_hit_stop_remaining -= real_delta
		if _hit_stop_remaining <= 0.0:
			Engine.time_scale = _base_time_scale
	if combo > 0:
		combo_timer -= real_delta
		if combo_timer <= 0.0:
			combo = 0
			Signals.combo_changed.emit(0, 0.0)

func _on_hit_stop(duration: float, time_scale: float) -> void:
	# A short, hard freeze on impact is the single strongest "weight" cue in
	# action games; stacking is clamped so chained hits never lock the sim.
	_hit_stop_remaining = maxf(_hit_stop_remaining, duration)
	Engine.time_scale = clampf(time_scale, 0.02, 1.0)

func add_combo(amount: int = 1) -> void:
	combo += amount
	combo_timer = COMBO_WINDOW
	Signals.combo_changed.emit(combo, combo_timer)

func _on_enemy_died(_enemy: Node3D, _pos: Vector3) -> void:
	enemies_alive = maxi(0, enemies_alive - 1)
	score += 120 * maxi(1, combo)
	Signals.wave_changed.emit(wave_index, enemies_alive)

func reset() -> void:
	score = 0
	combo = 0
	wave_index = 0
	enemies_alive = 0
	Engine.time_scale = 1.0
