extends RigidBody3D
## Drift-tuned raycast vehicle.
## - 4 raycast suspensions (spring + damper + anti-roll bars)
## - tyre model with slip-angle curve and a friction circle, so wheelspin / handbrake break rear grip
## - engine with torque curve, soft rev limiter, turbo spool & blow-off, nitro, launch control
## - automatic or manual gearbox (manual never shifts by itself)
## - tuning (engine, gearbox, suspension, tyres, steering, turbo, nitro) from Game.get_tuning()
## Remote (network) cars use the same node as a kinematic, interpolated puppet.

signal shifted(up: bool, boost: float)
signal blow_off(amount: float, full: bool)
signal assist_toggled(name: String, on: bool)   # ABS / ESP switched by its key   # full = lifting off the throttle, else a gear change
signal wall_hit(strength: float)
## strength 1 = loud bang with a big flame, below 1 = small overrun pop (Burble-Tune)
signal backfire(strength: float)

const CarBody = preload("res://scripts/car/car_body.gd")
const CarAudio = preload("res://scripts/car/car_audio.gd")
const TireFX = preload("res://scripts/car/tire_fx.gd")
const Underglow = preload("res://scripts/car/underglow.gd")

const LAYER_WORLD := 1
const LAYER_LOCAL := 2
const LAYER_REMOTE := 4
const LAYER_PROPS := 8         # loose physics props (playground barrels, cones, crates)

const SUSP_TRAVEL := 0.30
const SAG := 0.09
const PEAK_SLIP := 0.14         # rad – slip angle at maximum lateral grip
const SLIDE_GRIP := 0.78        # lateral grip multiplier when fully sliding
const REAR_SOFT := 2.2          # rear peak slip angle multiplier at 100 % "slide" setting
const RELAX_MAX := 0.06         # s – tyre relaxation time at 100 % "slide" setting
const STEER_SPEED := 5.5        # rad/s
const DRAG := 0.34
const ROLLING := 3.0
const LAUNCH_RPM := 0.6         # launch control rpm as a fraction of the redline
const KINETIC := 0.95           # spinning tyre: share of the peak grip it still pushes with
const SPIN_HOLD := 0.78         # a spinning wheel keeps spinning while the drive exceeds this share of the grip
const SPIN_MASS := 32.0         # kg – how hard the drivetrain resists spinning the wheels up (low = free-revving)
const DRIFT_PUSH := 3.2         # m/s² – extra drive along the nose at full throttle in a drift
const DRIFT_STEER := 2.8        # m/s² – in a slide the steering bends the path towards where you steer
const DRIFT_TRAIL_POINTS := 50000.0   # a drift chain above this lays a glowing trail in the car's colour
const INERTIA_SCALE := Vector3(1.25, 1.4, 1.25)   # heavier feel: more rotational inertia than a plain box

# --- configuration (set before adding to the tree) ---
var car_id := "r34"
var paint := {}
var player_name := "Driver"
var peer_id := 1
var is_remote := false
## Extra suspension travel and ride height (m), e.g. for the offroad minigame – see set_lift().
var lift := 0.0
## Minigame bots: when valid, returns [throttle, brake, steer, handbrake] instead of the keyboard.
var ai_fn: Callable
var trail_active := false     # drift trail on (local: set by the world from the drift chain)
var is_bot := false            # a minigame bot: collides like a remote car, sounds positional
## Tuning to use instead of the player's saved tuning for this car (race bots: the player's level)
var tuning_override: Dictionary = {}
var brake_gain := 1.0     # brake tuning: force multiplier
var brake_bite := 1.0     # brake tuning: longitudinal grip multiplier while braking
var is_display := false
var transmission := "auto"
var remote_collisions := true
var track = null
var skidmarks = null

# --- spec (after tuning) ---
var spec: Dictionary
var body_spec: Dictionary
var radius := 0.34
var max_torque := 400.0
var redline := 7500.0
var idle_rpm := 900.0
var gears: Array = []
var reverse_ratio := 3.3
var final_drive := 4.1
var rear_split := 1.0
var turbo_base := 0.0          # stock turbo lag share (off-boost torque loss)
var turbo_extra := 0.0         # tuning: extra torque at full boost
var turbo_gain := 0.0          # >0 when the car has any turbo (audio / HUD)
var spool_rate := 0.9
var grip := 1.0
var steer_lock := 0.75
var spring_k := 40000.0
var damper_c := 3500.0
var antiroll_k := 9000.0
var shift_time_auto := 0.24
var shift_time_manual := 0.16
var nitro_power := 0.12
var nitro_capacity := 2.5      # seconds of continuous use

# --- runtime state ---
var body: CarBody
var audio: CarAudio
var fx: TireFX
var wheels: Array = []
var input_enabled := true
var controls_locked := false
## Party minigames: ground of the venue (pos -> [grip, surface name]), where a reset puts the car and
## the height below which it has fallen off.
var surface_override: Callable
var respawn_fn: Callable
var arena_kill_y := -1e9
var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var steer_angle := 0.0
var handbrake := false
var gear := 1
var rpm := 900.0
var engine_on := true          # switched off with the "engine" key; gas or brake starts it again
var engine_level := 1.0        # 0..1: how much the engine runs (the sound fades with it)
var boost := 0.0
var shift_timer := 0.0
var limiter_timer := 0.0
var reverse_timer := 0.0
var speed := 0.0            # m/s, magnitude
var forward_speed := 0.0    # m/s, signed along heading
var slip_angle := 0.0       # rad, body slip (velocity vs heading)
## Handbrake pulled while already drifting: the car is pulled back in line instead of rotating further
## (pulled from a straight line it still locks the rear for a drift entry; pulled in a drift that is already
## too deep, beyond HB_DEEP_SLIP, it only locks the rear and the car slides on). Decided at the moment the
## handbrake is pulled, held until it is released.
var hb_straighten := false
var _hb_prev := false
const HB_STRAIGHTEN_SLIP := 0.22   # rad (~13 deg) of body slip at the pull = "already drifting"
const HB_DEEP_SLIP := 0.6          # rad (~34 deg): deeper than this the handbrake just locks the rear – the car slides on
const HB_ALIGN := 1.7              # how fast the nose is turned towards the direction of travel (1/s)
var grounded_wheels := 0
var headlights := false
var underglow_cfg: Dictionary = {}   # empty = the local player's setting (Game.get_underglow)
var rims_cfg: Dictionary = {}        # empty = the local player's setting (Game.get_rims)
var underglow: Node3D
var _engine_stage := 0
var spin_hold := SPIN_HOLD     # per car: spinning rear wheels grip again below this share of the grip
## Driving aids (settings): ABS keeps the wheels turning under hard braking (steering keeps working),
## ESP cuts the throttle and brakes the rotation when the car starts to slide. *_active = intervening
## right now (the dashboard lights blink).
## Throttle response (tuning): 1 = stock; lower = the pedal, the revs and the wheel spin build up gentler
var response := 1.0
var _thr_prev := 0.0
var abs_on := true
var esp_on := false
var abs_active := false
var esp_active := false
var yaw_damp := 0.0            # per car: extra yaw damping while sliding (keeps light, powerful cars calmer)
## The "Bouncing Yaris": springs that never settle (energy fed in on every rebound) and a body that
## wobbles like jelly. The wobble is worked out from how the drawn car moves, so remote players see
## exactly the same on their screens (their motion comes over the network).
var _counter := 0.0           # counter-steer amount this step (0 … 1)
const COUNTER_K := 1.9
var bounce := 0.0
var jelly := 0.0
var _jelly := Vector3.ZERO       # squash (y), lean sideways (x), lean fore/aft (z)
var _jelly_v := Vector3.ZERO
var _jelly_vel := Vector3.ZERO   # last drawn velocity
var _jelly_pos := Vector3.ZERO
var _jelly_init := false
var braking_visual := false
var track_hint := -1
var surface_name := "asphalt"
var total_slip := 0.0
var flip_timer := 0.0
var nitro := 1.0            # 0..1 tank
var nitro_active := false
var _xf_prev := Transform3D.IDENTITY   # the last two physics states, interpolated for drawing
var _xf_curr := Transform3D.IDENTITY
var _auto_hold := 0.0      # automatic gearbox: pause after a shift
var _paddle_hold := 0.0    # automatic gearbox: a paddle shift keeps the chosen gear this long
const PADDLE_HOLD := 4.0
var launch_active := false  # launch control / clutch dump phase
var line_lock := false      # W+S at standstill: front brakes hold, rear wheels spin (burnout)
var launch_time := 0.0
var _launch_osc := 0.0
var _limit_time := 0.0
var _prev_throttle := 0.0
var _prev_velocity := Vector3.ZERO
var _hit_cooldown := 0.0
var _backfire_cooldown := 0.0
var _overrun_time := 0.0
## Burble-Tune level 0..3 (local car: Game.get_burble, remote cars: from the player info)
var burble := -1

# remote interpolation
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_vel := Vector3.ZERO
var _net_time := 0.0
var _net_has := false
var remote_flags := 0
var replay_driven := false     # a replay car: placed exactly where the recording says
var remote_progress := 0.0
var remote_lap := 0
var remote_drift := 0.0
var remote_best_chain := 0.0   # best single drift of this remote player
var remote_chain := 0.0        # the drift they are doing right now


func _ready() -> void:
	spec = Game.get_car(car_id)
	body_spec = CarBody.physics_spec(car_id)
	radius = body_spec["wheel_r"]
	mass = spec["mass"]
	max_torque = spec["torque"]
	redline = spec["redline"]
	idle_rpm = spec["idle"]
	gears = (spec["gears"] as Array).duplicate()
	reverse_ratio = spec["reverse"]
	final_drive = spec["final"]
	rear_split = spec["rear_split"]
	turbo_base = spec["turbo"]
	grip = spec["grip"]
	steer_lock = deg_to_rad(float(spec["steer_lock"]))
	spin_hold = float(spec.get("spin_hold", SPIN_HOLD))
	yaw_damp = float(spec.get("yaw_damp", 0.0))
	bounce = float(spec.get("bounce", 0.0))
	jelly = float(spec.get("jelly", 0.0))
	var static_load := mass * 9.8 / 4.0
	spring_k = static_load / SAG
	damper_c = 2.0 * 0.38 * sqrt(spring_k * mass / 4.0)
	if bounce > 0.0:
		spring_k *= 0.7
		damper_c *= 0.05
	antiroll_k = spring_k * 0.35
	if not is_display:
		_apply_tuning(tuning_override if not tuning_override.is_empty() else Game.get_tuning(car_id))
	if burble < 0:
		# the player's own maps only for the player's car (bots: the car's stock setting)
		var own := not is_remote and not is_bot
		burble = Game.get_burble(car_id) if own else int(spec.get("burble", 1))
		response = Game.get_response(car_id) if own else 1.0
	if not is_remote and not is_display and not is_bot:
		Game.settings_changed.connect(_on_settings_changed)
	turbo_gain = maxf(turbo_base, turbo_extra)
	rpm = idle_rpm

	body = CarBody.new()
	body.name = "Body"
	add_child(body)
	body.build(car_id, paint, not is_remote and not is_display)
	if not is_display:
		body.top_level = true
		_xf_prev = global_transform
		_xf_curr = global_transform

	underglow = Underglow.new()
	underglow.name = "Underglow"
	body.add_child(underglow)
	set_underglow(underglow_cfg if not underglow_cfg.is_empty() or is_remote or is_bot else Game.get_underglow(car_id))
	if rims_cfg.is_empty() and not is_remote and not is_bot:
		rims_cfg = Game.get_rims(car_id)
	body.apply_rims(rims_cfg)
	# the player's stickers from the paint booth (own car and the menu's display car)
	if not is_remote and not is_bot:
		load("res://scripts/car/livery.gd").apply(body, Game.get_livery(car_id))

	_setup_physics()
	_setup_wheels()

	if not is_display:
		fx = TireFX.new()
		fx.name = "TireFX"
		fx.car = self
		add_child(fx)
		audio = CarAudio.new()
		audio.name = "Audio"
		audio.car = self
		audio.positional = is_remote or is_bot
		add_child(audio)
	_update_lights()


## Burble-Tune: bangs on lift-off, on the rev limiter / two-step and flame pops on the overrun.
## Level 0 (Mustang default) never backfires. Runs for local and remote cars (throttle/rpm are synced).
func _update_backfire(delta: float) -> void:
	_backfire_cooldown -= delta
	var lvl := burble
	if lvl <= 0:
		return
	var overrun := throttle < 0.08 and rpm > redline * 0.42 and speed > 6.0
	_overrun_time = _overrun_time + delta if overrun else 0.0
	if _backfire_cooldown > 0.0:
		return
	var lift_rpm: float = [1.0, 0.72, 0.58, 0.45][lvl]
	var lift_chance: float = [0.0, 0.45, 0.85, 1.0][lvl]
	if _prev_throttle > 0.7 and throttle < 0.1 and rpm > redline * lift_rpm:
		_backfire_cooldown = 0.5
		if randf() < lift_chance:
			backfire.emit(1.0)
		return
	var limiter := line_lock or (controls_locked and throttle > 0.4) or (rpm > redline * 0.975 and throttle > 0.3)
	if limiter:
		var rate: float = [0.0, 1.2, 3.5, 6.0][lvl]
		if randf() < delta * rate:
			_backfire_cooldown = 0.12
			backfire.emit(1.0)
	elif overrun and lvl >= 2:
		# the tune keeps a little fuel in the overrun: occasional flame pops, dying away
		var rate: float = (0.5 if lvl == 2 else 2.2) * exp(-_overrun_time / (1.5 if lvl == 2 else 5.0))
		if randf() < delta * rate:
			_backfire_cooldown = 0.15
			backfire.emit(0.5)


func _on_settings_changed() -> void:
	if not is_remote:
		burble = Game.get_burble(car_id)
		response = Game.get_response(car_id)
		var ug := Game.get_underglow(car_id)
		if underglow and ug != underglow.cfg:
			set_underglow(ug)
		var rc := Game.get_rims(car_id)
		if body and rc != rims_cfg:
			rims_cfg = rc
			body.apply_rims(rc)


func set_underglow(cfg: Dictionary) -> void:
	underglow_cfg = cfg
	if underglow:
		underglow.setup(cfg, body_spec, true)


func _apply_tuning(t: Dictionary) -> void:
	var e := int(t.get("engine", 0))
	var g := int(t.get("gearbox", 0))
	var s := int(t.get("suspension", 0))
	var ty := int(t.get("tyres", 0))
	var tu := int(t.get("turbo", 0))
	var n := int(t.get("nitro", 0))
	var st := clampi(int(t.get("steering", 0)), 0, Game.STEER_KIT.size() - 1)
	max_torque *= 1.0 + 0.2 * e
	_engine_stage = e
	# gearbox stages change the ratios (longer 2nd/3rd gear), the final drive and the shift speed
	var gb: Dictionary = Game.tuned_gearing(car_id, t)
	gears = gb["gears"]
	final_drive = gb["final"]
	redline = gb["redline"]
	shift_time_auto = 0.24 * float(gb["shift"])
	shift_time_manual = 0.16 * float(gb["shift"])
	grip *= (1.0 + 0.035 * s) * (1.0 + 0.06 * ty)
	steer_lock += deg_to_rad(float(Game.STEER_KIT[st]))
	spring_k *= 1.0 + 0.12 * s
	damper_c *= 1.0 + 0.1 * s
	antiroll_k *= 1.0 + 0.25 * s
	if tu > 0:
		# turbo cars get more boost, naturally aspirated cars a turbo kit
		if turbo_base > 0.0:
			turbo_extra = 0.12 * tu
		else:
			turbo_extra = 0.18 + 0.1 * (tu - 1)
	spool_rate = 0.9 * (1.0 + 0.35 * tu)
	nitro_power = 0.12 + 0.13 * n
	# brakes: more force per stage; better pads modulate cleaner (a touch more grip while braking hard)
	var bk := int(t.get("brakes", 0))
	brake_gain = 1.0 + 0.15 * bk
	brake_bite = 1.0 + 0.05 * bk
	nitro_capacity = 2.5 + 1.25 * n


func _setup_physics() -> void:
	var length: float = body_spec["length"]
	var hw: float = float(body_spec["track"]) + 0.12
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(hw * 2.0, 0.62, length * 0.96)
	cs.shape = box
	cs.position = Vector3(0, float(body_spec["base"]) + 0.36, 0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var cab := BoxShape3D.new()
	cab.size = Vector3(hw * 1.5, 0.36, length * 0.42)
	cs2.shape = cab
	cs2.position = Vector3(0, float(body_spec["roof"]) - 0.22, 0.2)
	add_child(cs2)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.3
	pm.bounce = 0.1
	physics_material_override = pm
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.42, 0.05)
	# a solid box of the car's size, then scaled up: the car turns in, rolls and pitches more
	# deliberately and keeps its rotation longer – it feels heavier, less like a go-kart
	var bw := hw * 2.0
	var bh := 1.0
	inertia = Vector3(mass / 12.0 * (bh * bh + length * length), mass / 12.0 * (bw * bw + length * length),
		mass / 12.0 * (bw * bw + bh * bh)) * INERTIA_SCALE
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.6
	if is_display:
		freeze = true
		collision_layer = 0
		collision_mask = 0
	elif is_remote:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		collision_layer = LAYER_REMOTE if remote_collisions else 0
		collision_mask = 0
	elif is_bot:
		collision_layer = LAYER_REMOTE
		collision_mask = LAYER_WORLD | LAYER_PROPS | LAYER_LOCAL | LAYER_REMOTE
	else:
		collision_layer = LAYER_LOCAL
		collision_mask = LAYER_WORLD | LAYER_PROPS | (LAYER_REMOTE if remote_collisions else 0)


func _setup_wheels() -> void:
	var tr: float = body_spec["track"]
	var mount_y := radius + SUSP_TRAVEL - SAG
	var local := [
		Vector3(-tr, mount_y, body_spec["axle_f"]), Vector3(tr, mount_y, body_spec["axle_f"]),
		Vector3(-tr, mount_y, body_spec["axle_r"]), Vector3(tr, mount_y, body_spec["axle_r"]),
	]
	for i in 4:
		var ray := RayCast3D.new()
		ray.position = local[i]
		ray.target_position = Vector3(0, -(SUSP_TRAVEL + lift + radius), 0)
		ray.collision_mask = LAYER_WORLD
		ray.enabled = not is_remote and not is_display
		ray.add_exception(self)
		add_child(ray)
		var nodes: Array = body.wheel_nodes[i]
		wheels.append({
			"mount": local[i], "front": i < 2, "left": i % 2 == 0, "ray": ray,
			"pivot": nodes[0], "spin_node": nodes[1],
			"compression": 0.0, "prev_compression": 0.0, "spring_len": SUSP_TRAVEL - SAG,
			"grounded": false, "contact": Vector3.ZERO, "normal": Vector3.UP,
			"load": 0.0, "slip": 0.0, "lat_slip": 0.0, "long_slip": 0.0, "spin": 0.0,
			"v_long": 0.0, "surface": "asphalt", "rot": 0.0,
		})


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if is_display:
		return
	# Godot 4.3 writes a rigid body's new transform back only at the start of the next physics tick, so
	# global_transform here is the result of the previous step: keep the last two states and draw
	# between them (one tick of latency, but smooth at any frame rate, e.g. 75/144 Hz)
	_xf_prev = _xf_curr
	_xf_curr = global_transform
	if is_remote:
		_remote_step(delta)
		return
	_read_input(delta)
	_simulate(delta)
	_check_hits(delta)
	_check_flip(delta)


func _process(delta: float) -> void:
	if is_display:
		return
	# the body mesh is drawn at an interpolated transform so it moves smoothly at any frame rate
	body.global_transform = visual_transform()
	if jelly > 0.0:
		_update_jelly(delta)
	_update_wheel_visuals(delta)
	_update_lights()


func _read_input(delta: float) -> void:
	var thr := 0.0
	var brk := 0.0
	var steer_target := 0.0
	var hb := false
	var want_nitro := false
	if input_enabled:
		thr = Input.get_action_strength("accelerate")
		brk = Input.get_action_strength("brake")
		steer_target = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		hb = Input.is_action_pressed("handbrake")
		want_nitro = Input.is_action_pressed("nitro")
		if Input.is_action_just_pressed("toggle_transmission"):
			transmission = "manual" if transmission == "auto" else "auto"
			if transmission == "auto" and gear == 0:
				gear = 1
		if transmission == "manual" and not controls_locked:
			if Input.is_action_just_pressed("shift_up"):
				_shift(1)
			if Input.is_action_just_pressed("shift_down"):
				_shift(-1)
		elif transmission == "auto" and not controls_locked and gear >= 1:
			# paddles in automatic mode: [E]/[Q] pick a gear by hand, the box then holds it for a while
			var paddle := 0
			if Input.is_action_just_pressed("shift_up") and gear < gears.size():
				paddle = 1
			if Input.is_action_just_pressed("shift_down") and gear > 1:
				paddle = -1
			if paddle != 0:
				_shift(paddle)
				_paddle_hold = PADDLE_HOLD
		if Input.is_action_just_pressed("engine") and engine_on:
			engine_on = false
			assist_toggled.emit("MOTOR", false)
		elif not engine_on and (thr > 0.05 or brk > 0.05):
			# pulling away: it starts right away
			engine_on = true
			assist_toggled.emit("MOTOR", true)
		if Input.is_action_just_pressed("lights"):
			headlights = not headlights
		# driver aids: K / right stick click = ABS, J / left stick click = ESP (saved in the settings)
		if Input.is_action_just_pressed("toggle_abs"):
			Game.set_setting("abs", not bool(Game.settings.get("abs", true)))
			assist_toggled.emit("ABS", bool(Game.settings["abs"]))
		if Input.is_action_just_pressed("toggle_esp"):
			Game.set_setting("esp", not bool(Game.settings.get("esp", false)))
			assist_toggled.emit("ESP", bool(Game.settings["esp"]))
		# hold N: strobe the underglow (works without flasher tuning)
		if underglow:
			underglow.manual = Input.is_action_pressed("neon_flash")
	if ai_fn.is_valid():
		var a: Array = ai_fn.call()
		thr = float(a[0])
		brk = float(a[1])
		steer_target = float(a[2])
		hb = bool(a[3])
		want_nitro = a.size() > 4 and bool(a[4])
	# smoothed steering for digital input
	var rate := 4.5 if absf(steer_target) > absf(steer_input) and signf(steer_target) == signf(steer_input) else 7.0
	steer_input = move_toward(steer_input, steer_target, rate * delta)
	handbrake = hb
	if handbrake and not _hb_prev:
		hb_straighten = absf(slip_angle) > HB_STRAIGHTEN_SLIP and absf(slip_angle) < HB_DEEP_SLIP \
			and speed > 8.0 and forward_speed > 0.0
	elif hb_straighten and absf(slip_angle) > HB_DEEP_SLIP:
		hb_straighten = false   # the slide got too deep while pulling: no more pull back, it slides
	elif not handbrake:
		hb_straighten = false
	_hb_prev = handbrake
	if controls_locked:
		# countdown: rev the engine against the launch control, handbrake on
		throttle = thr
		brake_input = 0.0
		handbrake = true
		line_lock = false
		nitro_active = false
		return
	if transmission == "auto":
		if gear == -1:
			throttle = brk
			brake_input = thr
		else:
			throttle = thr
			brake_input = brk
		if gear >= 1 and brk > 0.3 and thr < 0.1 and forward_speed < 0.8:
			reverse_timer += delta
			if reverse_timer > 0.3:
				gear = -1
				reverse_timer = 0.0
		elif gear == -1 and thr > 0.3 and forward_speed > -0.8:
			reverse_timer += delta
			if reverse_timer > 0.15:
				gear = 1
				reverse_timer = 0.0
		else:
			reverse_timer = 0.0
		if gear == 0:
			gear = 1
	else:
		throttle = thr
		brake_input = brk
	# throttle response: below 100 % the pedal travels in over a short time instead of snapping to full
	# (0.2 -> about half a second to full throttle); lifting off stays immediate
	if response < 0.999 and throttle > _thr_prev:
		throttle = minf(throttle, _thr_prev + delta * 2.0 * pow(15.0, (response - Game.RESPONSE_MIN) / (1.0 - Game.RESPONSE_MIN)))
	_thr_prev = throttle
	# bots: ABS on, no ESP (it cuts in at ~5 degrees of body slip – in almost every corner; the bots
	# have their own traction control); the player's switches are the player's
	abs_on = true if is_bot else bool(Game.settings.get("abs", true))
	esp_on = false if is_bot else bool(Game.settings.get("esp", false))
	esp_active = false
	if esp_on and not handbrake and speed > 5.0 and gear >= 1:
		# ESP: less power as soon as the rear steps out
		var cut := smoothstep(0.08, 0.25, absf(slip_angle))
		if cut > 0.0 and throttle > 0.1:
			throttle *= 1.0 - 0.85 * cut
			esp_active = true
	# W + S at (near) standstill = launch control with line lock (burnout)
	line_lock = gear >= 1 and thr > 0.5 and brk > 0.5 and absf(forward_speed) < 3.0
	# nitro
	nitro_active = want_nitro and nitro > 0.0 and throttle > 0.1 and gear >= 1 and not line_lock
	if nitro_active:
		nitro = maxf(nitro - delta / nitro_capacity, 0.0)
	else:
		var regen := 0.035 + (0.07 if absf(slip_angle) > 0.25 and speed > 8.0 else 0.0)
		nitro = minf(nitro + regen * delta, 1.0)


## How quickly the revs build up: 1 at 100 % response, 0.45 at the minimum. Spinning wheels are held
## back less (spin=true), so burnouts and drifts still work at any setting.
func _response_factor(spin := false) -> float:
	return lerpf(0.75 if spin else 0.45, 1.0, (response - Game.RESPONSE_MIN) / (1.0 - Game.RESPONSE_MIN))


func _gear_ratio() -> float:
	if gear == 0:
		return 0.0
	if gear < 0:
		return -reverse_ratio * final_drive
	return float(gears[gear - 1]) * final_drive


func _shift(dir: int) -> void:
	var ng := clampi(gear + dir, -1, gears.size())
	if ng == gear:
		return
	if ng == -1 and forward_speed > 2.0:
		return
	var up := dir > 0 and gear >= 1
	gear = ng
	shift_timer = shift_time_auto if transmission == "auto" else shift_time_manual
	if up and boost > 0.25:
		blow_off.emit(boost, false)
		boost *= 0.75
	if up and absf(slip_angle) < 0.15:
		# the clutch opens: spinning wheels slow down to the road and grip again in the next gear
		for w in wheels:
			w["spin"] = float(w["spin"]) * 0.3
	shifted.emit(dir > 0, boost)


func _torque_at(r: float) -> float:
	var t := clampf(r / redline, 0.0, 1.1)
	var c := (0.52 + 1.25 * t - 0.95 * t * t) / 0.931
	var tq := max_torque * clampf(c, 0.3, 1.0)
	if turbo_base > 0.0 or turbo_extra > 0.0:
		tq *= lerpf(1.0 - turbo_base, 1.0, boost) + turbo_extra * boost
	return tq


func _simulate(delta: float) -> void:
	var xf := global_transform
	var b := xf.basis
	var up := b.y
	var fwd := -b.z
	var right := b.x
	var vel := linear_velocity
	speed = vel.length()
	forward_speed = vel.dot(fwd)
	var local_vel := b.inverse() * vel
	slip_angle = atan2(local_vel.x, -local_vel.z) if speed > 3.0 else 0.0
	var com_global := xf * center_of_mass

	if track:
		var proj: Array = track.project(global_position, track_hint)
		track_hint = proj[0]

	# --- steering (speed sensitive + counter-steer assist) ---
	# finer steering the faster you go (60 km/h ~54 %, 120 km/h ~23 %, 170 km/h ~13 % of the lock), so a
	# full keyboard input at speed doesn't throw the car into a slide; counter-steer stays unlimited
	var vs := absf(forward_speed) / 18.0
	var speed_factor := 1.0 / (1.0 + vs * vs)
	var target := steer_input * steer_lock * speed_factor
	if forward_speed > 4.0 and absf(slip_angle) > 0.08:
		var assist := float(Game.settings.get("steer_assist", 0.5))
		target += clampf(slip_angle, -steer_lock, steer_lock) * assist * (1.0 - absf(steer_input) * 0.4)
	target = clampf(target, -steer_lock, steer_lock)
	steer_angle = move_toward(steer_angle, target, STEER_SPEED * lerpf(1.0, 0.45, smoothstep(15.0, 45.0, absf(forward_speed))) * delta)
	# how much the driver counter-steers a slide (0 … 1): the front tyres bite again and the car
	# answers (see "counter-steer" below) – also when all four tyres are already sliding
	_counter = 0.0
	if forward_speed > 3.0 and absf(slip_angle) > 0.1:
		_counter = clampf(steer_input * signf(slip_angle), 0.0, 1.0) * smoothstep(0.1, 0.3, absf(slip_angle))

	# --- launch control state ---
	if line_lock:
		launch_active = true
		launch_time = 0.0
	elif launch_active:
		launch_time += delta
		if launch_time > 1.3 or forward_speed > 13.0 or throttle < 0.3 or gear < 1:
			launch_active = false
	# launch control only through the two-step (W + S at a standstill, then release S) – a normal
	# pull-away just slips the clutch at low revs

	# --- gearbox / engine ---
	shift_timer = maxf(shift_timer - delta, 0.0)
	_auto_hold = maxf(_auto_hold - delta, 0.0)
	_paddle_hold = maxf(_paddle_hold - delta, 0.0)
	var driven_speed := 0.0
	var driven_count := 0.0
	for w in wheels:
		var driven: bool = (w["front"] and rear_split < 1.0) or (not w["front"] and rear_split > 0.0)
		if driven:
			# AWD: the engine follows the axles weighted by the torque split (spinning rears rev it up)
			var wgt: float = (1.0 - rear_split) if w["front"] else rear_split
			driven_speed += (float(w["v_long"]) + float(w["spin"])) * wgt
			driven_count += wgt
	if driven_count > 0.0:
		driven_speed /= driven_count
		# AWD: the axle that spins takes the engine with it (the centre coupling slips)
		var fastest := 0.0
		for w in wheels:
			var drv: bool = (w["front"] and rear_split < 1.0) or (not w["front"] and rear_split > 0.0)
			if drv:
				var ws: float = float(w["v_long"]) + float(w["spin"])
				if absf(ws) > absf(fastest):
					fastest = ws
		driven_speed = lerpf(driven_speed, fastest, 0.85)
	var ratio := _gear_ratio()
	var wheel_rpm := driven_speed / radius * 60.0 / TAU
	var coupled_rpm := absf(wheel_rpm * ratio)
	var launch_rpm := redline * LAUNCH_RPM
	_launch_osc += delta
	var wobble := sin(_launch_osc * TAU * 6.5) * 0.045 + sin(_launch_osc * TAU * 2.3) * 0.02 + randf_range(-0.012, 0.012)
	# handbrake pulled = clutch in (as drifters do): the engine revs freely, no drive reaches the
	# wheels and the locked rear wheels stay locked even with the throttle down
	var clutch_in := handbrake and not line_lock and not controls_locked
	var engaged := ratio != 0.0 and shift_timer <= 0.0 and not controls_locked and not clutch_in and engine_on
	engine_level = move_toward(engine_level, 1.0 if engine_on else 0.0, delta * (5.0 if engine_on else 1.4))
	if not engine_on:
		# switched off: the revs run down, no drive, no boost
		rpm = move_toward(rpm, 0.0, 1800.0 * delta)
		boost = move_toward(boost, 0.0, 3.0 * delta)
	elif rpm < idle_rpm * 0.9:
		# starting: the starter turns it over and it catches
		rpm = move_toward(rpm, idle_rpm, 3000.0 * delta)
	elif line_lock or (controls_locked and throttle > 0.4):
		# two-step limiter holds the revs around the launch rpm
		rpm = lerpf(rpm, launch_rpm * (1.0 + wobble) * clampf(throttle * 1.2, 0.3, 1.0), 1.0 - exp(-delta * 16.0))
		if turbo_gain > 0.0:
			boost = move_toward(boost, 0.85, 0.7 * delta)
	elif ratio != 0.0 and shift_timer > 0.0:
		# clutch open during a gear change: revs drop to the next gear's speed (no free revving)
		rpm = lerpf(rpm, maxf(coupled_rpm, idle_rpm), 1.0 - exp(-delta * 14.0))
	elif engaged:
		var floor_rpm := idle_rpm
		var climb := 2600.0
		if absi(gear) == 1:
			# normal pull-away: the clutch slips just above idle (far below the launch-control revs)
			floor_rpm = idle_rpm + throttle * (redline * 0.26 - idle_rpm)
		if absi(gear) == 1 and throttle > 0.85 and coupled_rpm < redline * 0.6:
			# flat out pulling away in 1st: the clutch lets the
			# engine rev up (burnout) – the torque then breaks the tyres loose and they keep the revs up
			# by themselves. Higher gears stay coupled: with grip the revs follow the road speed.
			floor_rpm = redline * 0.96
			climb = 3600.0 + 1800.0 * float(_engine_stage)
		if launch_active:
			floor_rpm = maxf(floor_rpm, launch_rpm * (1.0 + wobble * 0.5))
		var target_rpm := maxf(coupled_rpm, floor_rpm)
		var rf := _response_factor()
		var next := lerpf(rpm, target_rpm, 1.0 - exp(-delta * (18.0 * rf if target_rpm > rpm else 18.0)))
		if not launch_active and next > rpm and coupled_rpm < floor_rpm:
			# while the clutch is still slipping the revs climb (gently at part throttle)
			next = minf(next, rpm + climb * (_response_factor(true) if floor_rpm > redline * 0.9 else rf) * delta)
		rpm = next
	else:
		var free_target := idle_rpm + throttle * (redline * 0.99 - idle_rpm)
		rpm = move_toward(rpm, free_target, (7000.0 * _response_factor() if free_target > rpm else 4000.0) * delta)
	if engine_on and rpm >= idle_rpm * 0.9:
		rpm = clampf(rpm, idle_rpm * 0.9, redline)
	var at_limit := rpm > redline * 0.975
	limiter_timer = 0.1 if at_limit and throttle > 0.3 else maxf(limiter_timer - delta, 0.0)
	_limit_time = _limit_time + delta if at_limit else 0.0

	# turbo spool
	if turbo_gain > 0.0 and not line_lock:
		var boost_target := 0.0
		if throttle > 0.4:
			boost_target = clampf((rpm - redline * 0.3) / (redline * 0.35), 0.0, 1.0) * throttle
		boost = move_toward(boost, boost_target, (spool_rate if boost_target > boost else 3.0) * delta)
		if _prev_throttle > 0.6 and throttle < 0.2 and boost > 0.35:
			blow_off.emit(boost, true)
			boost *= 0.3
	_update_backfire(delta)
	_prev_throttle = throttle

	var drive_total := 0.0
	if engaged:
		var tq := _torque_at(rpm) * throttle
		# soft rev limiter: torque fades out over the last 3 % instead of a hard cut
		tq *= clampf((redline - rpm) / (redline * 0.03), 0.0, 1.0)
		if nitro_active:
			tq *= 1.0 + nitro_power
		if launch_active and not line_lock:
			tq *= 1.35
		if throttle < 0.05:
			tq = -max_torque * 0.14 * (rpm / redline) * signf(ratio * driven_speed) * signf(ratio)
		drive_total = tq * ratio * 0.85 / radius

	# automatic gearbox – never runs in manual mode, and pauses after a paddle shift
	if transmission == "auto" and shift_timer <= 0.0 and gear >= 1 and not controls_locked and not line_lock and _paddle_hold <= 0.0:
		var ground_rpm := absf(forward_speed / radius * 60.0 / TAU * ratio)
		var sliding := absf(slip_angle) > 0.35 and forward_speed > 5.0
		var hold_for_drift := sliding and _limit_time < 0.45
		# wheelspin makes the engine rpm run away from the road speed: only shift down when the engine
		# itself is slow too, otherwise the box would hunt between 1st and 2nd
		var spinning := rpm > ground_rpm * 1.25 + 300.0
		# upshift when the road speed has reached the gear's limit – or after a while on the limiter
		# with spinning wheels – but never right after the last automatic shift (no hunting)
		var gear_done := ground_rpm > redline * 0.8 or (_limit_time > 0.6 and ground_rpm > redline * 0.55)
		var may_down := _auto_hold <= 0.0 or throttle < 0.3
		# no upshift while the tyres just spin at low road speed (donuts, burnouts)
		var spin_only := spinning and ground_rpm < redline * 0.35
		if rpm > redline * 0.94 and gear < gears.size() and throttle > 0.2 and gear_done and not hold_for_drift and not launch_active and not spin_only:
			_shift(1)
			_auto_hold = 1.2
		elif gear > 1 and may_down and ground_rpm < redline * 0.42 and rpm < redline * 0.55:
			_shift(-1)
			_auto_hold = 0.8
		elif gear > 1 and may_down and throttle > 0.95 and ground_rpm < redline * 0.5 and not spinning:
			var lower := absf(forward_speed / radius * 60.0 / TAU * float(gears[gear - 2]) * final_drive)
			if lower < redline * 0.8:
				_shift(-1)

	# --- per wheel forces ---
	grounded_wheels = 0
	total_slip = 0.0
	abs_active = false
	var front_brake := 0.62
	var brake_force_max := mass * 9.8 * 1.25 * brake_gain
	# player settings: handbrake strength and how much the cars slide sideways
	var hb_strength := clampf(float(Game.settings.get("handbrake_strength", 0.75)), 0.1, 1.0)
	var slide := clampf(float(Game.settings.get("slide", 0.5)), 0.0, 1.0)
	# at speed the car sits firmer (like downforce): stiffer, quicker, grippier rear tyres – no pendulum
	var hs := smoothstep(20.0, 45.0, speed)
	var rear_slide_grip := lerpf(lerpf(0.86, 0.62, slide), 0.9, hs * 0.7)
	var slide_width := lerpf(2.2, 4.2, slide)
	var mass_per_wheel := mass / 4.0
	var spin_surface := rpm / 60.0 * TAU * radius / maxf(absf(ratio), 0.01) if ratio != 0.0 else 0.0
	for i in 4:
		var w: Dictionary = wheels[i]
		var ray: RayCast3D = w["ray"]
		ray.force_raycast_update()
		w["prev_compression"] = w["compression"]
		if not ray.is_colliding():
			w["grounded"] = false
			w["compression"] = 0.0
			w["spring_len"] = SUSP_TRAVEL + lift
			w["load"] = 0.0
			w["slip"] = 0.0
			w["spin"] = move_toward(float(w["spin"]), 0.0, 20.0 * delta)
			if handbrake and not w["front"] and not line_lock:
				w["spin"] = -float(w["v_long"])     # locked in the air as well
			continue
		grounded_wheels += 1
		var hit := ray.get_collision_point()
		var n := ray.get_collision_normal()
		var mount_g := ray.global_position
		var dist := mount_g.distance_to(hit)
		var spring_len := clampf(dist - radius, 0.0, SUSP_TRAVEL + lift)
		var compression := SUSP_TRAVEL + lift - spring_len
		var comp_vel := (compression - float(w["prev_compression"])) / delta
		var f_susp := spring_k * compression + damper_c * comp_vel
		if bounce > 0.0 and absf(linear_velocity.dot(up)) < 1.4:
			# negative damping: every rebound gets a little more push – it bounces and hops for ever
			f_susp -= comp_vel * spring_k * 0.018 * bounce
		if spring_len < 0.03:
			f_susp += spring_k * 3.0 * (0.03 - spring_len)
		f_susp = maxf(f_susp, 0.0)
		w["compression"] = compression
		w["spring_len"] = spring_len
		w["grounded"] = true
		w["contact"] = hit
		w["normal"] = n
		apply_force(up * f_susp, mount_g - global_position)
		var wheel_load := f_susp

		var sg := 1.0
		var sname := "asphalt"
		if surface_override.is_valid():
			# party minigame venue: its own ground
			var so: Array = surface_override.call(hit)
			sg = so[0]
			sname = so[1]
		elif track and track_hint >= 0:
			var s: Array = track.surface_at(hit, track_hint)
			sg = s[0]
			sname = s[1]
		w["surface"] = sname

		var a := steer_angle if w["front"] else 0.0
		var w_fwd := fwd * cos(a) + right * sin(a)
		var w_right := right * cos(a) - fwd * sin(a)
		w_fwd = (w_fwd - n * w_fwd.dot(n)).normalized()
		w_right = (w_right - n * w_right.dot(n)).normalized()
		var cvel := vel + angular_velocity.cross(hit - com_global)
		var v_long := cvel.dot(w_fwd)
		var v_lat := cvel.dot(w_right)
		w["v_long"] = v_long

		var is_front: bool = w["front"]
		var axle_grip := 1.03 if is_front else 0.97 + 0.1 * hs
		var max_f := grip * sg * axle_grip * wheel_load
		if brake_input > 0.3 and brake_bite > 1.0:
			max_f *= lerpf(1.0, brake_bite, clampf((brake_input - 0.3) / 0.7, 0.0, 1.0))

		# longitudinal request
		var split := (1.0 - rear_split) if is_front else rear_split
		var f_drive := drive_total * split * 0.5
		var f_long := f_drive
		var locked := false
		var power_slide := false   # rear wheels spinning under power (handbrake + gas, burnout)
		if line_lock:
			if is_front:
				# line lock: front brakes hold the car
				f_long = clampf(-v_long * mass_per_wheel * 25.0, -max_f, max_f)
			else:
				power_slide = true
		elif brake_input > 0.01:
			var bias := front_brake if is_front else 1.0 - front_brake
			f_long -= clampf(v_long / 0.6, -1.0, 1.0) * brake_force_max * bias * 0.5 * brake_input
		if handbrake and not is_front and not line_lock:
			# the rear wheels lock – also with the throttle down (the clutch is in, see `clutch_in`);
			# the strength setting only decides how much side grip the locked tyres keep
			f_long = -clampf(v_long / 0.4, -1.0, 1.0) * max_f * 0.95
			locked = absf(v_long) > 0.5
		f_long -= v_long * ROLLING
		# parking hold when nearly stopped and no input: static friction keeps the car where it is –
		# it also cancels the downhill pull, so it doesn't creep away on a slope (or roll backwards)
		if throttle < 0.02 and brake_input < 0.02 and absf(v_long) < 1.2 and speed < 1.5 and not line_lock:
			var g_along := -9.8 * w_fwd.y
			f_long = clampf(-v_long * mass_per_wheel * 30.0 - g_along * mass_per_wheel, -max_f, max_f)

		# lateral: slip-angle curve
		var alpha := atan2(v_lat, maxf(absf(v_long), 3.5))
		# softer rear tyres (higher slip angle at peak grip) slide more progressively
		var peak := PEAK_SLIP if is_front else PEAK_SLIP * lerpf(lerpf(1.0, REAR_SOFT, slide), 1.0, hs * 0.75)
		var ratio_a := alpha / peak
		var curve := 0.0
		var slide_grip := lerpf(SLIDE_GRIP, 1.0, _counter * 0.85) if is_front else rear_slide_grip
		if absf(ratio_a) <= 1.0:
			curve = ratio_a
		else:
			curve = signf(ratio_a) * lerpf(1.0, slide_grip, clampf((absf(ratio_a) - 1.0) / slide_width, 0.0, 1.0))
		var f_lat := -curve * max_f
		if speed < 2.0 and not power_slide:
			f_lat = clampf(-v_lat * mass_per_wheel * 6.0, -max_f, max_f)
		elif speed > 4.0:
			# tyre relaxation: side force builds up over a short time, so direction changes (transitions)
			# flow smoothly with the car sliding sideways instead of snapping back to grip
			var tau := lerpf(0.01, RELAX_MAX, slide) * (0.5 if is_front else 1.0) * (1.0 - 0.7 * hs)
			f_lat = lerpf(float(w.get("f_lat", f_lat)), f_lat, 1.0 - exp(-delta / tau))
		w["f_lat"] = f_lat

		var driven_w := split > 0.0
		var spinning_now := false
		if power_slide and line_lock:
			# line lock: the front brakes hold the car, the rears spin at the two-step revs
			f_long = signf(f_drive) * max_f * 0.45
			f_lat = clampf(f_lat, -max_f * 0.35, max_f * 0.35)
			var spin_target := maxf(spin_surface - v_long, 6.0 * throttle)
			w["spin"] = move_toward(float(w["spin"]), spin_target, 50.0 * delta)
			spinning_now = true
		elif driven_w and engaged and f_drive != 0.0 and not locked:
			# wheel spin: the grip left over by the cornering force limits what the tyre can pass on;
			# torque beyond that spins the wheel up (freely, up to the rev limiter in this gear), the
			# spinning tyre still pushes with sliding friction along its slip direction – mostly
			# along the car's nose, i.e. into the corner in a drift
			var lat_use := minf(absf(f_lat), max_f * 0.9)
			var long_cap := maxf(sqrt(maxf(max_f * max_f - lat_use * lat_use, 0.0)), max_f * 0.3)
			var req := absf(f_drive)
			var dsign := signf(f_drive)
			var spin := maxf(float(w["spin"]) * dsign, 0.0)
			var kin := max_f * KINETIC
			# going straight (no slide, no handbrake) the tyre only spins while the drive really exceeds
			# its grip and grips again as soon as it doesn't – the spin only "sticks" in a slide
			var straight := 0.0 if (handbrake or power_slide) else 1.0 - smoothstep(0.1, 0.3, absf(slip_angle))
			var hold := lerpf(spin_hold * (0.7 if power_slide else 1.0), 1.02, straight)
			if spin > 0.3 or req > long_cap * (0.35 if power_slide else lerpf(0.95, 1.05, straight)):
				spin += (req - max_f * hold) / SPIN_MASS * _response_factor(true) * delta
				var v_red := redline / 60.0 * TAU * radius / maxf(absf(ratio), 0.01)
				spin = clampf(spin, 0.0, maxf(v_red - v_long * dsign, 0.0))
			else:
				spin = move_toward(spin, 0.0, 35.0 * delta)
			if spin > 0.05:
				spinning_now = true
				var sv := Vector2(spin, -v_lat * dsign)
				var dir := sv.normalized()
				var blend := smoothstep(0.1, 1.5, spin)
				var lat_rest := f_lat
				var cap := sqrt(maxf(max_f * max_f - pow(minf(req, max_f), 2.0), 0.0))
				lat_rest = clampf(f_lat, -maxf(cap, max_f * 0.3), maxf(cap, max_f * 0.3))
				f_long = lerpf(clampf(f_long, -long_cap, long_cap), dsign * dir.x * kin, blend) - v_long * ROLLING
				f_lat = lerpf(lat_rest, dir.y * dsign * kin, blend)
			else:
				var combined := sqrt(f_long * f_long + f_lat * f_lat)
				if combined > max_f and max_f > 0.0:
					var s2 := max_f / combined
					f_long *= s2
					f_lat *= s2
			w["spin"] = spin * dsign
		else:
			var combined := sqrt(f_long * f_long + f_lat * f_lat)
			if abs_on and brake_input > 0.01 and not locked and combined > max_f * 0.95 and max_f > 0.0:
				# ABS: the brake force is held just below the limit that is left over by the cornering
				# force – the wheel never locks, the tyre keeps its side grip (the car still steers)
				var room := sqrt(maxf(max_f * max_f * 0.9 - f_lat * f_lat, max_f * max_f * 0.04))
				if absf(f_long) > room:
					f_long = clampf(f_long, -room, room)
					abs_active = true
				combined = sqrt(f_long * f_long + f_lat * f_lat)
			if combined > max_f and max_f > 0.0:
				if absf(f_long) > max_f * 0.98 or locked:
					f_long = clampf(f_long, -max_f, max_f) * 0.92
					var remaining := sqrt(maxf(max_f * max_f - f_long * f_long, 0.0))
					var lat_cap := maxf(remaining, max_f * (lerpf(0.5, 0.22, hb_strength) if locked else 0.3))
					if locked and hb_straighten:
						lat_cap = maxf(remaining, max_f * 0.85)   # straightening: the rear keeps its side grip
					f_lat = clampf(f_lat, -lat_cap, lat_cap)
				else:
					var s2 := max_f / combined
					f_long *= s2
					f_lat *= s2
			w["spin"] = move_toward(float(w["spin"]), 0.0, 35.0 * delta)
			if locked:
				w["spin"] = -v_long
		w["spinning"] = spinning_now

		var force_point := hit + up * 0.25 - global_position
		apply_force(w_fwd * f_long + w_right * f_lat, force_point)

		var lat_slide := maxf(absf(v_lat) - 1.2, 0.0)
		var long_slide := absf(float(w["spin"]))
		if locked:
			long_slide = absf(v_long)
		w["lat_slip"] = lat_slide
		w["long_slip"] = long_slide
		var slip := lat_slide * 0.6 + long_slide * 0.5
		if sname != "asphalt" and sname != "curb":
			slip *= 0.4
		w["slip"] = slip
		total_slip += slip

	# drive into the corner: flat out with the car sliding, the rear pushes along the nose
	if engaged and grounded_wheels >= 3 and throttle > 0.6 and forward_speed > 5.0 and not line_lock:
		var slide_k := smoothstep(0.12, 0.45, absf(slip_angle))
		if slide_k > 0.0:
			var push := DRIFT_PUSH * mass * slide_k * (throttle - 0.6) / 0.4 * (0.5 + 0.5 * absf(steer_input))
			apply_central_force(fwd * push)

	# steering in a slide: the path bends towards the side you steer to (not only the nose), so the car
	# goes where you point it while drifting – counter-steer opens the line, steering in tightens it
	if grounded_wheels >= 3 and speed > 6.0 and not line_lock and not hb_straighten:
		var slide_s := smoothstep(0.1, 0.35, absf(slip_angle))
		if slide_s > 0.0:
			var vdir := (vel - up * vel.dot(up)).normalized()
			var side := vdir.cross(up)
			apply_central_force(side * steer_input * DRIFT_STEER * mass * slide_s * smoothstep(6.0, 14.0, speed))

	# counter-steer: steering into the slide catches the rotation (the yaw follows the steering back
	# towards the direction of travel) – on throttle only partly, so a held power-drift stays a drift
	if _counter > 0.0 and grounded_wheels >= 3 and speed > 4.0 and not hb_straighten:
		var yaw_c := angular_velocity.dot(up)
		var want_c := -slip_angle * 2.4 * _counter
		var k_c := COUNTER_K * _counter * lerpf(1.0, 0.45, smoothstep(0.5, 1.0, throttle))
		apply_torque(up * (want_c - yaw_c) * mass * k_c)

	# calmer cars: damp the rotation while sliding (not in slow turns or donuts at low speed)
	if yaw_damp > 0.0 and grounded_wheels >= 3 and speed > 8.0:
		var slide_y := smoothstep(0.1, 0.4, absf(slip_angle))
		apply_torque(-up * angular_velocity.dot(up) * yaw_damp * mass * slide_y)

	# handbrake in a drift: turn the nose back towards the direction of travel (a yaw rate proportional
	# to the slip, the car's own rotation damped) and take the sideways slide out
	if hb_straighten and grounded_wheels >= 3 and speed > 3.0:
		var yaw := angular_velocity.dot(up)
		var want := -slip_angle * HB_ALIGN
		apply_torque(up * (want - yaw) * mass * 1.8)
		var v_side := vel.dot(right)
		apply_central_force(-right * v_side * mass * 0.8 * smoothstep(0.02, 0.15, absf(slip_angle)))

	# at speed: damp any rotation beyond what the steering asks for (the car doesn't pendulum after a
	# quick lane change) – not with the handbrake pulled or flat out in a drift, so drifting still works
	var hs_y := smoothstep(20.0, 40.0, speed)
	if hs_y > 0.0 and grounded_wheels >= 3 and not handbrake and forward_speed > 0.0:
		var wb := absf(float(body_spec["axle_r"]) - float(body_spec["axle_f"]))
		var yaw_ref := -forward_speed * tan(steer_angle) / maxf(wb, 1.0)
		var excess := angular_velocity.dot(up) - yaw_ref
		var k := hs_y * (1.0 - 0.7 * smoothstep(0.6, 1.0, throttle) * smoothstep(0.2, 0.5, absf(slip_angle)))
		apply_torque(-up * excess * mass * 1.2 * k)
	# ESP: from walking pace up, any rotation beyond the steering is braked away (no drifting)
	if esp_on and grounded_wheels >= 3 and not handbrake and forward_speed > 4.0:
		var wb2 := absf(float(body_spec["axle_r"]) - float(body_spec["axle_f"]))
		var excess2 := angular_velocity.dot(up) + forward_speed * tan(steer_angle) / maxf(wb2, 1.0)
		if absf(excess2) > 0.12 or absf(slip_angle) > 0.08:
			esp_active = true
		apply_torque(-up * excess2 * mass * 2.5 * smoothstep(4.0, 10.0, forward_speed))

	# anti-roll bars
	for pair in [[0, 1], [2, 3]]:
		var wl: Dictionary = wheels[pair[0]]
		var wr: Dictionary = wheels[pair[1]]
		if wl["grounded"] and wr["grounded"]:
			var diff := float(wl["compression"]) - float(wr["compression"])
			var f := diff * antiroll_k
			apply_force(up * f, (wl["ray"] as RayCast3D).global_position - global_position)
			apply_force(-up * f, (wr["ray"] as RayCast3D).global_position - global_position)

	# aero: drag + downforce
	apply_central_force(-vel * speed * DRAG)
	if grounded_wheels > 0:
		apply_central_force(-up * speed * speed * 1.4)
	surface_name = str(wheels[2]["surface"])
	braking_visual = brake_input > 0.1 or (handbrake and speed > 1.0)


func _check_hits(delta: float) -> void:
	_hit_cooldown -= delta
	var dv := (linear_velocity - _prev_velocity).length()
	if get_contact_count() > 0 and dv > 3.5 and _hit_cooldown <= 0.0:
		_hit_cooldown = 0.35
		wall_hit.emit(dv)
	_prev_velocity = linear_velocity


func _check_flip(delta: float) -> void:
	if global_transform.basis.y.dot(Vector3.UP) < 0.35 and speed < 4.0:
		flip_timer += delta
		if flip_timer > 2.5:
			reset_to_track()
	else:
		flip_timer = 0.0
	var ky := arena_kill_y if respawn_fn.is_valid() else (float(track.kill_y) if track else -20.0)
	if global_position.y < ky:
		reset_to_track()


## Car transform interpolated between the last two physics steps (smooth at any frame rate).
## Squash and stretch of the body from the drawn car's acceleration (a damped wobble).
func _update_jelly(delta: float) -> void:
	if body.model_root == null or delta <= 0.0:
		return
	var xf := body.global_transform
	if not _jelly_init:
		_jelly_init = true
		_jelly_pos = xf.origin
		return
	var vel := (xf.origin - _jelly_pos) / delta
	_jelly_pos = xf.origin
	var acc := (vel - _jelly_vel) / delta
	_jelly_vel = vel
	acc = acc.limit_length(60.0)
	var local := xf.basis.inverse() * acc
	# a stiff, barely damped spring: the body keeps wobbling after every bump
	var k := 180.0
	var c := 3.2
	var force := Vector3(-local.x * 0.0022, -local.y * 0.003, -local.z * 0.0016) * k * jelly
	var a := force - _jelly * k - _jelly_v * c
	_jelly_v += a * delta
	_jelly += _jelly_v * delta
	_jelly = _jelly.clamp(Vector3(-0.12, -0.16, -0.1), Vector3(0.12, 0.16, 0.1))
	var sy := 1.0 + _jelly.y
	var sxz := 1.0 / sqrt(maxf(sy, 0.5))   # keeps its volume: squashed flat, it bulges out
	var shear := Basis(Vector3(1, 0, 0), Vector3(_jelly.x, 1, _jelly.z), Vector3(0, 0, 1))
	body.model_root.transform = Transform3D(shear * Basis.from_scale(Vector3(sxz, sy, sxz)), Vector3.ZERO)


func visual_transform() -> Transform3D:
	if is_display:
		return global_transform
	return _xf_prev.interpolate_with(_xf_curr, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))


func reset_to_track() -> void:
	flip_timer = 0.0
	if respawn_fn.is_valid():
		global_transform = respawn_fn.call()
	elif track == null:
		global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	else:
		var proj: Array = track.project(global_position, track_hint)
		var lateral := clampf(float(proj[2]), -float(track.half_w) + 2.5, float(track.half_w) - 2.5)
		global_transform = track.transform_at(int(proj[0]), lateral, 0.6)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_xf_prev = global_transform
	_xf_curr = global_transform
	gear = 1
	boost = 0.0
	for w in wheels:
		w["spin"] = 0.0
		w.erase("f_lat")


## Lifts the car: `m` metres more ride height and the same again as extra spring travel, so it can
## crawl over logs and land jumps. The static sag stays the same (same spring rate).
func set_lift(m: float) -> void:
	# longer springs from the same mounts: the rest length grows by `m`, so the same load leaves
	# the body `m` higher (moving the mounts up as well would cancel that out)
	var d := m - lift
	lift = m
	for w in wheels:
		var ray: RayCast3D = w["ray"]
		ray.target_position = Vector3(0, -(SUSP_TRAVEL + lift + radius), 0)
		w["spring_len"] = float(w["spring_len"]) + d
	# the body sits higher, keep the mass where it was relative to the ground (no easy roll-overs)
	center_of_mass = Vector3(0, 0.42 - lift, 0.05)


func place(xf: Transform3D) -> void:
	global_transform = xf
	_xf_prev = xf
	_xf_curr = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	# forget the tyres' state from before (spin, built-up side force, suspension travel): carried over
	# a teleport it would kick the car away on the first step
	for w in wheels:
		w["spin"] = 0.0
		w.erase("f_lat")
		w["prev_compression"] = w["compression"]
	_net_pos = xf.origin
	_net_rot = xf.basis.get_rotation_quaternion()


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------
func _update_wheel_visuals(delta: float) -> void:
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var pivot: Node3D = w["pivot"]
		var spin_node: Node3D = w["spin_node"]
		var mount: Vector3 = w["mount"]
		var y := mount.y - float(w["spring_len"])
		pivot.position.y = lerpf(pivot.position.y, y, 1.0 - exp(-delta * 30.0))
		if w["front"]:
			pivot.rotation.y = -steer_angle
		var surface_speed := float(w["v_long"]) + float(w["spin"])
		if is_remote:
			surface_speed = forward_speed
		w["rot"] = wrapf(float(w["rot"]) - surface_speed / radius * delta, -TAU, TAU)
		spin_node.rotation.x = w["rot"]


func _update_lights() -> void:
	if body == null:
		return
	var reversing := gear == -1
	body.set_lights(headlights, braking_visual, reversing)


func set_paint(p: Dictionary) -> void:
	paint = p
	if body:
		body.set_paint(p)


func speed_kmh() -> float:
	return speed * 3.6


func drift_angle_deg() -> float:
	return rad_to_deg(absf(slip_angle))


func is_sliding() -> bool:
	return total_slip > 3.0


# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
func get_net_state(progress: float, lap: int, drift_total: float, best_chain := 0.0, chain := 0.0) -> Array:
	var flags := 0
	if braking_visual:
		flags |= 1
	if headlights:
		flags |= 2
	if gear == -1:
		flags |= 4
	if nitro_active:
		flags |= 8
	if line_lock:
		flags |= 16
	if underglow and underglow.manual:
		flags |= 32
	if not engine_on:
		flags |= 64
	var rear_slip := 0.0
	var front_slip := 0.0
	if wheels.size() == 4:
		rear_slip = (float(wheels[2]["slip"]) + float(wheels[3]["slip"])) * 0.5
		front_slip = (float(wheels[0]["slip"]) + float(wheels[1]["slip"])) * 0.5
	return [global_position, global_transform.basis.get_rotation_quaternion(), linear_velocity, steer_angle,
		rpm, flags, progress, lap, drift_total, rear_slip, front_slip, throttle, boost, best_chain, chain]


func apply_net_state(s: Array) -> void:
	if s.size() < 13:
		return
	_net_pos = s[0]
	_net_rot = s[1]
	_net_vel = s[2]
	steer_angle = s[3]
	rpm = s[4]
	remote_flags = s[5]
	remote_progress = s[6]
	remote_lap = s[7]
	remote_drift = s[8]
	var rear_slip: float = s[9]
	var front_slip: float = s[10]
	throttle = s[11]
	boost = s[12]
	if s.size() >= 15:
		remote_best_chain = s[13]
		remote_chain = s[14]
		trail_active = remote_chain >= DRIFT_TRAIL_POINTS
	braking_visual = (remote_flags & 1) != 0
	headlights = (remote_flags & 2) != 0
	gear = -1 if (remote_flags & 4) != 0 else 1
	nitro_active = (remote_flags & 8) != 0
	line_lock = (remote_flags & 16) != 0
	if underglow:
		underglow.manual = (remote_flags & 32) != 0
	engine_on = (remote_flags & 64) == 0
	if wheels.size() == 4:
		wheels[0]["slip"] = front_slip
		wheels[1]["slip"] = front_slip
		wheels[2]["slip"] = rear_slip
		wheels[3]["slip"] = rear_slip
	total_slip = rear_slip * 2.0 + front_slip * 2.0
	_net_time = 0.0
	if not _net_has:
		_net_has = true
		global_transform = Transform3D(Basis(_net_rot), _net_pos)


func _remote_step(delta: float) -> void:
	# the other player's engine switched off / started: its sound fades out / comes back
	engine_level = move_toward(engine_level, 1.0 if engine_on else 0.0, delta * (5.0 if engine_on else 1.4))
	if not _net_has:
		return
	_update_backfire(delta)
	_prev_throttle = throttle
	_net_time += delta
	if replay_driven:
		# a replay sets the exact (interpolated) pose itself
		global_transform = Transform3D(Basis(_net_rot), _net_pos)
	else:
		var predicted := _net_pos + _net_vel * minf(_net_time, 0.25)
		var cur := global_transform
		var pos := cur.origin.lerp(predicted, 1.0 - exp(-delta * 14.0))
		if pos.distance_to(predicted) > 12.0:
			pos = predicted
		var rot := cur.basis.get_rotation_quaternion().slerp(_net_rot, 1.0 - exp(-delta * 14.0))
		global_transform = Transform3D(Basis(rot), pos)
	linear_velocity = _net_vel
	speed = _net_vel.length()
	var fwd := -global_transform.basis.z
	forward_speed = _net_vel.dot(fwd)
	var local_vel := global_transform.basis.inverse() * _net_vel
	slip_angle = atan2(local_vel.x, -local_vel.z) if speed > 3.0 else 0.0
	for w in wheels:
		var mount: Vector3 = w["mount"]
		w["contact"] = global_transform * Vector3(mount.x, 0.0, mount.z)
		w["grounded"] = true
		w["normal"] = Vector3.UP
		w["v_long"] = forward_speed
