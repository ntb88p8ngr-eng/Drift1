extends Node
## AI opponents for races. Offline and on the online host they are real physics cars driven by this
## controller (they collide like other players' cars); online the host sends their state to everybody
## like a player's and reports their results. The drivers follow a racing line (towards the inside of
## the corners), look ahead up to 250 m and brake for what comes (grip, rain), recover from spins
## and get put back on the road when they are stuck.

const Car = preload("res://scripts/car/car.gd")

## corner: share of the cornering speed they dare, throttle: how hard they accelerate,
## brake: braking distance factor (> 1 = earlier), line: how much they use the racing line,
## err: random mistakes (late braking, wobbly steering), vmax: top speed they go for (m/s)
const LEVELS := [
	{"name": "Leicht", "corner": 0.64, "throttle": 0.7, "brake": 1.45, "line": 0.3, "err": 0.12, "vmax": 36.0},
	{"name": "Mittel", "corner": 0.8, "throttle": 0.88, "brake": 1.2, "line": 0.6, "err": 0.07, "vmax": 50.0},
	{"name": "Schwer", "corner": 0.95, "throttle": 1.0, "brake": 1.0, "line": 0.85, "err": 0.035, "vmax": 80.0},
	{"name": "Profi", "corner": 1.03, "throttle": 1.0, "brake": 0.9, "line": 1.0, "err": 0.015, "vmax": 95.0},
]
const NAMES := ["Kenta", "Mika", "Ryo", "Sora", "Daigo", "Yuki", "Hana", "Taro"]
const BOT_ID0 := 1000

var world
var level := 1
var bots: Array = []           # see add_bot
var _net_t := 0.0
var _rng := RandomNumberGenerator.new()


## The opponents of a race: [{id, name, car, paint}] (the same list goes to every machine online).
static func make_roster(count: int, seed_v: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var out: Array = []
	var cars: Array = Game.CARS.keys()
	var names := NAMES.duplicate()
	for k in clampi(count, 0, 7):
		var ni := r.randi() % names.size()
		out.append({"id": BOT_ID0 + k, "name": "KI " + str(names[ni]), "car": str(cars[r.randi() % cars.size()]),
			"paint": str(Game.PAINTS[r.randi() % Game.PAINTS.size()]["id"])})
		names.remove_at(ni)
	return out


func add_bot(id: int, car) -> void:
	var b := {"id": id, "car": car, "lap": 0, "last_prog": -1.0, "crossed": false, "lap_start": 0.0, "finished": false,
		"time": 0.0, "best": 0.0, "stuck_t": 0.0, "off_t": 0.0, "wrong_t": 0.0, "lane": _rng.randf_range(-1.0, 1.0),
		"lane_t": 0.0, "err": 0.0, "err_t": 0.0, "progress": 0.0}
	bots.append(b)
	car.ai_fn = _drive.bind(b)
	car.respawn_fn = Callable()


func is_bot(id: int) -> bool:
	for b in bots:
		if int(b["id"]) == id:
			return true
	return false


# ---------------------------------------------------------------------------
# Per physics step: progress, laps, network
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if world == null or not world.is_loaded:
		return
	var tr = world.track
	var length: float = tr.length
	for b in bots:
		var car = b["car"]
		if not is_instance_valid(car):
			continue
		var proj: Array = tr.project(car.global_position, car.track_hint)
		var prog: float = proj[1]
		b["progress"] = prog
		var last: float = b["last_prog"]
		if last >= 0.0 and world.state == "running" and not bool(b["finished"]):
			if last > length * 0.8 and prog < length * 0.2:
				if not bool(b["crossed"]):
					b["crossed"] = true
					b["lap_start"] = world.race_time
				else:
					var t: float = world.race_time - float(b["lap_start"])
					b["lap_start"] = world.race_time
					b["lap"] = int(b["lap"]) + 1
					if float(b["best"]) <= 0.0 or t < float(b["best"]):
						b["best"] = t
					if int(b["lap"]) >= int(world.laps_total):
						_bot_finished(b)
			elif last < length * 0.2 and prog > length * 0.8 and bool(b["crossed"]):
				b["lap"] = maxi(int(b["lap"]) - 1, 0)      # rolled back over the line
		b["last_prog"] = prog
		# the scoreboards read the same fields as for remote players
		car.remote_lap = int(b["lap"])
		car.remote_progress = total_progress(b)
		car.remote_drift = 0.0
		_watchdog(b, delta)
	# online host: everybody sees the bots
	if world.online and Net.is_host():
		_net_t -= delta
		if _net_t <= 0.0:
			_net_t = 1.0 / 30.0
			for b in bots:
				var c = b["car"]
				if is_instance_valid(c):
					Net.send_bot_state(int(b["id"]), c.get_net_state(total_progress(b), int(b["lap"]), 0.0, 0.0, 0.0))


func total_progress(b: Dictionary) -> float:
	var length: float = world.track.length
	if not bool(b["crossed"]):
		return float(b["progress"]) - length
	return int(b["lap"]) * length + float(b["progress"])


func _bot_finished(b: Dictionary) -> void:
	b["finished"] = true
	b["time"] = world.race_time
	var car = b["car"]
	if world.online and Net.is_host():
		Net.report_bot_result(int(b["id"]), {"time": b["time"], "best_lap": b["best"], "drift": 0.0, "finished": true,
			"name": car.player_name, "car": car.car_id})


## Stuck, off the road or the wrong way round for too long: back onto the road.
func _watchdog(b: Dictionary, delta: float) -> void:
	var car = b["car"]
	if world.state != "running":
		return
	var tr = world.track
	var i: int = maxi(car.track_hint, 0)
	var fwd: Vector3 = -car.global_transform.basis.z
	var wrong: bool = fwd.dot(tr.tangents[i]) < -0.2 and car.speed > 2.0
	b["wrong_t"] = float(b["wrong_t"]) + delta if wrong else 0.0
	b["stuck_t"] = float(b["stuck_t"]) + delta if car.speed < 1.2 else 0.0
	var off: bool = tr.distance_to_center(car.global_position) > float(tr.half_w) + 7.0
	b["off_t"] = float(b["off_t"]) + delta if off else 0.0
	if float(b["stuck_t"]) > 3.5 or float(b["wrong_t"]) > 2.5 or float(b["off_t"]) > 5.0:
		car.reset_to_track()
		b["stuck_t"] = 0.0
		b["wrong_t"] = 0.0
		b["off_t"] = 0.0


# ---------------------------------------------------------------------------
# Driving: [throttle, brake, steer, handbrake]
# ---------------------------------------------------------------------------
func _drive(b: Dictionary) -> Array:
	var car = b["car"]
	if world.state != "running" or bool(b["finished"]) and car.speed < 3.0:
		return [0.0, 0.0, 0.0, true]
	var lv: Dictionary = LEVELS[clampi(level, 0, LEVELS.size() - 1)]
	var tr = world.track
	var n: int = tr.sample_count()
	var sp: float = tr.SPACING
	var i: int = maxi(car.track_hint, 0)
	var v: float = car.speed
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	# slowly wandering lane (so they do not all drive on one line) and random mistakes
	b["lane_t"] = float(b["lane_t"]) - dt
	if float(b["lane_t"]) <= 0.0:
		b["lane_t"] = _rng.randf_range(3.0, 8.0)
		b["lane"] = clampf(float(b["lane"]) + _rng.randf_range(-0.6, 0.6), -1.0, 1.0)
	b["err_t"] = float(b["err_t"]) - dt
	if float(b["err_t"]) <= 0.0:
		b["err_t"] = _rng.randf_range(2.0, 6.0)
		b["err"] = _rng.randf_range(-1.0, 1.0) * float(lv["err"])
	# racing line at the look-ahead point: towards the inside of the corner
	var look := clampf(7.0 + v * 0.55, 9.0, 42.0)
	var ti := (i + int(look / sp)) % n
	var k_line := 0.0
	for d in range(-6, 7, 3):
		k_line += tr.curvature[(ti + d + n) % n]
	k_line /= 5.0
	var hw: float = tr.half_w
	var lat := -clampf(k_line * 260.0, -1.0, 1.0) * hw * 0.6 * float(lv["line"])
	lat += float(b["lane"]) * hw * 0.25 * (1.0 - absf(k_line) * 120.0)
	lat = clampf(lat, -hw + 1.6, hw - 1.6)
	var target: Vector3 = tr.samples[ti] + tr.rights[ti] * lat
	# pure pursuit: the wheel angle that drives through the target, divided by what the car's
	# speed-sensitive steering gives for a full input
	var xf: Transform3D = car.global_transform
	var to := target - xf.origin
	to.y = 0.0
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var alpha := fwd.signed_angle_to(to.normalized(), Vector3.UP)      # + = target to the left
	var wb := absf(float(car.body_spec["axle_r"]) - float(car.body_spec["axle_f"]))
	var delta_w := atan(2.0 * wb * sin(alpha) / maxf(to.length(), 4.0))
	var vs := absf(car.forward_speed) / 18.0
	var speed_factor := 1.0 / (1.0 + vs * vs)
	var steer := clampf(-delta_w / maxf(car.steer_lock * speed_factor, 0.01), -1.0, 1.0)
	steer += float(b["err"]) * 0.3 * sin(Time.get_ticks_msec() * 0.003)
	# catching a slide: steer into it, lift
	var slide: float = car.slip_angle
	if absf(slide) > 0.12 and v > 6.0:
		steer = clampf(steer + slide * 1.2, -1.0, 1.0)
	# target speed from the corners ahead
	var wet: float = tr.wetness
	var a_lat := 9.81 * 1.05 * (1.0 - 0.3 * wet) * float(lv["corner"])
	var decel := 9.81 * 0.95 * (1.0 - 0.3 * wet) / float(lv["brake"])
	var v_target: float = lv["vmax"]
	var reach := int(clampf(v * v / (2.0 * decel) + 40.0, 40.0, 260.0) / sp)
	for d in range(2, reach, 3):
		var k := 0.0
		for e in range(-2, 3, 2):
			k = maxf(k, absf(tr.curvature[(i + d + e) % n]))
		if k < 1e-4:
			continue
		var v_c := sqrt(a_lat / k)
		var dist := d * sp - 6.0
		var v_now := sqrt(v_c * v_c + 2.0 * decel * maxf(dist, 0.0))
		v_target = minf(v_target, v_now)
	v_target *= 1.0 + float(b["err"])
	var thr := 0.0
	var brk := 0.0
	if v < v_target - 3.0:
		thr = float(lv["throttle"])
	elif v < v_target:
		thr = float(lv["throttle"]) * 0.55
	elif v > v_target + 1.5:
		brk = clampf((v - v_target) / 6.0, 0.25, 1.0)
	if absf(slide) > 0.22:
		thr *= 0.35
	if bool(b["finished"]):
		thr = 0.0
		brk = 0.4
	return [thr, brk, steer, false]
