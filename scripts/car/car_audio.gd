extends Node
## Real-time synthesized car audio (no samples needed):
## engine harmonics per engine type (I6 / V8 cross-plane burble / high-revving race V8),
## turbo whistle & blow-off, launch-control two-step stutter with pops, nitro hiss,
## tyre squeal (resonant band-pass filtered noise), wind and impacts.

const MIX_RATE := 22050.0

var car          # car.gd
var positional := false

var player: Node
var playback: AudioStreamGeneratorPlayback

var _ph_engine := 0.0
var _ph_turbo := 0.0
var _ph_flutter := 0.0
var _ph_thump := 0.0
var _ph_cut := 0.0
var _bov_env := 0.0
var _bov_amount := 0.0
var _flutter := false
var _pop_env := 0.0
var _pops_left := 0
var _pop_gap := 0.0
var _impact_env := 0.0
var _impact_amount := 0.0
var _shift_dip := 0.0
var _lp_noise := 0.0
var _lp_bov := 0.0
var _lp_pop := 0.0
var _lp_wind := 0.0
var _lp_out := 0.0
var _lp_nitro := 0.0
var _lp_scrub := 0.0
# tyre squeal: two state-variable band-pass filters
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
var _order := 3.0
var _burble := 0.35
var _rasp := 0.5


func _ready() -> void:
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
	if car:
		_rpm = car.idle_rpm
		var engine := str(Game.get_car(car.car_id).get("engine", "i6"))
		match engine:
			"v8":
				_order = 4.0
				_burble = 0.8
				_rasp = 0.35
			"v8race":
				_order = 4.0
				_burble = 0.25
				_rasp = 0.9
			_:
				_order = 3.0
				_burble = 0.35
				_rasp = 0.55
		_flutter = false
		car.shifted.connect(_on_shift)
		car.blow_off.connect(_on_blow_off)
		car.backfire.connect(_on_backfire)
		car.wall_hit.connect(_on_hit)


func _on_shift(_up: bool, _boost_val: float) -> void:
	_shift_dip = 1.0


func _on_blow_off(amount: float) -> void:
	_bov_env = 1.0
	_bov_amount = clampf(amount, 0.3, 1.0)


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
	var redline: float = car.redline
	var t_rpm: float = car.rpm
	var t_thr: float = car.throttle
	var t_boost: float = car.boost
	var t_slip: float = clampf(float(car.total_slip), 0.0, 40.0)
	var t_speed: float = car.speed
	var limiter: bool = t_rpm > redline * 0.975 and t_thr > 0.3
	var launch: bool = car.line_lock or (car.controls_locked and t_thr > 0.4)
	var nitro: bool = car.nitro_active
	var turbo_gain: float = car.turbo_gain
	var off_road: bool = car.surface_name != "asphalt" and car.surface_name != "curb"
	var dt := 1.0 / MIX_RATE
	var buf := PackedVector2Array()
	buf.resize(frames)
	var r0 := _rpm
	var th0 := _thr
	var b0 := _boost
	var s0 := _slip
	var sp0 := _speed
	var inv := 1.0 / float(frames)
	var bov_decay := exp(-dt / 0.26)
	var pop_decay := exp(-dt / 0.03)
	var imp_decay := exp(-dt / 0.18)
	var dip_decay := exp(-dt / 0.12)
	# tyre squeal parameters change slowly: compute the filter coefficients once per buffer
	var sq_target := clampf((t_slip - 3.0) / 13.0, 0.0, 1.0)
	if off_road:
		sq_target = 0.0
	_sq_pitch = clampf(_sq_pitch + randf_range(-0.12, 0.12), -1.0, 1.0)
	var fc1 := 780.0 + 160.0 * _sq_pitch + t_speed * 2.5
	var fc2 := fc1 * 1.58
	var f1 := 2.0 * sin(PI * fc1 / MIX_RATE)
	var f2 := 2.0 * sin(PI * fc2 / MIX_RATE)
	var q := 0.1
	var sq_attack := 1.0 - exp(-dt / 0.06)
	var sq_release := 1.0 - exp(-dt / 0.22)
	for i in frames:
		var f := float(i) * inv
		var rpm := lerpf(r0, t_rpm, f)
		var thr := lerpf(th0, t_thr, f)
		var boost := lerpf(b0, t_boost, f)
		var slip := lerpf(s0, t_slip, f)
		var spd := lerpf(sp0, t_speed, f)
		var n := randf() * 2.0 - 1.0

		# --- engine ---
		var f0 := rpm / 60.0 * _order
		_ph_engine = fposmod(_ph_engine + f0 * dt, 2.0)
		var x := _ph_engine * TAU
		var eng := sin(x) + 0.55 * sin(2.0 * x + 0.4) + 0.3 * sin(3.0 * x + 1.3) * _rasp + 0.2 * sin(4.0 * x + 0.2) * _rasp
		eng += _burble * (0.6 * sin(0.5 * x) + 0.25 * sin(0.25 * x + 0.7))
		var pulse := maxf(sin(x), 0.0)
		pulse = pulse * pulse * pulse
		_lp_noise += (n - _lp_noise) * 0.35
		eng += _lp_noise * pulse * (0.5 + 1.2 * thr)
		eng = tanh(eng * (0.55 + thr * 0.9))
		var eng_amp := 0.3 + 0.45 * thr + 0.25 * (rpm / redline)
		if launch:
			# two-step ignition cut: irregular stutter around the launch rpm
			_ph_cut = fposmod(_ph_cut + (11.0 + 3.0 * sin(float(i) * 0.0007)) * dt, 1.0)
			var gate := 0.5 + 0.5 * sin(_ph_cut * TAU)
			eng_amp *= 0.35 + 0.65 * gate * gate
		elif limiter:
			eng_amp *= 0.85 + 0.15 * sin(float(i) * TAU * 17.0 / MIX_RATE)
		eng_amp *= 1.0 - _shift_dip * 0.55
		_shift_dip *= dip_decay
		var out := eng * eng_amp * 0.42

		# --- turbo whistle + spool hiss ---
		if turbo_gain > 0.0:
			_ph_turbo = fposmod(_ph_turbo + (1700.0 + 5200.0 * boost) * dt, 1.0)
			out += sin(_ph_turbo * TAU) * pow(boost, 1.6) * 0.045
			out += n * boost * thr * 0.02

		# --- nitro hiss ---
		if nitro:
			_lp_nitro += (n - _lp_nitro) * 0.6
			out += (n - _lp_nitro) * 0.09

		# --- blow-off valve ---
		if _bov_env > 0.002:
			_lp_bov += (n - _lp_bov) * 0.55
			var hiss := n - _lp_bov * 0.7
			var amp := _bov_env * _bov_amount * 0.5
			if _flutter:
				_ph_flutter = fposmod(_ph_flutter + 21.0 * dt, 1.0)
				amp *= 0.35 + 0.65 * (1.0 if _ph_flutter < 0.5 else 0.15)
			out += hiss * amp
			_bov_env *= bov_decay

		# --- exhaust pops ---
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
	playback.push_buffer(buf)


func set_volume(v: float) -> void:
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).volume_db = linear_to_db(maxf(v, 0.001)) - 5.0
	elif player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).volume_db = linear_to_db(maxf(v, 0.001)) - 2.0
