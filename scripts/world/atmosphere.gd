extends Node3D
## Time of day and weather.
## * The clock starts at the chosen time of day and (optionally) keeps running: the sun moves along
##   its path, the sky, fog and light blend through sunset, twilight and night, the moon takes over.
## * Weather: dry, steady rain or changing (showers come and go). Clouds build up before rain,
##   the road gets wet (darker, glossy, less grip) and puddles form that are extra slippery.
## * Rain drops and splashes follow the camera; the rain has its own sound.
## Everything is a deterministic function of the session time and a seed, so all players in an
## online race get the same weather.

const TexKit = preload("res://scripts/util/tex_kit.gd")

const START_HOURS := {"morning": 7.2, "day": 13.0, "dusk": 19.4, "night": 0.5}
const SUNRISE := 6.0
const SUNSET := 20.0
const MOON_ELEV := 38.0
const MOON_AZ := 150.0

## Sky/light key frames by sun elevation (degrees), interpolated linearly.
const KEYS := [
	{"e": -14.0, "zenith": Color(0.005, 0.008, 0.025), "horizon": Color(0.04, 0.05, 0.1), "ground": Color(0.01, 0.01, 0.015),
		"sun": Color(0.45, 0.55, 0.85), "cloud": Color(0.08, 0.09, 0.14), "shade": Color(0.02, 0.02, 0.04),
		"fog": Color(0.03, 0.04, 0.07), "fog_d": 0.0014, "ambient": 0.5, "exposure": 1.05, "stars": 1.0, "glow": 0.1},
	{"e": -4.0, "zenith": Color(0.04, 0.05, 0.18), "horizon": Color(0.42, 0.24, 0.3), "ground": Color(0.05, 0.04, 0.06),
		"sun": Color(0.9, 0.4, 0.3), "cloud": Color(0.42, 0.26, 0.36), "shade": Color(0.12, 0.1, 0.18),
		"fog": Color(0.25, 0.18, 0.25), "fog_d": 0.0013, "ambient": 0.5, "exposure": 1.05, "stars": 0.5, "glow": 0.25},
	{"e": 5.0, "zenith": Color(0.10, 0.10, 0.30), "horizon": Color(0.95, 0.45, 0.25), "ground": Color(0.12, 0.08, 0.1),
		"sun": Color(1.0, 0.55, 0.28), "cloud": Color(1.0, 0.62, 0.42), "shade": Color(0.35, 0.22, 0.35),
		"fog": Color(0.75, 0.45, 0.4), "fog_d": 0.0012, "ambient": 0.7, "exposure": 1.1, "stars": 0.12, "glow": 0.35},
	{"e": 18.0, "zenith": Color(0.16, 0.3, 0.6), "horizon": Color(0.8, 0.74, 0.7), "ground": Color(0.25, 0.23, 0.22),
		"sun": Color(1.0, 0.85, 0.66), "cloud": Color(1.0, 0.92, 0.84), "shade": Color(0.58, 0.58, 0.66),
		"fog": Color(0.78, 0.76, 0.76), "fog_d": 0.001, "ambient": 0.85, "exposure": 1.0, "stars": 0.0, "glow": 0.35},
	{"e": 55.0, "zenith": Color(0.12, 0.30, 0.66), "horizon": Color(0.62, 0.74, 0.88), "ground": Color(0.22, 0.22, 0.2),
		"sun": Color(1.0, 0.96, 0.88), "cloud": Color(1.0, 1.0, 1.0), "shade": Color(0.58, 0.62, 0.7),
		"fog": Color(0.66, 0.74, 0.86), "fog_d": 0.0009, "ambient": 0.9, "exposure": 1.0, "stars": 0.0, "glow": 0.35},
]

signal night_changed(n: float)

var hour := 19.4
var day_minutes := 0
var weather := "dry"
var weather_seed := 0
var quality := 2
var elapsed := 0.0
var rain := 0.0          # rain intensity 0..1
var clouds := 0.4        # cloud coverage 0..1
var wetness := 0.0       # road wetness 0..1 (lags behind the rain)
var night := 0.0         # 0 = day … 1 = night
var sun_elevation := 0.0
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var track                # track.gd (grip + puddles)
var materials_wet: Array = []   # ShaderMaterials with a "wetness" parameter

var _noise := FastNoiseLite.new()
var _rain_fx: GPUParticles3D
var _splash_fx: GPUParticles3D
var _rain_mat: StandardMaterial3D
var _rain_player: AudioStreamPlayer
var _rain_playback: AudioStreamGeneratorPlayback
# rain sound state: soft noise wash per channel, low rumble, soft drop patter
var _rs := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0.1, 0.5])   # wash L1 L2 R1 R2, rumble, drop low, drop band, drop f, pan
var _drop_env := 0.0
var _gust_ph := 0.0
var _last_night := -1.0
var _sun_dir := Vector3.UP
var _moon_dir := Vector3.UP


func setup(cfg: Dictionary, p_quality: int) -> void:
	quality = p_quality
	var tod := str(cfg.get("time_of_day", "dusk"))
	hour = float(START_HOURS.get(tod, 19.4))
	day_minutes = int(cfg.get("day_cycle", 0))
	weather = str(cfg.get("weather", "dry"))
	weather_seed = int(cfg.get("weather_seed", 1))
	_noise.seed = weather_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 2
	_moon_dir = _dir_from(MOON_ELEV, MOON_AZ)
	_build_environment()
	_build_rain()
	rain = _rain_at(0.0)
	wetness = rain * 0.9 if weather == "rain" else rain * 0.5
	clouds = _clouds_at(0.0)
	_apply(0.0)


func _build_environment() -> void:
	sky_mat = TexKit.sky_material()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	# the sky changes all the time (clock, clouds): real-time radiance updates
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = quality >= 2
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssr_enabled = quality >= 3
	env.ssr_max_steps = 48
	env.fog_enabled = true
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.2
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality >= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = [110.0, 150.0, 200.0, 300.0][clampi(quality, 0, 3)]
	sun.directional_shadow_blend_splits = quality >= 2
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)


# ---------------------------------------------------------------------------
# Clock & weather functions
# ---------------------------------------------------------------------------
static func _dir_from(elev_deg: float, az_deg: float) -> Vector3:
	var e := deg_to_rad(elev_deg)
	var a := deg_to_rad(az_deg)
	return Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e)).normalized()


func hour_at(t: float) -> float:
	if day_minutes <= 0:
		return hour
	return fposmod(hour + t / (float(day_minutes) * 60.0) * 24.0, 24.0)


## Sun elevation (degrees) and azimuth for an hour of the day.
static func sun_position(h: float) -> Vector2:
	var day_len := SUNSET - SUNRISE
	var elev: float
	if h >= SUNRISE and h <= SUNSET:
		elev = 62.0 * sin(PI * (h - SUNRISE) / day_len)
	else:
		var night_h := fposmod(h - SUNSET, 24.0)
		elev = -32.0 * sin(PI * night_h / (24.0 - day_len))
	var az := 70.0 + 220.0 * (fposmod(h - SUNRISE, 24.0) / day_len)
	return Vector2(elev, az)


func _rain_at(t: float) -> float:
	match weather:
		"rain":
			return 0.72 + 0.28 * (_noise.get_noise_1d(t / 35.0) * 0.5 + 0.5)
		"changing":
			var w := _noise.get_noise_1d(t / 140.0 + 17.0)
			var gust := 0.6 + 0.4 * (_noise.get_noise_1d(t / 22.0 + 51.0) * 0.5 + 0.5)
			return smoothstep(0.02, 0.3, w) * gust
	return 0.0


func _clouds_at(t: float) -> float:
	var base := 0.3 + 0.25 * (_noise.get_noise_1d(t / 180.0 + 99.0) * 0.5 + 0.5)
	# clouds build up about half a minute before the rain arrives
	var ahead := maxf(_rain_at(t), _rain_at(t + 35.0))
	return clampf(maxf(base, smoothstep(0.0, 0.35, ahead) * 0.97), 0.0, 1.0)


# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	elapsed += delta
	var target := _rain_at(elapsed)
	rain = move_toward(rain, target, delta * 0.2)
	clouds = move_toward(clouds, _clouds_at(elapsed), delta * 0.05)
	# the road gets wet quickly and dries slowly
	var rate := 1.0 / 25.0 if rain > wetness else 1.0 / 140.0
	wetness = clampf(wetness + (rain - wetness) * rate * delta * 4.0, 0.0, 1.0)
	if track:
		track.set_weather(wetness, smoothstep(0.35, 0.85, wetness), rain)


func _process(delta: float) -> void:
	_apply(delta)
	_update_rain_fx()


func _apply(_delta: float) -> void:
	var h := hour_at(elapsed)
	var sp := sun_position(h)
	sun_elevation = sp.x
	_sun_dir = _dir_from(sp.x, sp.y)
	var k := _key_at(sp.x)
	var overcast := smoothstep(0.55, 0.95, clouds)
	var dark := clampf(overcast * 0.7 + rain * 0.35, 0.0, 1.0)
	# sky
	sky_mat.set_shader_parameter("zenith_color", (k["zenith"] as Color).lerp(Color(0.32, 0.34, 0.38) * _day_level(sp.x), dark * 0.8))
	sky_mat.set_shader_parameter("horizon_color", (k["horizon"] as Color).lerp(Color(0.45, 0.47, 0.5) * _day_level(sp.x), dark * 0.8))
	sky_mat.set_shader_parameter("ground_color", k["ground"])
	sky_mat.set_shader_parameter("sun_color", k["sun"])
	sky_mat.set_shader_parameter("sun_dir", _sun_dir)
	sky_mat.set_shader_parameter("sun_size", 0.035 * (1.0 - overcast))
	sky_mat.set_shader_parameter("sun_glow", float(k["glow"]) * (1.0 - overcast * 0.85))
	sky_mat.set_shader_parameter("cloud_coverage", clouds)
	sky_mat.set_shader_parameter("cloud_darkness", dark)
	var lvl := _day_level(sp.x)
	sky_mat.set_shader_parameter("cloud_color", (k["cloud"] as Color).lerp(Color(0.62, 0.63, 0.66) * lvl, dark * 0.85))
	sky_mat.set_shader_parameter("cloud_shade", (k["shade"] as Color).lerp(Color(0.3, 0.31, 0.34) * lvl, dark * 0.85))
	sky_mat.set_shader_parameter("cloud_offset", Vector2(elapsed * 0.004, elapsed * 0.0017))
	sky_mat.set_shader_parameter("star_amount", k["stars"])
	sky_mat.set_shader_parameter("moon_amount", clampf(-sp.x / 8.0, 0.0, 1.0) * (1.0 - overcast))
	sky_mat.set_shader_parameter("moon_dir", _moon_dir)
	sky_mat.set_shader_parameter("exposure", 1.0)
	# light: the sun above the horizon, otherwise the moon
	var sun_amount := smoothstep(-2.0, 4.0, sp.x)
	var moon_amount := smoothstep(-2.0, -9.0, sp.x)
	var sun_col: Color = k["sun"]
	if sun_amount >= moon_amount:
		sun.global_transform = Transform3D(Basis.looking_at(-_sun_dir, Vector3.UP if absf(_sun_dir.y) < 0.99 else Vector3.FORWARD), Vector3.ZERO)
		sun.light_color = sun_col
		sun.light_energy = lerpf(0.05, 1.35, clampf(sp.x / 30.0, 0.0, 1.0)) * sun_amount * (1.0 - overcast * 0.75)
	else:
		sun.global_transform = Transform3D(Basis.looking_at(-_moon_dir, Vector3.UP), Vector3.ZERO)
		sun.light_color = Color(0.45, 0.55, 0.85)
		sun.light_energy = 0.2 * moon_amount * (1.0 - overcast * 0.6)
	sun.shadow_enabled = sun.light_energy > 0.03
	# fog: thicker in rain and in the early morning
	var mist := exp(-pow((h - 6.8) / 1.3, 2.0)) * (1.0 - rain * 0.5)
	env.fog_light_color = (k["fog"] as Color).lerp(Color(0.5, 0.52, 0.55) * _day_level(sp.x), dark * 0.85)
	env.fog_density = float(k["fog_d"]) * (1.0 + rain * 2.2 + mist * 3.5)
	env.ambient_light_energy = float(k["ambient"]) * (1.0 - dark * 0.25)
	env.tonemap_exposure = float(k["exposure"]) + dark * 0.1
	# night factor for lamps, windows and headlights
	night = clampf(1.0 - smoothstep(-5.0, 6.0, sp.x) + dark * 0.35 * smoothstep(20.0, 0.0, sp.x), 0.0, 1.0)
	if absf(night - _last_night) > 0.02:
		_last_night = night
		night_changed.emit(night)
	for m in materials_wet:
		(m as ShaderMaterial).set_shader_parameter("wetness", wetness)


func _day_level(elev: float) -> float:
	return lerpf(0.08, 1.0, smoothstep(-8.0, 12.0, elev))


func _key_at(elev: float) -> Dictionary:
	if elev <= float(KEYS[0]["e"]):
		return KEYS[0]
	for i in range(KEYS.size() - 1):
		var a: Dictionary = KEYS[i]
		var b: Dictionary = KEYS[i + 1]
		if elev <= float(b["e"]):
			var t := (elev - float(a["e"])) / (float(b["e"]) - float(a["e"]))
			var out := {}
			for key in a.keys():
				var va = a[key]
				if va is Color:
					out[key] = (va as Color).lerp(b[key], t)
				else:
					out[key] = lerpf(float(va), float(b[key]), t)
			return out
	return KEYS[KEYS.size() - 1]


func sun_direction() -> Vector3:
	return _sun_dir


func moon_direction() -> Vector3:
	return _moon_dir


## How visible the sun disk is (for lens flares): 0 below the horizon or behind thick clouds.
func sun_visibility() -> float:
	return smoothstep(-1.0, 2.0, sun_elevation) * (1.0 - smoothstep(0.45, 0.9, clouds))


func moon_visibility() -> float:
	return smoothstep(-2.0, -9.0, sun_elevation) * (1.0 - smoothstep(0.45, 0.9, clouds))


# ---------------------------------------------------------------------------
# Rain effects
# ---------------------------------------------------------------------------
func _build_rain() -> void:
	if weather == "dry":
		return
	_rain_fx = GPUParticles3D.new()
	_rain_fx.name = "Rain"
	_rain_fx.amount = [2500, 4500, 7000, 9000][clampi(quality, 0, 3)]
	_rain_fx.lifetime = 1.3
	_rain_fx.local_coords = false
	_rain_fx.top_level = true
	_rain_fx.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_rain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 1, 26)
	pm.direction = Vector3(0.08, -1, 0.04)
	pm.spread = 3.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3.ZERO
	_rain_fx.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.5)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_mat.albedo_color = Color(0.75, 0.8, 0.85, 0.08)
	_rain_mat.disable_receive_shadows = true
	quad.material = _rain_mat
	_rain_fx.draw_pass_1 = quad
	add_child(_rain_fx)
	# splashes on the ground around the camera
	_splash_fx = GPUParticles3D.new()
	_splash_fx.name = "Splashes"
	_splash_fx.amount = [400, 800, 1400, 1800][clampi(quality, 0, 3)]
	_splash_fx.lifetime = 0.16
	_splash_fx.local_coords = false
	_splash_fx.top_level = true
	_splash_fx.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 10, 60))
	_splash_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(18, 0.02, 18)
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 35.0
	sm.initial_velocity_min = 0.4
	sm.initial_velocity_max = 0.9
	sm.gravity = Vector3(0, -9.0, 0)
	sm.scale_min = 0.5
	sm.scale_max = 1.0
	_splash_fx.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.035, 0.035)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.albedo_color = Color(0.8, 0.83, 0.88, 0.09)
	smat.albedo_texture = TexKit.smoke_texture()
	sq.material = smat
	_splash_fx.draw_pass_1 = sq
	add_child(_splash_fx)
	# rain sound
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.15
	_rain_player = AudioStreamPlayer.new()
	_rain_player.stream = gen
	add_child(_rain_player)
	_apply_weather_volume()
	Game.settings_changed.connect(_apply_weather_volume)
	_rain_player.play()
	_rain_playback = _rain_player.get_stream_playback()


## "Wetter" slider in the audio options (0 = off).
func _apply_weather_volume() -> void:
	if _rain_player == null:
		return
	var v := clampf(float(Game.settings.get("weather_volume", 0.6)), 0.0, 1.5)
	_rain_player.volume_db = linear_to_db(maxf(v, 0.0001)) - 10.0


func _update_rain_fx() -> void:
	if _rain_fx == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	# emit a bit ahead of the camera so moving forward does not run out of drops
	var ahead := fwd.normalized() * 8.0 if fwd.length_squared() > 0.01 else Vector3.ZERO
	_rain_fx.global_position = cp + ahead + Vector3(0, 14.0, 0)
	_rain_fx.emitting = rain > 0.02
	_rain_fx.amount_ratio = clampf(rain, 0.0, 1.0)
	var lvl := lerpf(0.12, 0.8, _day_level(sun_elevation))
	# faint streaks: you notice the rain without looking through a curtain
	_rain_mat.albedo_color = Color(lvl, lvl * 1.04, lvl * 1.1, 0.045 + 0.06 * rain)
	var ground_y := 0.05
	if track:
		ground_y = 0.06
	_splash_fx.global_position = Vector3(cp.x, ground_y, cp.z) + ahead
	_splash_fx.emitting = rain > 0.05
	_splash_fx.amount_ratio = clampf(rain, 0.0, 1.0)
	_fill_rain_audio()


## Calm rain: a soft, warm wash of low-passed noise (independent per ear, slowly swelling like gusts),
## a low rumble when it pours and a quiet patter of drops on leaves – no hiss, no clicks.
func _fill_rain_audio() -> void:
	if _rain_playback == null:
		return
	var frames := _rain_playback.get_frames_available()
	if frames <= 0:
		return
	_rain_playback.push_buffer(render_rain(frames))


func render_rain(frames: int) -> PackedVector2Array:
	var sr := 22050.0
	var buf := PackedVector2Array()
	buf.resize(frames)
	var amp := clampf(rain, 0.0, 1.0)
	var k_wash := 1.0 - exp(-TAU * 1000.0 / sr)
	var k_rumble := 1.0 - exp(-TAU * 160.0 / sr)
	var drop_rate := (20.0 + 70.0 * amp) / sr
	var drop_decay := exp(-1.0 / (0.008 * sr))
	_gust_ph = fposmod(_gust_ph + float(frames) / sr * 0.09, 1.0)
	var gust := 0.85 + 0.15 * sin(_gust_ph * TAU) + 0.06 * sin(_gust_ph * TAU * 2.7 + 1.0)
	var wash_amp := 0.5 * amp * gust
	var rumble_amp := 0.9 * pow(amp, 1.5)
	var drop_amp := 0.05 * sqrt(amp)
	var l1 := _rs[0]
	var l2 := _rs[1]
	var r1 := _rs[2]
	var r2 := _rs[3]
	var rum := _rs[4]
	var dl := _rs[5]
	var db := _rs[6]
	var df := _rs[7]
	var pan := _rs[8]
	var denv := _drop_env
	for i in frames:
		var wl := randf() * 2.0 - 1.0
		var wr := randf() * 2.0 - 1.0
		l1 += (wl - l1) * k_wash
		l2 += (l1 - l2) * k_wash
		r1 += (wr - r1) * k_wash
		r2 += (r1 - r2) * k_wash
		rum += ((wl + wr) * 0.5 - rum) * k_rumble
		var left := l2 * wash_amp + rum * rumble_amp
		var right := r2 * wash_amp + rum * rumble_amp
		if denv > 0.001:
			# a drop: short band-limited tap, panned
			dl += df * db
			db += df * (wl * denv - dl - 1.4 * db)
			var tap := db * drop_amp
			left += tap * (1.0 - pan)
			right += tap * pan
			denv *= drop_decay
		elif randf() < drop_rate:
			denv = randf_range(0.3, 1.0)
			df = 2.0 * sin(PI * randf_range(900.0, 2600.0) / sr)
			pan = randf()
		buf[i] = Vector2(left, right)
	_rs = PackedFloat32Array([l1, l2, r1, r2, rum, dl, db, df, pan])
	_drop_env = denv
	return buf
