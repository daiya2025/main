class_name SoundBank
extends RefCounted
## Procedural audio synthesis.
##
## Every sound in the game is rendered here as 16-bit PCM at load time — the
## same "no imported assets" rule the meshes follow. Each recipe is a few
## subtractive/FM building blocks: noise through one-pole filters, sine stacks
## with exponential envelopes, and a soft clip to glue a layer together.
## Results are cached per name, so each clip is synthesised exactly once.

const RATE := 22050

static var _cache: Dictionary = {}

static func get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var samples: PackedFloat32Array
	var loop := false
	match name:
		"slash_1": samples = _slash(720.0, 0.22)
		"slash_2": samples = _slash(880.0, 0.20)
		"slash_3": samples = _slash(520.0, 0.30)
		"impact": samples = _impact(0.9, 110.0)
		"impact_heavy": samples = _impact(1.25, 68.0)
		"dash": samples = _dash()
		"jump": samples = _jump()
		"land": samples = _impact(0.55, 88.0)
		"bolt_fire": samples = _bolt_fire()
		"bolt_hit": samples = _impact(1.0, 150.0)
		"hurt": samples = _hurt()
		"enemy_die": samples = _enemy_die()
		"growl": samples = _growl()
		"wave_start": samples = _wave_start()
		"toast": samples = _toast()
		"footstep": samples = _footstep()
		"wind_loop":
			samples = _wind_loop()
			loop = true
		"hum_loop":
			samples = _hum_loop()
			loop = true
		_:
			push_warning("SoundBank: unknown sound '%s'" % name)
			samples = _toast()
	var wav := _wav(samples, loop)
	_cache[name] = wav
	return wav

static func clear_cache() -> void:
	_cache.clear()

# ------------------------------------------------------------- primitives --

static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

static func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out

## Deterministic noise: the same clip every run, so nothing "pops differently"
## after a reload.
static func _noise(n: int, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf_range(-1.0, 1.0)
	return out

static func _lowpass(buffer: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var alpha := clampf(TAU * cutoff_hz / (TAU * cutoff_hz + float(RATE)), 0.0, 1.0)
	var y := 0.0
	for i in buffer.size():
		y += alpha * (buffer[i] - y)
		buffer[i] = y
	return buffer

static func _highpass(buffer: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var alpha := float(RATE) / (float(RATE) + TAU * cutoff_hz)
	var y := 0.0
	var prev := 0.0
	for i in buffer.size():
		var x := buffer[i]
		y = alpha * (y + x - prev)
		prev = x
		buffer[i] = y
	return buffer

static func _soft_clip(buffer: PackedFloat32Array, drive: float = 1.6) -> PackedFloat32Array:
	for i in buffer.size():
		buffer[i] = tanh(buffer[i] * drive)
	return buffer

## amp *= e^(-t*rate), with an optional linear attack.
static func _env(buffer: PackedFloat32Array, attack_s: float, decay_rate: float) -> PackedFloat32Array:
	var attack_n := maxi(int(attack_s * RATE), 1)
	for i in buffer.size():
		var t := float(i) / float(RATE)
		var a := minf(float(i) / float(attack_n), 1.0)
		buffer[i] *= a * exp(-t * decay_rate)
	return buffer

static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gain_b: float = 1.0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var va := a[i] if i < a.size() else 0.0
		var vb := b[i] if i < b.size() else 0.0
		out[i] = va + vb * gain_b
	return out

## Sine with an exponential pitch sweep — the universal "energy" ingredient.
static func _sweep(seconds: float, f0: float, f1: float, decay_rate: float) -> PackedFloat32Array:
	var out := _buffer(seconds)
	var phase := 0.0
	var n := out.size()
	for i in n:
		var t := float(i) / float(n)
		var f := f0 * pow(f1 / f0, t)
		phase += TAU * f / float(RATE)
		out[i] = sin(phase) * exp(-float(i) / float(RATE) * decay_rate)
	return out

# ---------------------------------------------------------------- recipes --

## A blade cutting air: band-passed noise whose centre falls through the swing.
static func _slash(center_hz: float, seconds: float) -> PackedFloat32Array:
	var noise := _noise(int(seconds * RATE), 101)
	# time-varying band: run two sweeps of low/high pass by processing in halves
	noise = _highpass(noise, center_hz * 0.5)
	noise = _lowpass(noise, center_hz * 2.2)
	var out := _env(noise, 0.02, 11.0)
	# a faint metallic ring under the whoosh
	out = _mix(out, _sweep(seconds, center_hz * 3.1, center_hz * 2.2, 26.0), 0.10)
	return _soft_clip(out, 1.8)

static func _impact(weight: float, thump_hz: float) -> PackedFloat32Array:
	var crack := _highpass(_noise(int(0.16 * RATE), 202), 900.0)
	crack = _env(crack, 0.001, 34.0)
	var body := _lowpass(_noise(int(0.30 * RATE), 203), 300.0)
	body = _env(body, 0.002, 16.0)
	var thump := _sweep(0.34, thump_hz * 1.8, thump_hz * 0.7, 12.0)
	var out := _mix(_mix(crack, body, 1.2), thump, 1.5 * weight)
	return _soft_clip(out, 2.2 * weight)

static func _dash() -> PackedFloat32Array:
	var whoosh := _lowpass(_highpass(_noise(int(0.38 * RATE), 303), 220.0), 1400.0)
	# swell in, tear out
	for i in whoosh.size():
		var t := float(i) / float(whoosh.size())
		whoosh[i] *= smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.55, 1.0, t))
	var zip := _sweep(0.30, 240.0, 900.0, 7.0)
	return _soft_clip(_mix(whoosh, zip, 0.35), 1.6)

static func _jump() -> PackedFloat32Array:
	var out := _sweep(0.20, 180.0, 420.0, 13.0)
	var air := _env(_lowpass(_noise(int(0.18 * RATE), 404), 900.0), 0.01, 18.0)
	return _soft_clip(_mix(out, air, 0.5), 1.4)

static func _bolt_fire() -> PackedFloat32Array:
	# FM zap: carrier swept down, modulated hard, plus a noise sizzle.
	var seconds := 0.30
	var out := _buffer(seconds)
	var phase := 0.0
	var mod_phase := 0.0
	var n := out.size()
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(1500.0, 260.0, t * t)
		mod_phase += TAU * f * 2.7 / float(RATE)
		phase += TAU * (f + sin(mod_phase) * f * 0.6) / float(RATE)
		out[i] = sin(phase) * exp(-t * 6.5)
	var sizzle := _env(_highpass(_noise(n, 505), 2400.0), 0.002, 15.0)
	return _soft_clip(_mix(out, sizzle, 0.35), 2.0)

static func _hurt() -> PackedFloat32Array:
	var out := _sweep(0.24, 300.0, 120.0, 15.0)
	var grit := _env(_lowpass(_noise(int(0.2 * RATE), 606), 800.0), 0.001, 22.0)
	return _soft_clip(_mix(out, grit, 0.9), 3.0)

static func _enemy_die() -> PackedFloat32Array:
	# data shatter: granular downward chirps over a deep boom
	var seconds := 0.85
	var out := _buffer(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	for g in 22:
		var start := rng.randf_range(0.0, 0.45)
		var f0 := rng.randf_range(700.0, 2400.0)
		var grain := _sweep(0.12, f0, f0 * 0.4, 30.0)
		var offset := int(start * RATE)
		for i in grain.size():
			if offset + i < out.size():
				out[offset + i] += grain[i] * 0.22
	var boom := _sweep(0.8, 130.0, 42.0, 5.0)
	return _soft_clip(_mix(out, boom, 1.3), 1.8)

static func _growl() -> PackedFloat32Array:
	# low FM snarl for the wind-up telegraph
	var seconds := 0.6
	var out := _buffer(seconds)
	var phase := 0.0
	var n := out.size()
	for i in n:
		var t := float(i) / float(n)
		var f := 68.0 + sin(t * 31.0) * 9.0
		phase += TAU * f / float(RATE)
		out[i] = (sin(phase) + 0.55 * sin(phase * 2.02) + 0.3 * sin(phase * 3.11)) \
			* (0.4 + 0.6 * sin(t * PI))
	var breath := _env(_lowpass(_noise(n, 808), 500.0), 0.05, 4.0)
	return _soft_clip(_mix(out, breath, 0.5), 2.4)

static func _wave_start() -> PackedFloat32Array:
	# rising minor-third stab: the "here they come" sting
	var seconds := 0.7
	var a := _sweep(seconds, 220.0, 330.0, 4.0)
	var b := _sweep(seconds, 261.6, 392.0, 4.0)
	var out := _mix(a, b, 0.8)
	return _soft_clip(out, 1.3)

static func _toast() -> PackedFloat32Array:
	var a := _sweep(0.28, 880.0, 880.0, 9.0)
	var b := _sweep(0.22, 1318.5, 1318.5, 11.0)
	return _mix(a, b, 0.5)

static func _footstep() -> PackedFloat32Array:
	var out := _lowpass(_noise(int(0.09 * RATE), 909), 420.0)
	out = _env(out, 0.001, 42.0)
	var knock := _sweep(0.08, 140.0, 90.0, 30.0)
	return _soft_clip(_mix(out, knock, 0.8), 1.6)

# ----------------------------------------------------------------- loops ----

static func _wind_loop() -> PackedFloat32Array:
	var seconds := 5.0
	var out := _lowpass(_highpass(_noise(int(seconds * RATE), 1111), 90.0), 620.0)
	# slow amplitude weather, phase-aligned so the loop point is seamless
	var n := out.size()
	for i in n:
		var t := float(i) / float(n)
		out[i] *= 0.55 + 0.30 * sin(TAU * t) + 0.15 * sin(TAU * t * 3.0)
	# The filtered noise does not wrap; crossfade the tail into the head so the
	# loop point is inaudible.
	var fade := int(0.12 * RATE)
	for i in fade:
		var w := float(i) / float(fade)
		out[n - fade + i] = out[n - fade + i] * (1.0 - w) + out[i] * w
	return out

static func _hum_loop() -> PackedFloat32Array:
	# the monolith: a low fifth with a slow beat between detuned partials
	var seconds := 4.0
	var out := _buffer(seconds)
	var n := out.size()
	for i in n:
		var t := float(i) / float(RATE)
		var lt := float(i) / float(n)
		out[i] = 0.5 * sin(TAU * 55.0 * t) \
			+ 0.35 * sin(TAU * 82.5 * t) \
			+ 0.18 * sin(TAU * 110.5 * t) \
			+ 0.10 * sin(TAU * 164.0 * t)
		out[i] *= 0.8 + 0.2 * sin(TAU * lt)
	return _soft_clip(out, 1.1)
