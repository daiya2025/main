class_name AudioKit
extends Object
## サウンド再生の共通基盤。
## アセットは tools/generate_audio.py がプロシージャル合成した ogg/wav
## (res://assets/audio/)。存在しない環境でも無音で安全に動作する。

const DIR := "res://assets/audio/"

static var _cache: Dictionary = {}


static func stream(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var st: AudioStream = null
	for ext: String in ["ogg", "wav"]:
		var path: String = DIR + sound_name + "." + ext
		if ResourceLoader.exists(path):
			st = load(path) as AudioStream
			break
	_cache[sound_name] = st
	return st


## 位置付きの使い捨てSFX。pos=Vector3.INF で2D(非位置)再生。
static func sfx(parent: Node, sound_name: String, pos: Vector3 = Vector3.INF,
		volume_db: float = 0.0, pitch: float = 1.0, unit_size: float = 12.0) -> void:
	var st := stream(sound_name)
	if st == null or parent == null or not parent.is_inside_tree():
		return
	if pos == Vector3.INF:
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.bus = "Master"
		parent.add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = st
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		p3.unit_size = unit_size
		p3.max_db = 6.0
		parent.add_child(p3)
		p3.global_position = pos
		p3.finished.connect(p3.queue_free)
		p3.play()


## BGM / 環境音。loop=true でシームレスループ (ogg) or 再生終了時に再スタート。
static func music(parent: Node, sound_name: String, volume_db: float = -6.0,
		loop: bool = true) -> AudioStreamPlayer:
	var st := stream(sound_name)
	if st == null or parent == null:
		return null
	if loop:
		st = st.duplicate()
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		elif st is AudioStreamWAV:
			var w := st as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = w.data.size() / 4  # 16bit stereo
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = volume_db
	p.bus = "Master"
	parent.add_child(p)
	if loop:
		p.finished.connect(p.play)  # ループ非対応フォーマットの保険
	p.play()
	return p


static func available() -> bool:
	return stream("music_demo") != null or stream("rain_loop") != null
