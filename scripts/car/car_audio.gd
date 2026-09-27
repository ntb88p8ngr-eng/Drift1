extends Node
## Real-time synthesized car audio (no samples needed):
## engine harmonics + combustion noise, turbo whistle & spool, blow-off valve "pssh"/flutter on gear
## changes, exhaust pops, tyre squeal, wind and impacts.

const MIX_RATE := 22050.0

var car          # car.gd
var positional := false

var player: Node
var playback: AudioStreamGeneratorPlayback

var _ph_engine := 0.0
var _ph_turbo := 0.0
var _ph_squeal := 0.0
var _ph_squeal_mod := 0.0
var _ph_flutter := 0.0
var _ph_thump := 0.0
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
var _lp_squeal := 0.0
var _lp_wind := 0.0
var _lp_out := 0.0
var _rpm := 900.0
var _thr := 0.0
var _boost := 0.0
var _slip := 0.0
var _speed := 0.0
var _harmonic_order := 3.0


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
		# 6-cylinder cars fire 3 times per revolution, 4-cylinders twice
		_harmonic_order = 2.0 if car.car_id in ["s15", "ae86"] else 3.0
		_flutter = car.car_id == "s15"
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
	_pops_left = randi_range(2, 4)
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
	var limiter: bool = float(car.limiter_timer) > 0.0 if not car.is_remote else t_rpm > redline * 0.985
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
	var pop_decay := exp(-dt / 0.025)
	var imp_decay := exp(-dt / 0.18)
	var dip_decay := exp(-dt / 0.12)
	for i in frames:
		var f := float(i) * inv
		var rpm := lerpf(r0, t_rpm, f)
		var thr := lerpf(th0, t_thr, f)
		var boost := lerpf(b0, t_boost, f)
		var slip := lerpf(s0, t_slip, f)
		var spd := lerpf(sp0, t_speed, f)
		var n := randf() * 2.0 - 1.0

		# --- engine ---
		var f0 := rpm / 60.0 * _harmonic_order
		_ph_engine = fposmod(_ph_engine + f0 * dt, 2.0)
		var x := _ph_engine * TAU
		var eng := sin(x) + 0.6 * sin(2.0 * x + 0.4) + 0.38 * sin(3.0 * x + 1.3) + 0.22 * sin(4.0 * x + 0.2) + 0.35 * sin(0.5 * x)
		var pulse := maxf(sin(x), 0.0)
		pulse = pulse * pulse * pulse
		_lp_noise += (n - _lp_noise) * 0.35
		eng += _lp_noise * pulse * (0.5 + 1.2 * thr)
		eng = tanh(eng * (0.55 + thr * 0.9))
		var eng_amp := 0.3 + 0.45 * thr + 0.25 * (rpm / redline)
		if limiter:
			eng_amp *= 0.55 + 0.45 * signf(sin(float(i) * 0.02))
		eng_amp *= 1.0 - _shift_dip * 0.6
		_shift_dip *= dip_decay
		var out := eng * eng_amp * 0.42

		# --- turbo whistle + spool hiss ---
		if turbo_gain > 0.0:
			_ph_turbo = fposmod(_ph_turbo + (1700.0 + 5200.0 * boost) * dt, 1.0)
			out += sin(_ph_turbo * TAU) * pow(boost, 1.6) * 0.05
			out += n * boost * thr * 0.025

		# --- blow-off valve ---
		if _bov_env > 0.002:
			_lp_bov += (n - _lp_bov) * 0.55
			var hiss := n - _lp_bov * 0.7
			var amp := _bov_env * _bov_amount * 0.55
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
			out += _lp_pop * _pop_env * 1.4
			_pop_env *= pop_decay

		# --- tyre squeal / off-road rumble ---
		var sq := clampf((slip - 2.5) / 14.0, 0.0, 1.0)
		if sq > 0.0:
			if off_road:
				_lp_squeal += (n - _lp_squeal) * 0.08
				out += _lp_squeal * sq * 0.5
			else:
				_ph_squeal_mod = fposmod(_ph_squeal_mod + 7.3 * dt, 1.0)
				var pitch := 950.0 + 180.0 * sin(_ph_squeal_mod * TAU) + spd * 3.0
				_ph_squeal = fposmod(_ph_squeal + pitch * dt, 1.0)
				_lp_squeal += (n - _lp_squeal) * 0.4
				var tone := sin(_ph_squeal * TAU) * 0.6 + sin(_ph_squeal * TAU * 2.01) * 0.25 + _lp_squeal * 0.5
				out += tone * sq * 0.16

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
