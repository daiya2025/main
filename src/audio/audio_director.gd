extends Node
## Positional SFX routing and ambient beds. Autoloaded as `Audio`.
##
## Gameplay code never touches players or buses: it emits
## `Signals.sfx_requested(name, world_pos)` (or calls `play()` directly) and a
## voice is taken from a round-robin pool. Ambient beds (wind, the monolith
## hum) are started once by the game director via `start_ambience()`.

const POOL_3D := 14
const POOL_UI := 4

## Per-sound tuning: volume dB, pitch jitter, minimum seconds between plays
## (the anti-machine-gun guard for footsteps and impacts).
const PROFILES := {
	"slash_1": {"db": -6.0, "jitter": 0.06, "cooldown": 0.05},
	"slash_2": {"db": -6.0, "jitter": 0.06, "cooldown": 0.05},
	"slash_3": {"db": -4.0, "jitter": 0.05, "cooldown": 0.05},
	"impact": {"db": -5.0, "jitter": 0.10, "cooldown": 0.03},
	"impact_heavy": {"db": -2.5, "jitter": 0.08, "cooldown": 0.05},
	"dash": {"db": -8.0, "jitter": 0.05, "cooldown": 0.1},
	"jump": {"db": -10.0, "jitter": 0.07, "cooldown": 0.08},
	"land": {"db": -9.0, "jitter": 0.09, "cooldown": 0.1},
	"bolt_fire": {"db": -7.0, "jitter": 0.05, "cooldown": 0.05},
	"bolt_hit": {"db": -6.0, "jitter": 0.08, "cooldown": 0.04},
	"hurt": {"db": -4.0, "jitter": 0.06, "cooldown": 0.2},
	"enemy_die": {"db": -3.0, "jitter": 0.07, "cooldown": 0.05},
	"growl": {"db": -6.0, "jitter": 0.10, "cooldown": 0.3},
	"wave_start": {"db": -6.0, "jitter": 0.0, "cooldown": 0.5},
	"toast": {"db": -14.0, "jitter": 0.0, "cooldown": 0.2},
	"footstep": {"db": -16.0, "jitter": 0.14, "cooldown": 0.12},
}

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_ui: int = 0
var _last_played: Dictionary = {}
var _ambient_nodes: Array[Node] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.set_bus_volume_db(0, float(Settings.get_value("master_volume_db", -4.0)))
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Voice3D_%d" % i
		p.max_distance = 80.0
		p.unit_size = 6.0
		p.attenuation_filter_cutoff_hz = 12000.0
		p.panning_strength = 1.4
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		p.name = "VoiceUI_%d" % i
		add_child(p)
		_pool_ui.append(p)
	Signals.sfx_requested.connect(play)

## `world_pos` of INF plays flat (UI / non-positional).
func play(name: String, world_pos: Vector3 = Vector3.INF, volume_offset_db: float = 0.0) -> void:
	var profile: Dictionary = PROFILES.get(name, {})
	var now := Time.get_ticks_msec() * 0.001
	var cooldown := float(profile.get("cooldown", 0.03))
	if now - float(_last_played.get(name, -10.0)) < cooldown:
		return
	_last_played[name] = now

	var stream := SoundBank.get_stream(name)
	var db := float(profile.get("db", -6.0)) + volume_offset_db
	var jitter := float(profile.get("jitter", 0.05))
	var pitch := 1.0 + randf_range(-jitter, jitter)

	if world_pos.x == INF:
		var ui := _pool_ui[_next_ui]
		_next_ui = (_next_ui + 1) % POOL_UI
		ui.stream = stream
		ui.volume_db = db
		ui.pitch_scale = pitch
		ui.play()
		return
	var voice := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	voice.global_position = world_pos
	voice.stream = stream
	voice.volume_db = db
	voice.pitch_scale = pitch
	voice.play()

## Wind everywhere, hum at the monolith. Idempotent; the previous beds are
## cleared so a scene reload does not stack them.
func start_ambience(monolith_pos: Vector3 = Vector3(0, 11, 0)) -> void:
	for node in _ambient_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_ambient_nodes.clear()

	var wind := AudioStreamPlayer.new()
	wind.name = "Wind"
	wind.stream = SoundBank.get_stream("wind_loop")
	wind.volume_db = -18.0
	wind.autoplay = true
	add_child(wind)
	wind.play()
	_ambient_nodes.append(wind)

	var hum := AudioStreamPlayer3D.new()
	hum.name = "MonolithHum"
	hum.stream = SoundBank.get_stream("hum_loop")
	hum.volume_db = -6.0
	hum.max_distance = 60.0
	hum.unit_size = 9.0
	add_child(hum)
	hum.global_position = monolith_pos
	hum.play()
	_ambient_nodes.append(hum)
