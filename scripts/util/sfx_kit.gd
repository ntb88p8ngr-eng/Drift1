extends RefCounted
## Synthesised sound effects (no asset files): clock, thunder, phone, footsteps, doors, lights,
## engine starter, roller door, campfire and an eerie drone. Every sound is rendered once into an
## AudioStreamWAV (16 bit, mono) and cached.

const RATE := 22050

static var _cache := {}


static func get_sound(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var s: AudioStreamWAV
	match name:
		"tick":
			s = _wav(_tick())
		"chime":
			s = _wav(_chime())
		"thunder_near":
			s = _wav(_thunder(true, 11))
		"thunder_far":
			s = _wav(_thunder(false, 23))
		"vibrate":
			s = _wav(_vibrate())
		"notify":
			s = _wav(_notify())
		"step":
			s = _wav(_step())
		"door_open":
			s = _wav(_door_open())
		"fluoro_on":
			s = _wav(_fluoro_on())
		"hum":
			s = _wav(_hum(), true)
		"car_door":
			s = _wav(_car_door())
		"starter":
			s = _wav(_starter())
		"roller_door":
			s = _wav(_roller_door())
		"fire":
			s = _wav(_fire(), true)
		"drone":
			s = _wav(_drone(), true)
		"whoosh":
			s = _wav(_whoosh())
		"light_go":
			s = _wav(_beeps([[1320.0, 0.0, 0.12], [1760.0, 0.16, 0.3]]))
		"light_warn":
			s = _wav(_beeps([[880.0, 0.0, 0.1]]))
		"light_stop":
			s = _wav(_buzzer())
		"whistle":
			s = _wav(_whistle())
		_:
			s = _wav(PackedFloat32Array([0.0]))
	_cache[name] = s
	return s


## Plays a sound once on a new player under `parent` (3D when `at` is given), frees it afterwards.
static func play(parent: Node, name: String, volume_db := 0.0, at = null, pitch := 1.0) -> Node:
	var p: Node
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = get_sound(name)
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		p3.unit_size = 6.0
		p3.max_distance = 120.0
		parent.add_child(p3)
		p3.global_position = at
		p3.play()
		p3.finished.connect(p3.queue_free)
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = get_sound(name)
		p2.volume_db = volume_db
		p2.pitch_scale = pitch
		parent.add_child(p2)
		p2.play()
		p2.finished.connect(p2.queue_free)
		p = p2
	return p


static func _wav(data: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


# ---------------------------------------------------------------------------
# Sounds
# ---------------------------------------------------------------------------
static func _tick() -> PackedFloat32Array:
	var b := _buf(0.06)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 3100.0 * t) * 0.5 + rng.randf_range(-1.0, 1.0) * 0.5) * exp(-t * 160.0) * 0.6
	return b


## Grandfather clock strike: inharmonic bell partials with long, separate decays.
static func _chime() -> PackedFloat32Array:
	var b := _buf(4.0)
	var f0 := 196.0
	var partials := [[0.5, 0.35, 1.2], [1.0, 0.5, 1.6], [2.0, 0.3, 2.4], [2.4, 0.22, 3.2], [3.0, 0.18, 4.0], [4.2, 0.12, 5.5], [5.4, 0.08, 7.0]]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * f0 * float(p[0]) * t + float(p[0])) * float(p[1]) * exp(-t * float(p[2]))
		var strike := exp(-t * 90.0) * sin(TAU * 1900.0 * t) * 0.2
		b[i] = (v + strike) * 0.55 * minf(t * 400.0, 1.0)
	return b


## Thunder: a crack (near strikes) and a long rolling rumble of low-passed noise.
static func _thunder(near: bool, seed_v: int) -> PackedFloat32Array:
	var dur := 6.5 if near else 7.5
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var lp1 := 0.0
	var lp2 := 0.0
	var env_n := FastNoiseLite.new()
	env_n.seed = seed_v
	env_n.frequency = 3.0
	for i in b.size():
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += (w - lp1) * (0.08 if near else 0.04)
		lp2 += (lp1 - lp2) * 0.05
		var roll := 0.55 + 0.45 * env_n.get_noise_1d(t)
		var env := minf(t * (6.0 if near else 1.5), 1.0) * exp(-t * (0.55 if near else 0.45)) * roll
		var v := lp2 * 6.0 * env
		if near:
			# the crack: bright, sharp, in the first 0.4 s
			v += w * exp(-t * 9.0) * 0.55 * minf(t * 200.0, 1.0)
			v += lp1 * 3.0 * exp(-t * 3.0)
		b[i] = clampf(v, -1.0, 1.0) * 0.9
	return b


static func _vibrate() -> PackedFloat32Array:
	var b := _buf(1.1)
	for i in b.size():
		var t := float(i) / RATE
		var on := 1.0 if (t < 0.4 or (t > 0.6 and t < 1.0)) else 0.0
		var buzz := signf(sin(TAU * 172.0 * t)) * 0.4 + sin(TAU * 344.0 * t) * 0.2
		b[i] = buzz * on * 0.35 * (0.8 + 0.2 * sin(TAU * 31.0 * t))
	return b


static func _notify() -> PackedFloat32Array:
	var b := _buf(0.55)
	for i in b.size():
		var t := float(i) / RATE
		var f := 1318.5 if t < 0.12 else 1760.0
		var t0 := t if t < 0.12 else t - 0.12
		b[i] = (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t)) * exp(-t0 * 9.0) * 0.4 * minf(t0 * 300.0, 1.0)
	return b


static func _step() -> PackedFloat32Array:
	var b := _buf(0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
		b[i] = (sin(TAU * 62.0 * t) * exp(-t * 28.0) * 0.8 + lp * exp(-t * 40.0) * 0.6) * 0.8
	return b


static func _door_open() -> PackedFloat32Array:
	var b := _buf(1.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		# latch click
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 120.0) * 0.6
		# hinge creak: a scratchy, wobbling low tone
		if t > 0.1:
			var f := 140.0 + 70.0 * sin(t * 7.0) + 40.0 * sin(t * 23.0)
			ph += TAU * f / RATE
			var saw := fposmod(ph, TAU) / PI - 1.0
			v += saw * 0.25 * smoothstep(0.1, 0.25, t) * (1.0 - smoothstep(0.8, 1.15, t)) * (0.6 + 0.4 * rng.randf())
		b[i] = v * 0.7
	return b


static func _fluoro_on() -> PackedFloat32Array:
	var b := _buf(1.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in b.size():
		var t := float(i) / RATE
		var v := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.7            # switch clack
		for k in [0.25, 0.45, 0.6]:
			if t > k:
				v += rng.randf_range(-1.0, 1.0) * exp(-(t - k) * 150.0) * 0.35       # starter pings
		var on := smoothstep(0.55, 0.7, t)
		v += (sin(TAU * 100.0 * t) * 0.12 + sin(TAU * 200.0 * t) * 0.05) * (on + 0.4 * float(fmod(t, 0.2) < 0.1) * (1.0 - on))
		b[i] = v * 0.7
	return b


static func _hum() -> PackedFloat32Array:
	var b := _buf(1.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 100.0 * t) * 0.1 + sin(TAU * 200.0 * t) * 0.04 + sin(TAU * 300.0 * t) * 0.015
	return b


static func _car_door() -> PackedFloat32Array:
	var b := _buf(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.15
		var thump := sin(TAU * 55.0 * t) * exp(-t * 14.0)
		var clunk := sin(TAU * 420.0 * t) * exp(-t * 35.0) * 0.4 + lp * exp(-t * 30.0) * 0.8
		b[i] = (thump + clunk) * 0.8
	return b


static func _starter() -> PackedFloat32Array:
	var b := _buf(1.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in b.size():
		var t := float(i) / RATE
		var crank := 0.5 + 0.5 * sin(TAU * 8.5 * t)
		var whine := sin(TAU * (330.0 + 30.0 * sin(TAU * 8.5 * t)) * t) * 0.18
		var chug := rng.randf_range(-1.0, 1.0) * 0.3 * pow(crank, 3.0)
		var env := minf(t * 20.0, 1.0) * (1.0 - smoothstep(1.0, 1.3, t))
		b[i] = (whine + chug + sin(TAU * 60.0 * t) * crank * 0.3) * env * 0.7
	return b


static func _roller_door() -> PackedFloat32Array:
	var b := _buf(3.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var next_click := 0.0
	var click_t := -1.0
	for i in b.size():
		var t := float(i) / RATE
		if t >= next_click:
			click_t = t
			next_click = t + rng.randf_range(0.05, 0.09)
		var env := minf(t * 4.0, 1.0) * (1.0 - smoothstep(3.1, 3.6, t))
		var motor := sin(TAU * 95.0 * t) * 0.12 + sin(TAU * 190.0 * t) * 0.06
		var rattle := rng.randf_range(-1.0, 1.0) * exp(-(t - click_t) * 180.0) * 0.45
		var bang := sin(TAU * 70.0 * t) * exp(-maxf(t - 3.35, 0.0) * 20.0) * 0.6 * float(t > 3.35)
		b[i] = (motor + rattle) * env + bang
	return b


static func _fire() -> PackedFloat32Array:
	var b := _buf(4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var lp := 0.0
	var pop_t := -1.0
	var pop_a := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.06
		if rng.randf() < 0.0009:
			pop_t = t
			pop_a = rng.randf_range(0.2, 0.7)
		var pop := rng.randf_range(-1.0, 1.0) * pop_a * exp(-(t - pop_t) * 260.0) if pop_t >= 0.0 else 0.0
		# seamless loop: fade the roar in/out over the loop point
		var edge := minf(t / 0.2, (4.0 - t) / 0.2)
		b[i] = lp * 1.6 * clampf(0.6 + edge, 0.6, 1.0) + pop
	return b


static func _drone() -> PackedFloat32Array:
	var b := _buf(8.0)
	for i in b.size():
		var t := float(i) / RATE
		# frequencies chosen so that 8 s hold whole cycles (loops without a click)
		var v := sin(TAU * 55.0 * t) * 0.18 + sin(TAU * 55.625 * t) * 0.16 + sin(TAU * 82.5 * t) * 0.08
		v += sin(TAU * 110.125 * t) * 0.05 * (0.5 + 0.5 * sin(TAU * 0.25 * t))
		b[i] = v * (0.7 + 0.3 * sin(TAU * 0.125 * t))
	return b


static func _whoosh() -> PackedFloat32Array:
	var b := _buf(0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := 0.02 + 0.25 * sin(PI * t / 0.9)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * k
		b[i] = lp * sin(PI * t / 0.9) * 0.9
	return b


## Start-light beeps: [frequency, start, length] – a soft sine with a little square in it.
static func _beeps(notes: Array) -> PackedFloat32Array:
	var end := 0.0
	for n in notes:
		end = maxf(end, float(n[1]) + float(n[2]))
	var b := _buf(end + 0.05)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for n in notes:
			var lt := t - float(n[1])
			if lt >= 0.0 and lt < float(n[2]):
				var env := minf(lt * 300.0, 1.0) * minf((float(n[2]) - lt) * 120.0, 1.0)
				var ph := TAU * float(n[0]) * lt
				v += (sin(ph) * 0.75 + signf(sin(ph)) * 0.12) * env
		b[i] = v * 0.55
	return b


## Red light: a short, harsh buzzer.
static func _buzzer() -> PackedFloat32Array:
	var b := _buf(0.55)
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t * 200.0, 1.0) * minf((0.55 - t) * 40.0, 1.0)
		var saw := fposmod(t * 220.0, 1.0) * 2.0 - 1.0
		var saw2 := fposmod(t * 331.0, 1.0) * 2.0 - 1.0
		b[i] = (saw * 0.5 + saw2 * 0.35) * env * 0.5
	return b


## Caught moving on red: a referee's whistle (trilling pea).
static func _whistle() -> PackedFloat32Array:
	var b := _buf(0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 2900.0 + 180.0 * sin(TAU * 32.0 * t)
		ph += TAU * f / RATE
		var env := minf(t * 60.0, 1.0) * minf((0.7 - t) * 20.0, 1.0)
		b[i] = (sin(ph) * 0.7 + rng.randf_range(-0.12, 0.12)) * env * 0.45
	return b
