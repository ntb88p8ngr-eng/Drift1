extends Node
## Real-time synthesized car audio (no samples needed). Every engine has its own voice, built from
## exhaust pulses (one per cylinder firing) that ring through two exhaust resonances, plus the
## engine-order harmonics for a stable pitch:
##   r34    – real recordings (tools/make_r34_audio.py): HKS exhaust RB26 played as pitch-normalized
##            grains that follow rpm and throttle, real turbo whistle driven by boost and blow-off
##            "pssst" + compressor flutter one-shots on every lift-off/upshift (the only audible turbo)
##   i6     – synthesized straight six (fallback for the R34 when the samples are missing)
##   v8     – Ford 5.0 Coyote: cross-plane V8 burble from uneven pulses, deep bass, overrun crackle
##   v8race – BMW M3 GT3: high-revving race V8, harsh straight-through exhaust, straight-cut gear whine
##            and ignition-cut bangs on upshifts
## Plus launch-control two-step stutter, nitro hiss, tyre squeal, wind and impacts.

const MIX_RATE := 22050.0
const R34Data = preload("res://scripts/car/r34_sound_data.gd")
const SAMPLE_DIR := "res://assets/audio/"
const ENGINE_SAMPLE_GAIN := 0.7
const SPOOL_GAIN := 0.5
const LIFT_GAIN := 0.85

static var _sample_cache := {}


## Synchronous granular player over a pitch-normalized buffer (see tools/make_r34_audio.py). Two
## Hann-windowed grains overlap by half; each new grain starts at the requested position shifted by
## whole periods so it stays in phase with the grain that is fading out.
class Granular:
	var buf := PackedFloat32Array()
	var period := 294.0
	var grain := 882.0
	var pos_a := 0.0
	var pos_b := 0.0
	var age_a := 0.0
	var jitter := 6       # random offset in whole periods, keeps held notes from sounding robotic

	func _init(data: PackedFloat32Array, p_period: float, periods_per_grain: float, p_jitter: int) -> void:
		buf = data
		period = p_period
		grain = p_period * periods_per_grain
		jitter = p_jitter
		pos_b = grain * 0.5

	func _start(target: float, other: float) -> float:
		var hi := float(buf.size()) - grain - 4.0
		var span := period * float(jitter)
		# near the ends of the buffer the random window is shifted inwards
		var centre := clampf(target, span, maxf(hi - span, span))
		var st := centre + fposmod(other - centre, period) + period * float(randi_range(-jitter, jitter))
		while st > hi:
			st -= period
		while st < 0.0:
			st += period
		return st

	## Adds `frames` samples to out (gain ramps from g0 to g1, rate from r0 to r1).
	func mix(out: PackedFloat32Array, frames: int, target: float, r0: float, r1: float, g0: float, g1: float) -> void:
		if buf.size() < int(grain) + 8:
			return
		var inv := 1.0 / float(frames)
		var inv_grain := 1.0 / grain
		for i in frames:
			var f := float(i) * inv
			var rate := lerpf(r0, r1, f)
			age_a += rate * inv_grain
			if age_a >= 1.0:
				age_a -= 1.0
				pos_a = _start(target, pos_b)
			var age_b := age_a + 0.5
			if age_b >= 1.0:
				age_b -= 1.0
			if age_b < rate * inv_grain:
				pos_b = _start(target, pos_a)
			var sw := sin(PI * age_a)
			var wa := sw * sw
			var ia := int(pos_a)
			var fa := pos_a - float(ia)
			var va := buf[ia] + (buf[ia + 1] - buf[ia]) * fa
			var ib := int(pos_b)
			var fb := pos_b - float(ib)
			var vb := buf[ib] + (buf[ib + 1] - buf[ib]) * fb
			out[i] += (va * wa + vb * (1.0 - wa)) * lerpf(g0, g1, f)
			pos_a += rate
			pos_b += rate

const VOICES := {
	"i6": {
		"cyl": 6, "pattern": [1.0, 0.94, 0.98, 0.95, 1.0, 0.93], "timing": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
		"body": 170.0, "body_q": 1.4, "high": 1250.0, "high_q": 2.5, "decay": 0.28, "grit": 0.35,
		"tone": 0.42, "bass": 0.9, "rasp": 1.0, "click": 0.25, "drive": 1.2, "hard": 0.0,
		"whine": 0.0, "crackle": 2.5, "turbo": 1.0, "bov": 1.0, "gain": 1.0, "upshift_bang": 0.0,
	},
	"v8": {
		"cyl": 8, "pattern": [1.0, 0.62, 0.9, 0.7, 0.96, 0.58, 0.86, 0.74],
		"timing": [1.06, 0.94, 1.03, 0.97, 1.05, 0.95, 1.02, 0.98],
		"body": 95.0, "body_q": 1.1, "high": 620.0, "high_q": 1.8, "decay": 0.42, "grit": 0.5,
		"tone": 0.36, "bass": 1.6, "rasp": 0.55, "click": 0.3, "drive": 1.5, "hard": 0.0,
		"whine": 0.0, "crackle": 8.0, "turbo": 0.15, "bov": 0.0, "gain": 1.05, "upshift_bang": 0.35,
	},
	"v8race": {
		"cyl": 8, "pattern": [1.0, 0.86, 0.97, 0.9, 1.0, 0.84, 0.95, 0.9], "timing": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
		"body": 210.0, "body_q": 1.3, "high": 1500.0, "high_q": 2.0, "decay": 0.22, "grit": 0.6,
		"tone": 0.3, "bass": 0.8, "rasp": 1.5, "click": 0.35, "drive": 2.1, "hard": 0.35,
		"whine": 1.0, "crackle": 12.0, "turbo": 0.15, "bov": 0.0, "gain": 0.95, "upshift_bang": 1.0,
	},
}

var car          # car.gd (or anything exposing the same state, see render())
var engine_type := "i6"
var positional := false

var player: Node
var playback: AudioStreamGeneratorPlayback

# voice parameters
var _cyl := 6
var _pattern := PackedFloat32Array()
var _timing := PackedFloat32Array()
var _decay := 0.28
var _grit := 0.35
var _tone := 0.42
var _bass := 0.9
var _rasp := 1.0
var _click := 0.25
var _drive := 1.2
var _hard := 0.0
var _whine := 0.0
var _crackle := 2.5
var _turbo_level := 1.0
var _bov_level := 1.0
var _gain := 1.0
var _upshift_bang := 0.0
var _bcoef := PackedFloat32Array([0, 0, 0, 0])   # body resonance biquad (b0, b2, a1, a2)
var _hcoef := PackedFloat32Array([0, 0, 0, 0])   # high resonance biquad

# engine state
var _ph_fire := 0.0
var _ph_tone := 0.0
var _fire_k := 0
var _jit := 1.0
var _pulse := 0.0
var _bx1 := 0.0
var _bx2 := 0.0
var _by1 := 0.0
var _by2 := 0.0
var _hx1 := 0.0
var _hx2 := 0.0
var _hy1 := 0.0
var _hy2 := 0.0
var _ph_cut := 0.0
var _ph_whine := 0.0
var _shift_dip := 0.0
var _lp_noise := 0.0

# turbo / blow-off
var _ph_turbo := 0.0
var _ph_turbo2 := 0.0
var _lp_whoosh := 0.0
var _bov_env := 0.0
var _bov_t := 1.0
var _bov_amount := 0.0
var _bov_c := PackedFloat32Array([0, 0, 0, 0])
var _vx1 := 0.0
var _vx2 := 0.0
var _vy1 := 0.0
var _vy2 := 0.0
var _lp_bov := 0.0

# sampled voice (R34)
var _sampled := false
var _g_on: Granular
var _g_off: Granular
var _g_spool: Granular
var _idle_buf := PackedFloat32Array()
var _idle_pos := 0.0
var _on_f := PackedFloat32Array()
var _off_f := PackedFloat32Array()
var _spool_f := PackedFloat32Array()
var _lifts: Array = []
var _lift_slots: Array = [[-1, 0.0, 0.0, 1.0], [-1, 0.0, 0.0, 1.0]]   # [sample, pos, gain, rate]
var _last_lift := -1
var _load_s := 0.0
var _eng_block := PackedFloat32Array()

# pops, crackle, impacts
var _pop_env := 0.0
var _pops_left := 0
var _pop_gap := 0.0
var _lp_pop := 0.0
var _crk_env := 0.0
var _lp_crk := 0.0
var _impact_env := 0.0
var _impact_amount := 0.0
var _ph_thump := 0.0

# misc
var _lp_wind := 0.0
var _lp_out := 0.0
var _lp_nitro := 0.0
var _lp_scrub := 0.0
var _sq_low1 := 0.0
var _sq_band1 := 0.0
var _sq_low2 := 0.0
var _sq_band2 := 0.0
var _sq_env := 0.0
var _sq_pitch := 0.0
var _rpm := 900.0
var _thr := 0.0
var _boost := 0.0
var _slip := 0.0
var _speed := 0.0


func _ready() -> void:
	if car:
		engine_type = str(Game.get_car(str(car.car_id)).get("engine", "i6"))
		setup_voice(engine_type)
		if str(car.car_id) == "r34":
			setup_samples()
		_rpm = car.idle_rpm
		car.shifted.connect(_on_shift)
		car.blow_off.connect(_on_blow_off)
		car.backfire.connect(_on_backfire)
		car.wall_hit.connect(_on_hit)
	Game.settings_changed.connect(_on_settings_changed)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	var vol := float(Game.settings.get("engine_volume", 1.0))
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = gen
		p3.unit_size = 10.0
		p3.max_distance = 160.0
		p3.volume_db = linear_to_db(maxf(vol, 0.001)) - 2.0
		player = p3
		add_child(p3)
		p3.play()
		playback = p3.get_stream_playback()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = gen
		p.volume_db = linear_to_db(maxf(vol, 0.001)) - 5.0
		player = p
		add_child(p)
		p.play()
		playback = p.get_stream_playback()


func setup_voice(engine: String) -> void:
	var v: Dictionary = VOICES.get(engine, VOICES["i6"])
	_cyl = int(v["cyl"])
	_pattern = PackedFloat32Array(v["pattern"])
	_timing = PackedFloat32Array(v["timing"])
	_decay = float(v["decay"])
	_grit = float(v["grit"])
	_tone = float(v["tone"])
	_bass = float(v["bass"])
	_rasp = float(v["rasp"])
	_click = float(v["click"])
	_drive = float(v["drive"])
	_hard = float(v["hard"])
	_whine = float(v["whine"])
	_crackle = float(v["crackle"])
	_turbo_level = float(v["turbo"])
	_bov_level = float(v["bov"])
	_gain = float(v["gain"])
	_upshift_bang = float(v["upshift_bang"])
	_bcoef = _bandpass(float(v["body"]), float(v["body_q"]))
	_hcoef = _bandpass(float(v["high"]), float(v["high_q"]))


## Loads the R34 recordings; falls back to the synthesized voice when they are missing.
func setup_samples() -> bool:
	var on := _load_sample("r34_engine_on")
	var off := _load_sample("r34_engine_off")
	var idle := _load_sample("r34_idle")
	var spool := _load_sample("r34_turbo_spool")
	if on.size() < 4096 or off.size() < 4096 or idle.size() < 4096:
		push_warning("R34 engine samples missing – using the synthesized engine")
		return false
	var period := MIX_RATE / R34Data.F_REF
	_g_on = Granular.new(on, period, 4.0, 6)
	_g_off = Granular.new(off, period, 4.0, 6)
	_idle_buf = idle
	_on_f = PackedFloat32Array(R34Data.ON_F)
	_off_f = PackedFloat32Array(R34Data.OFF_F)
	if spool.size() > 4096:
		_g_spool = Granular.new(spool, MIX_RATE / R34Data.F_REF_TURBO, 60.0, 40)
		_spool_f = PackedFloat32Array(R34Data.SPOOL_F)
	_lifts.clear()
	for k in R34Data.LIFT_COUNT:
		var l := _load_sample("r34_turbo_lift_%d" % (k + 1))
		if l.size() > 0:
			_lifts.append(l)
	_sampled = true
	return true


static func _load_sample(sample_name: String) -> PackedFloat32Array:
	if not _sample_cache.has(sample_name):
		var bytes := FileAccess.get_file_as_bytes(SAMPLE_DIR + sample_name + ".bin")
		_sample_cache[sample_name] = bytes.to_float32_array()
	return _sample_cache[sample_name]


## Buffer position (in samples) where the tracked line frequency of a table equals `freq`.
static func _pos_for(table: PackedFloat32Array, freq: float) -> float:
	var n := table.size()
	if n == 0:
		return 0.0
	var ascending := table[n - 1] >= table[0]
	var lo := 0
	var hi := n - 1
	if ascending:
		if freq <= table[0]:
			return 0.0
		if freq >= table[n - 1]:
			return float(n - 1) * R34Data.TABLE_STEP
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if table[mid] < freq:
				lo = mid
			else:
				hi = mid
	else:
		if freq >= table[0]:
			return 0.0
		if freq <= table[n - 1]:
			return float(n - 1) * R34Data.TABLE_STEP
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if table[mid] > freq:
				lo = mid
			else:
				hi = mid
	var span := table[hi] - table[lo]
	var t := 0.0 if absf(span) < 1e-6 else (freq - table[lo]) / span
	return (float(lo) + clampf(t, 0.0, 1.0)) * R34Data.TABLE_STEP


## Engine (idle loop + on/off-load grains) and turbo layers of the sampled voice for one buffer.
func _render_sampled(frames: int, r0: float, r1: float, thr: float, boost0: float, boost1: float) -> PackedFloat32Array:
	if _eng_block.size() != frames:
		_eng_block.resize(frames)
	_eng_block.fill(0.0)
	var order: float = R34Data.ORDER
	var f0 := r0 * order / 60.0
	var f1 := r1 * order / 60.0
	var rate0 := f0 / R34Data.F_REF
	var rate1 := f1 / R34Data.F_REF
	var load0 := _load_s
	_load_s += (clampf(thr * 1.15, 0.0, 1.0) - _load_s) * 0.35
	var load1 := _load_s
	# idle loop weight: only near idle and without load
	var wi0 := (1.0 - smoothstep(1.04, 1.45, f0 / R34Data.IDLE_LINE)) * (1.0 - load0 * 0.8)
	var wi1 := (1.0 - smoothstep(1.04, 1.45, f1 / R34Data.IDLE_LINE)) * (1.0 - load1 * 0.8)
	var idle_gain := 0.5
	var fm := (f0 + f1) * 0.5
	var g_on0 := sqrt(load0) * (1.0 - wi0)
	var g_on1 := sqrt(load1) * (1.0 - wi1)
	var g_off0 := sqrt(1.0 - load0) * (1.0 - wi0) * 0.7
	var g_off1 := sqrt(1.0 - load1) * (1.0 - wi1) * 0.7
	if maxf(g_on0, g_on1) > 0.001:
		_g_on.mix(_eng_block, frames, _pos_for(_on_f, fm), rate0, rate1, g_on0, g_on1)
	if maxf(g_off0, g_off1) > 0.001:
		_g_off.mix(_eng_block, frames, _pos_for(_off_f, fm), rate0, rate1, g_off0, g_off1)
	if maxf(wi0, wi1) > 0.001:
		var n := _idle_buf.size()
		var inv := 1.0 / float(frames)
		for i in frames:
			var f := float(i) * inv
			var ii := int(_idle_pos)
			var fr := _idle_pos - float(ii)
			var v := _idle_buf[ii] + (_idle_buf[(ii + 1) % n] - _idle_buf[ii]) * fr
			_eng_block[i] += v * lerpf(wi0, wi1, f) * idle_gain
			_idle_pos += lerpf(f0, f1, f) / R34Data.IDLE_LINE
			if _idle_pos >= float(n):
				_idle_pos -= float(n)
	# turbo whistle follows the boost
	if _g_spool and maxf(boost0, boost1) > 0.02:
		var fw0 := 3000.0 + 3900.0 * boost0
		var fw1 := 3000.0 + 3900.0 * boost1
		var ga := pow(boost0, 1.3) * (0.35 + 0.65 * load0) * SPOOL_GAIN
		var gb := pow(boost1, 1.3) * (0.35 + 0.65 * load1) * SPOOL_GAIN
		_g_spool.mix(_eng_block, frames, _pos_for(_spool_f, (fw0 + fw1) * 0.5), fw0 / R34Data.F_REF_TURBO,
			fw1 / R34Data.F_REF_TURBO, ga, gb)
	return _eng_block


## RBJ band-pass biquad (0 dB peak gain): returns normalized [b0, b2, a1, a2] (b1 = 0, b2 = -b0).
static func _bandpass(freq: float, q: float) -> PackedFloat32Array:
	var w := TAU * freq / MIX_RATE
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	return PackedFloat32Array([alpha / a0, -alpha / a0, -2.0 * cos(w) / a0, (1.0 - alpha) / a0])


func _on_shift(up: bool, _boost_val: float) -> void:
	_shift_dip = 1.0
	if up and _upshift_bang > 0.0 and car.throttle > 0.5:
		_pop_env = _upshift_bang
		_pops_left = 1 if _upshift_bang >= 1.0 else 0
		_pop_gap = 0.045


func _on_blow_off(amount: float) -> void:
	if _sampled and _lifts.size() > 0:
		var k := randi() % _lifts.size()
		if k == _last_lift and _lifts.size() > 1:
			k = (k + 1) % _lifts.size()
		_last_lift = k
		# reuse the slot that has played longest
		var slot: Array = _lift_slots[0] if float(_lift_slots[0][1]) >= float(_lift_slots[1][1]) or int(_lift_slots[0][0]) < 0 else _lift_slots[1]
		if int(_lift_slots[0][0]) < 0:
			slot = _lift_slots[0]
		elif int(_lift_slots[1][0]) < 0:
			slot = _lift_slots[1]
		slot[0] = k
		slot[1] = 0.0
		slot[2] = clampf(0.35 + 0.75 * amount, 0.4, 1.0) * LIFT_GAIN
		slot[3] = randf_range(0.96, 1.04)
		return
	if _bov_level <= 0.0:
		return
	_bov_env = 1.0
	_bov_t = 0.0
	_bov_amount = clampf(amount, 0.35, 1.0)


func _on_backfire() -> void:
	_pops_left = randi_range(1, 3) if car.line_lock else randi_range(2, 4)
	_pop_gap = 0.0


func _on_hit(strength: float) -> void:
	_impact_env = 1.0
	_impact_amount = clampf(strength / 15.0, 0.2, 1.0)


func _process(_delta: float) -> void:
	if playback == null or car == null:
		return
	var frames := playback.get_frames_available()
	if frames <= 0:
		return
	playback.push_buffer(render(frames))


## Synthesizes `frames` stereo samples from the car's current state.
func render(frames: int) -> PackedVector2Array:
	var buf := PackedVector2Array()
	buf.resize(frames)
	var redline: float = car.redline
	var idle: float = car.idle_rpm
	var t_rpm: float = car.rpm
	var t_thr: float = car.throttle
	var t_boost: float = car.boost
	var t_slip: float = clampf(float(car.total_slip), 0.0, 40.0)
	var t_speed: float = car.speed
	var limiter: bool = t_rpm > redline * 0.975 and t_thr > 0.3
	var launch: bool = car.line_lock or (car.controls_locked and t_thr > 0.4)
	var nitro: bool = car.nitro_active
	var turbo_on: bool = float(car.turbo_gain) > 0.0 and _turbo_level > 0.0
	var off_road: bool = car.surface_name != "asphalt" and car.surface_name != "curb"
	var overrun: bool = t_thr < 0.08 and t_rpm > redline * 0.42 and t_speed > 6.0
	var dt := 1.0 / MIX_RATE
	var r0 := _rpm
	var th0 := _thr
	var b0 := _boost
	var s0 := _slip
	var sp0 := _speed
	var inv := 1.0 / float(frames)
	# per-buffer constants
	var fire_mid := maxf(t_rpm, 300.0) / 60.0 * float(_cyl) * 0.5
	var pulse_decay := exp(-dt * fire_mid / _decay)
	var bov_decay := exp(-dt / 0.3)
	var pop_decay := exp(-dt / 0.03)
	var crk_decay := exp(-dt / 0.012)
	var imp_decay := exp(-dt / 0.18)
	var dip_decay := exp(-dt / 0.12)
	var cb0 := _bcoef[0]
	var cb2 := _bcoef[1]
	var ca1 := _bcoef[2]
	var ca2 := _bcoef[3]
	var hb0 := _hcoef[0]
	var hb2 := _hcoef[1]
	var ha1 := _hcoef[2]
	var ha2 := _hcoef[3]
	var idle_rough := clampf(1.0 - (t_rpm - idle) / 1500.0, 0.0, 1.0)
	var crackle_rate := _crackle * (1.0 if overrun else 0.0)
	# tyre squeal parameters change slowly: compute the filter coefficients once per buffer
	var sq_target := clampf((t_slip - 3.0) / 13.0, 0.0, 1.0)
	if off_road:
		sq_target = 0.0
	_sq_pitch = clampf(_sq_pitch + randf_range(-0.12, 0.12), -1.0, 1.0)
	var fc1 := 780.0 + 160.0 * _sq_pitch + t_speed * 2.5
	var f1 := 2.0 * sin(PI * fc1 / MIX_RATE)
	var f2 := 2.0 * sin(PI * fc1 * 1.58 / MIX_RATE)
	var q := 0.1
	var sq_attack := 1.0 - exp(-dt / 0.06)
	var sq_release := 1.0 - exp(-dt / 0.22)
	var eblock := PackedFloat32Array()
	if _sampled:
		eblock = _render_sampled(frames, r0, t_rpm, t_thr, b0, t_boost)
	for i in frames:
		var f := float(i) * inv
		var rpm := lerpf(r0, t_rpm, f)
		var thr := lerpf(th0, t_thr, f)
		var boost := lerpf(b0, t_boost, f)
		var slip := lerpf(s0, t_slip, f)
		var spd := lerpf(sp0, t_speed, f)
		var n := randf() * 2.0 - 1.0
		var load := 0.45 + 0.55 * thr
		if overrun:
			load = 0.25

		var eng := 0.0
		if _sampled:
			eng = eblock[i] * ENGINE_SAMPLE_GAIN / 0.42
		else:
			# --- engine: exhaust pulses (one per firing) ---
			var fire := rpm / 60.0 * float(_cyl) * 0.5
			_ph_fire += fire * dt / _jit
			if _ph_fire >= 1.0:
				_ph_fire -= 1.0
				_fire_k = (_fire_k + 1) % _cyl
				_jit = _timing[_fire_k] * (1.0 + randf_range(-0.015, 0.015) * idle_rough)
				_pulse = _pattern[_fire_k] * load * (1.0 + randf_range(-0.07, 0.07))
			var ex := _pulse * (1.0 + n * _grit)
			_pulse *= pulse_decay
			var yb := cb0 * ex + cb2 * _bx2 - ca1 * _by1 - ca2 * _by2
			_bx2 = _bx1
			_bx1 = ex
			_by2 = _by1
			_by1 = yb
			var yh := hb0 * ex + hb2 * _hx2 - ha1 * _hy1 - ha2 * _hy2
			_hx2 = _hx1
			_hx1 = ex
			_hy2 = _hy1
			_hy1 = yh
			# engine-order harmonics for a clear pitch
			_ph_tone = fposmod(_ph_tone + fire * dt, 1.0)
			var x := _ph_tone * TAU
			var tone := (sin(x) + 0.5 * sin(2.0 * x + 0.4) + 0.22 * _rasp * sin(3.0 * x + 1.3)) * load
			_lp_noise += (n - _lp_noise) * 0.35
			eng = tone * _tone + yb * 3.0 * _bass + yh * 3.0 * _rasp + ex * _click + _lp_noise * _pulse * 0.4
			eng = tanh(eng * _drive * (0.85 + 0.6 * thr))
			if _hard > 0.0:
				eng = lerpf(eng, clampf(eng * 2.5, -0.8, 0.8), _hard)
		var eng_amp := 1.0 if _sampled else 0.42 + 0.36 * thr + 0.22 * (rpm / redline)
		if launch:
			# two-step ignition cut: irregular stutter around the launch rpm
			_ph_cut = fposmod(_ph_cut + (11.0 + 3.0 * sin(float(i) * 0.0007)) * dt, 1.0)
			var gate := 0.5 + 0.5 * sin(_ph_cut * TAU)
			eng_amp *= 0.35 + 0.65 * gate * gate
		elif limiter:
			eng_amp *= 0.85 + 0.15 * sin(float(i) * TAU * 17.0 / MIX_RATE)
		eng_amp *= 1.0 - _shift_dip * 0.55
		_shift_dip *= dip_decay
		var out := eng * eng_amp * 0.42 * _gain

		# --- straight-cut gearbox whine (race car) ---
		if _whine > 0.0 and spd > 1.0:
			_ph_whine = fposmod(_ph_whine + rpm / 60.0 * 19.0 * dt, 1.0)
			var wx := _ph_whine * TAU
			out += (sin(wx) + 0.3 * sin(2.0 * wx)) * _whine * (0.012 + 0.022 * thr) * clampf(spd / 12.0, 0.0, 1.0)

		# --- turbo whistle + intake whoosh (loud on the R34 only) ---
		if turbo_on and not _sampled:
			var tf := 2200.0 + 6000.0 * boost
			_ph_turbo = fposmod(_ph_turbo + tf * dt, 1.0)
			_ph_turbo2 = fposmod(_ph_turbo2 + tf * 1.06 * dt, 1.0)
			var bst := pow(boost, 1.5)
			out += (sin(_ph_turbo * TAU) + 0.6 * sin(_ph_turbo2 * TAU)) * bst * 0.05 * _turbo_level
			_lp_whoosh += (n - _lp_whoosh) * 0.3
			out += (n - _lp_whoosh) * boost * thr * 0.035 * _turbo_level

		# --- blow-off valve: bright "pssst" that darkens, with a short flutter tail ---
		if _bov_env > 0.002:
			if (i & 31) == 0:
				_bov_c = _bandpass(1700.0 + 2600.0 * exp(-_bov_t / 0.1), 0.9)
			var vy := _bov_c[0] * n + _bov_c[1] * _vx2 - _bov_c[2] * _vy1 - _bov_c[3] * _vy2
			_vx2 = _vx1
			_vx1 = n
			_vy2 = _vy1
			_vy1 = vy
			_lp_bov += (n - _lp_bov) * 0.5
			var attack := minf(_bov_t / 0.006, 1.0)
			var amp := _bov_env * attack * _bov_amount * _bov_level
			if _bov_t > 0.12:
				var fl := 0.5 + 0.5 * sin((_bov_t - 0.12) * TAU * 17.0)
				amp *= 1.0 - 0.45 * fl * _bov_amount
			out += (vy * 1.25 + (n - _lp_bov) * 0.22) * amp * 0.7
			_bov_env *= bov_decay
			_bov_t += dt

		# --- recorded lift-off: blow-off "pssst" + compressor flutter + falling whistle ---
		if _sampled:
			for slot in _lift_slots:
				var li: int = slot[0]
				if li < 0:
					continue
				var lb: PackedFloat32Array = _lifts[li]
				var lp: float = slot[1]
				var k := int(lp)
				if k + 1 >= lb.size():
					slot[0] = -1
					continue
				out += (lb[k] + (lb[k + 1] - lb[k]) * (lp - float(k))) * float(slot[2])
				slot[1] = lp + float(slot[3])

		# --- nitro hiss ---
		if nitro:
			_lp_nitro += (n - _lp_nitro) * 0.6
			out += (n - _lp_nitro) * 0.09

		# --- exhaust pops (backfire, upshift bang) ---
		if _pops_left > 0:
			_pop_gap -= dt
			if _pop_gap <= 0.0:
				_pop_env = 1.0
				_pops_left -= 1
				_pop_gap = randf_range(0.05, 0.13)
		if _pop_env > 0.002:
			_lp_pop += (n - _lp_pop) * 0.25
			out += _lp_pop * _pop_env * 1.3
			_pop_env *= pop_decay
		# --- overrun crackle ---
		if crackle_rate > 0.0 and randf() < crackle_rate * dt:
			_crk_env = randf_range(0.4, 1.0)
		if _crk_env > 0.002:
			_lp_crk += (n - _lp_crk) * 0.45
			out += _lp_crk * _crk_env * 0.7
			_crk_env *= crk_decay

		# --- tyre squeal: resonant band-pass noise with smooth envelope ---
		_sq_env += (sq_target - _sq_env) * (sq_attack if sq_target > _sq_env else sq_release)
		if _sq_env > 0.001:
			_sq_low1 += f1 * _sq_band1
			var high1 := n - _sq_low1 - q * _sq_band1
			_sq_band1 += f1 * high1
			_sq_low2 += f2 * _sq_band2
			var high2 := n - _sq_low2 - q * _sq_band2
			_sq_band2 += f2 * high2
			var squeal := _sq_band1 * 0.65 + _sq_band2 * 0.35
			out += squeal * _sq_env * 0.11
			_lp_scrub += (n - _lp_scrub) * 0.06
			out += _lp_scrub * _sq_env * 0.12
		# off-road rumble
		if off_road and slip > 1.0:
			_lp_scrub += (n - _lp_scrub) * 0.05
			out += _lp_scrub * clampf(slip / 10.0, 0.0, 1.0) * 0.35

		# --- wind ---
		_lp_wind += (n - _lp_wind) * 0.05
		out += _lp_wind * clampf(spd / 70.0, 0.0, 1.0) * 0.12

		# --- impact thump ---
		if _impact_env > 0.002:
			_ph_thump = fposmod(_ph_thump + 55.0 * dt, 1.0)
			out += (sin(_ph_thump * TAU) * 0.8 + n * 0.4) * _impact_env * _impact_amount * 0.9
			_impact_env *= imp_decay

		_lp_out += (out - _lp_out) * 0.85
		var s := tanh(_lp_out * 1.2) * 0.8
		buf[i] = Vector2(s, s)
	_rpm = t_rpm
	_thr = t_thr
	_boost = t_boost
	_slip = t_slip
	_speed = t_speed
	return buf


func _on_settings_changed() -> void:
	set_volume(float(Game.settings.get("engine_volume", 1.0)))


func set_volume(v: float) -> void:
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).volume_db = linear_to_db(maxf(v, 0.001)) - 5.0
	elif player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).volume_db = linear_to_db(maxf(v, 0.001)) - 2.0
