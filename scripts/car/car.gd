extends RigidBody3D
## Drift-tuned raycast vehicle.
## - 4 raycast suspensions (spring + damper + anti-roll bars)
## - tyre model with slip-angle curve and a friction circle, so wheelspin / handbrake break rear grip
## - engine with torque curve, rev limiter, turbo spool & blow-off, automatic or manual gearbox
## - optional counter-steer assist
## Remote (network) cars use the same node as a kinematic, interpolated puppet.

signal shifted(up: bool, boost: float)
signal blow_off(amount: float)
signal wall_hit(strength: float)
signal backfire

const CarBody = preload("res://scripts/car/car_body.gd")
const CarAudio = preload("res://scripts/car/car_audio.gd")
const TireFX = preload("res://scripts/car/tire_fx.gd")

const LAYER_WORLD := 1
const LAYER_LOCAL := 2
const LAYER_REMOTE := 4

const SUSP_TRAVEL := 0.30
const SAG := 0.09
const PEAK_SLIP := 0.14         # rad – slip angle at maximum lateral grip
const SLIDE_GRIP := 0.78        # lateral grip multiplier when fully sliding
const STEER_SPEED := 5.5        # rad/s

# --- configuration (set before adding to the tree) ---
var car_id := "r34"
var paint := {}
var player_name := "Driver"
var peer_id := 1
var is_remote := false
var is_display := false
var transmission := "auto"
var remote_collisions := true
var track = null
var skidmarks = null

# --- spec ---
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
var turbo_gain := 0.0
var grip := 1.0
var steer_lock := 0.75
var spring_k := 40000.0
var damper_c := 3500.0
var antiroll_k := 9000.0

# --- runtime state ---
var body: CarBody
var audio: CarAudio
var fx: TireFX
var wheels: Array = []
var input_enabled := true
var controls_locked := false
var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var steer_angle := 0.0
var handbrake := false
var gear := 1
var rpm := 900.0
var boost := 0.0
var shift_timer := 0.0
var limiter_timer := 0.0
var reverse_timer := 0.0
var speed := 0.0            # m/s, magnitude
var forward_speed := 0.0    # m/s, signed along heading
var slip_angle := 0.0       # rad, body slip (velocity vs heading)
var grounded_wheels := 0
var headlights := false
var braking_visual := false
var track_hint := -1
var surface_name := "asphalt"
var total_slip := 0.0
var flip_timer := 0.0
var _prev_throttle := 0.0
var _prev_velocity := Vector3.ZERO
var _hit_cooldown := 0.0
var _backfire_cooldown := 0.0

# remote interpolation
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_vel := Vector3.ZERO
var _net_time := 0.0
var _net_has := false
var remote_flags := 0
var remote_progress := 0.0
var remote_lap := 0
var remote_drift := 0.0


func _ready() -> void:
	spec = Game.get_car(car_id)
	body_spec = CarBody.BODIES.get(spec["body"], CarBody.BODIES["r34"])
	radius = body_spec["wheel_r"]
	mass = spec["mass"]
	max_torque = spec["torque"]
	redline = spec["redline"]
	idle_rpm = spec["idle"]
	gears = spec["gears"]
	reverse_ratio = spec["reverse"]
	final_drive = spec["final"]
	rear_split = spec["rear_split"]
	turbo_gain = spec["turbo"]
	grip = spec["grip"]
	steer_lock = deg_to_rad(float(spec["steer_lock"]))
	rpm = idle_rpm
	var static_load := mass * 9.8 / 4.0
	spring_k = static_load / SAG
	damper_c = 2.0 * 0.38 * sqrt(spring_k * mass / 4.0)
	antiroll_k = spring_k * 0.35

	body = CarBody.new()
	body.name = "Body"
	add_child(body)
	body.build(spec["body"], paint, not is_remote and not is_display)

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
		audio.positional = is_remote
		add_child(audio)
	_update_lights()


func _setup_physics() -> void:
	var length: float = body_spec["length"]
	var hw: float = body_spec["track"] + 0.12
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(hw * 2.0, 0.62, length * 0.96)
	cs.shape = box
	cs.position = Vector3(0, float(body_spec["base"]) + 0.36, 0)
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var cab := BoxShape3D.new()
	cab.size = Vector3(hw * 1.5, 0.38, length * 0.42)
	cs2.shape = cab
	cs2.position = Vector3(0, float(body_spec["roof"]) - 0.22, 0.3)
	add_child(cs2)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.3
	pm.bounce = 0.1
	physics_material_override = pm
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.42, 0.05)
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
	else:
		collision_layer = LAYER_LOCAL
		collision_mask = LAYER_WORLD | (LAYER_REMOTE if remote_collisions else 0)


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
		ray.target_position = Vector3(0, -(SUSP_TRAVEL + radius), 0)
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
	_update_wheel_visuals(delta)
	_update_lights()


func _read_input(delta: float) -> void:
	var thr := 0.0
	var brk := 0.0
	var steer_target := 0.0
	var hb := false
	if input_enabled:
		thr = Input.get_action_strength("accelerate")
		brk = Input.get_action_strength("brake")
		steer_target = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		hb = Input.is_action_pressed("handbrake")
		if Input.is_action_just_pressed("toggle_transmission"):
			transmission = "manual" if transmission == "auto" else "auto"
			if transmission == "auto" and gear == 0:
				gear = 1
		if transmission == "manual" and not controls_locked:
			if Input.is_action_just_pressed("shift_up"):
				_shift(1)
			if Input.is_action_just_pressed("shift_down"):
				_shift(-1)
		if Input.is_action_just_pressed("lights"):
			headlights = not headlights
	# smoothed steering for digital input
	var rate := 4.5 if absf(steer_target) > absf(steer_input) and signf(steer_target) == signf(steer_input) else 7.0
	steer_input = move_toward(steer_input, steer_target, rate * delta)
	handbrake = hb
	if controls_locked:
		throttle = thr
		brake_input = 0.0
		handbrake = true
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
	shift_timer = 0.3 if transmission == "auto" else 0.16
	if up and boost > 0.25:
		blow_off.emit(boost)
		boost *= 0.45
	shifted.emit(dir > 0, boost)


func _torque_at(r: float) -> float:
	var t := clampf(r / redline, 0.0, 1.1)
	var c := (0.52 + 1.25 * t - 0.95 * t * t) / 0.931
	var tq := max_torque * clampf(c, 0.3, 1.0)
	if turbo_gain > 0.0:
		tq *= lerpf(1.0 - turbo_gain, 1.0, boost)
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

	# --- track / surface lookup (one query per tick for the whole car) ---
	if track:
		var proj: Array = track.project(global_position, track_hint)
		track_hint = proj[0]

	# --- steering (speed sensitive + counter-steer assist) ---
	var speed_factor := clampf(1.0 - absf(forward_speed) / 55.0, 0.4, 1.0)
	var target := steer_input * steer_lock * speed_factor
	if forward_speed > 4.0 and absf(slip_angle) > 0.08:
		var assist := float(Game.settings.get("steer_assist", 0.5))
		target += clampf(slip_angle, -steer_lock, steer_lock) * assist * (1.0 - absf(steer_input) * 0.4)
	target = clampf(target, -steer_lock, steer_lock)
	steer_angle = move_toward(steer_angle, target, STEER_SPEED * delta)

	# --- gearbox / engine ---
	shift_timer = maxf(shift_timer - delta, 0.0)
	limiter_timer = maxf(limiter_timer - delta, 0.0)
	var driven_speed := 0.0
	var driven_count := 0.0
	for w in wheels:
		var driven: bool = (w["front"] and rear_split < 1.0) or (not w["front"] and rear_split > 0.0)
		if driven:
			driven_speed += float(w["v_long"]) + float(w["spin"])
			driven_count += 1.0
	if driven_count > 0.0:
		driven_speed /= driven_count
	var ratio := _gear_ratio()
	var wheel_rpm := driven_speed / radius * 60.0 / TAU
	var coupled_rpm := absf(wheel_rpm * ratio)
	var engaged := ratio != 0.0 and shift_timer <= 0.0 and not controls_locked
	if engaged:
		var floor_rpm := idle_rpm
		if absi(gear) == 1:
			floor_rpm = idle_rpm + throttle * (redline * 0.5 - idle_rpm)
		var target_rpm := maxf(coupled_rpm, floor_rpm)
		rpm = lerpf(rpm, target_rpm, 1.0 - exp(-delta * 18.0))
	else:
		var free_target := idle_rpm + throttle * (redline * 1.02 - idle_rpm)
		rpm = move_toward(rpm, free_target, (7000.0 if free_target > rpm else 4000.0) * delta)
	if rpm >= redline:
		rpm = redline
		limiter_timer = 0.07
	rpm = maxf(rpm, idle_rpm * 0.9)

	# turbo spool
	if turbo_gain > 0.0:
		var boost_target := 0.0
		if throttle > 0.4:
			boost_target = clampf((rpm - redline * 0.3) / (redline * 0.35), 0.0, 1.0) * throttle
		boost = move_toward(boost, boost_target, (0.9 if boost_target > boost else 3.0) * delta)
		if _prev_throttle > 0.6 and throttle < 0.2 and boost > 0.35:
			blow_off.emit(boost)
			boost *= 0.3
	# backfire on lift-off at high rpm
	_backfire_cooldown -= delta
	if _prev_throttle > 0.7 and throttle < 0.1 and rpm > redline * 0.6 and _backfire_cooldown <= 0.0:
		_backfire_cooldown = 0.6
		backfire.emit()
	_prev_throttle = throttle

	var drive_total := 0.0
	if engaged:
		var tq := _torque_at(rpm) * throttle
		if limiter_timer > 0.0:
			tq = 0.0
		if throttle < 0.05:
			tq = -max_torque * 0.14 * (rpm / redline) * signf(ratio * driven_speed) * signf(ratio)
		drive_total = tq * ratio * 0.85 / radius

	# automatic gearbox
	if transmission == "auto" and shift_timer <= 0.0 and gear >= 1 and not controls_locked:
		var ground_rpm := absf(forward_speed / radius * 60.0 / TAU * ratio)
		if rpm > redline * 0.93 and gear < gears.size() and throttle > 0.2:
			_shift(1)
		elif gear > 1 and ground_rpm < redline * 0.42:
			_shift(-1)
		elif gear > 1 and throttle > 0.95 and ground_rpm < redline * 0.5:
			var lower := absf(forward_speed / radius * 60.0 / TAU * float(gears[gear - 2]) * final_drive)
			if lower < redline * 0.8:
				_shift(-1)

	# --- per wheel forces ---
	grounded_wheels = 0
	total_slip = 0.0
	var front_brake := 0.62
	var brake_force_max := mass * 9.8 * 1.25
	var mass_per_wheel := mass / 4.0
	for i in 4:
		var w: Dictionary = wheels[i]
		var ray: RayCast3D = w["ray"]
		ray.force_raycast_update()
		w["prev_compression"] = w["compression"]
		if not ray.is_colliding():
			w["grounded"] = false
			w["compression"] = 0.0
			w["spring_len"] = SUSP_TRAVEL
			w["load"] = 0.0
			w["slip"] = 0.0
			w["spin"] = move_toward(float(w["spin"]), 0.0, 20.0 * delta)
			continue
		grounded_wheels += 1
		var hit := ray.get_collision_point()
		var n := ray.get_collision_normal()
		var mount_g := ray.global_position
		var dist := mount_g.distance_to(hit)
		var spring_len := clampf(dist - radius, 0.0, SUSP_TRAVEL)
		var compression := SUSP_TRAVEL - spring_len
		var comp_vel := (compression - float(w["prev_compression"])) / delta
		var f_susp := spring_k * compression + damper_c * comp_vel
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

		# surface
		var sg := 1.0
		var sname := "asphalt"
		if track and track_hint >= 0:
			var s: Array = track.surface_at(hit, track_hint)
			sg = s[0]
			sname = s[1]
		w["surface"] = sname

		# wheel frame
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
		var axle_grip := 1.03 if is_front else 0.97
		var max_f := grip * sg * axle_grip * wheel_load

		# longitudinal request
		var split := (1.0 - rear_split) if is_front else rear_split
		var f_drive := drive_total * split * 0.5
		var f_long := f_drive
		if brake_input > 0.01:
			var bias := front_brake if is_front else 1.0 - front_brake
			f_long -= clampf(v_long / 0.6, -1.0, 1.0) * brake_force_max * bias * 0.5 * brake_input
		var locked := false
		if handbrake and not is_front:
			f_long = -clampf(v_long / 0.4, -1.0, 1.0) * max_f * 0.95
			locked = absf(v_long) > 0.5
		f_long -= v_long * 12.0  # rolling resistance
		# parking hold when nearly stopped and no input
		if throttle < 0.02 and brake_input < 0.02 and absf(v_long) < 1.2 and speed < 1.5:
			f_long -= v_long * mass_per_wheel * 8.0

		# lateral: slip-angle curve
		var alpha := atan2(v_lat, maxf(absf(v_long), 3.5))
		var ratio_a := alpha / PEAK_SLIP
		var curve := 0.0
		if absf(ratio_a) <= 1.0:
			curve = ratio_a
		else:
			curve = signf(ratio_a) * lerpf(1.0, SLIDE_GRIP, clampf((absf(ratio_a) - 1.0) / 2.5, 0.0, 1.0))
		var f_lat := -curve * max_f
		# low speed: kill lateral creep directly
		if speed < 2.0:
			f_lat = clampf(-v_lat * mass_per_wheel * 6.0, -max_f, max_f)

		# friction circle – wheelspin / locked wheels eat lateral grip
		var spin_excess := 0.0
		var combined := sqrt(f_long * f_long + f_lat * f_lat)
		if combined > max_f and max_f > 0.0:
			if absf(f_long) > max_f * 0.98 or locked:
				spin_excess = (absf(f_drive) - max_f) / max_f if absf(f_drive) > max_f else 0.0
				f_long = clampf(f_long, -max_f, max_f) * 0.92
				var remaining := sqrt(maxf(max_f * max_f - f_long * f_long, 0.0))
				var lat_cap := maxf(remaining, max_f * (0.22 if locked else 0.3))
				f_lat = clampf(f_lat, -lat_cap, lat_cap)
			else:
				var s2 := max_f / combined
				f_long *= s2
				f_lat *= s2
		# wheelspin state (drives rpm and smoke)
		if spin_excess > 0.0 and absf(f_drive) > 0.0:
			w["spin"] = move_toward(float(w["spin"]), signf(f_drive) * minf(spin_excess * 10.0, 25.0), 60.0 * delta)
		else:
			w["spin"] = move_toward(float(w["spin"]), 0.0, 35.0 * delta)
		if locked:
			w["spin"] = -v_long

		var force_point := hit + up * 0.25 - global_position
		apply_force(w_fwd * f_long + w_right * f_lat, force_point)

		# slip value for smoke / sound / skidmarks (m/s of sliding)
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
	apply_central_force(-vel * speed * 0.42)
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
	if global_position.y < -20.0:
		reset_to_track()


func reset_to_track() -> void:
	flip_timer = 0.0
	if track == null:
		global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	else:
		var proj: Array = track.project(global_position, track_hint)
		var lateral := clampf(float(proj[2]), -float(track.half_w) + 2.5, float(track.half_w) - 2.5)
		global_transform = track.transform_at(int(proj[0]), lateral, 0.6)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gear = 1
	boost = 0.0
	for w in wheels:
		w["spin"] = 0.0


func place(xf: Transform3D) -> void:
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
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
func get_net_state(progress: float, lap: int, drift_total: float) -> Array:
	var flags := 0
	if braking_visual:
		flags |= 1
	if headlights:
		flags |= 2
	if gear == -1:
		flags |= 4
	var rear_slip := 0.0
	if wheels.size() == 4:
		rear_slip = (float(wheels[2]["slip"]) + float(wheels[3]["slip"])) * 0.5
	var front_slip := 0.0
	if wheels.size() == 4:
		front_slip = (float(wheels[0]["slip"]) + float(wheels[1]["slip"])) * 0.5
	return [global_position, global_transform.basis.get_rotation_quaternion(), linear_velocity, steer_angle,
		rpm, flags, progress, lap, drift_total, rear_slip, front_slip, throttle, boost]


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
	braking_visual = (remote_flags & 1) != 0
	headlights = (remote_flags & 2) != 0
	gear = -1 if (remote_flags & 4) != 0 else 1
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
	if not _net_has:
		return
	_net_time += delta
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
	# contact points for smoke / skidmarks
	for w in wheels:
		var mount: Vector3 = w["mount"]
		w["contact"] = global_transform * Vector3(mount.x, 0.0, mount.z)
		w["grounded"] = true
		w["normal"] = Vector3.UP
		w["v_long"] = forward_speed
