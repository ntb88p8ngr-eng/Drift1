extends Node
## AI opponents for races. Offline and on the online host they are real physics cars driven by this
## controller (they collide like other players' cars); online the host sends their state to everybody
## like a player's and reports their results. The drivers follow a racing line (towards the inside of
## the corners), look ahead up to 250 m and brake for what comes (grip, rain), recover from spins
## and get put back on the road when they are stuck.

const Car = preload("res://scripts/car/car.gd")
const BotProfiles = preload("res://scripts/admin/bot_profiles.gd")

## corner: share of the car's real cornering grip they use, throttle: how hard they accelerate,
## brake: braking distance factor (> 1 = earlier), line: how much they use the racing line,
## err: random mistakes (late braking, wobbly steering), vmax: top speed they go for (m/s),
## nitro: they use the nitro on the straights
const LEVELS := [
	{"name": "Leicht", "corner": 0.84, "throttle": 0.9, "brake": 1.25, "line": 0.45, "err": 0.07, "vmax": 60.0, "nitro": false, "grip": 1.0, "power": 1.0},
	{"name": "Mittel", "corner": 0.97, "throttle": 1.0, "brake": 1.08, "line": 0.8, "err": 0.035, "vmax": 95.0, "nitro": true, "grip": 1.0, "power": 1.0},
	# the top levels drive like a pro *and* get a little help (racing-game style): more tyre grip and power
	{"name": "Schwer", "corner": 1.06, "throttle": 1.0, "brake": 0.95, "line": 0.95, "err": 0.015, "vmax": 130.0, "nitro": true, "grip": 1.06, "power": 1.1},
	{"name": "Profi", "corner": 1.1, "throttle": 1.0, "brake": 0.86, "line": 1.0, "err": 0.006, "vmax": 150.0, "nitro": true, "grip": 1.12, "power": 1.2},
]
const NAMES := ["Kenta", "Mika", "Ryo", "Sora", "Daigo", "Yuki", "Hana", "Taro"]
const BOT_ID0 := 1000

var world
var level := 1
var bots: Array = []           # see add_bot
## Learned corner speeds: a factor per 20 m of track, lowered where a bot ran wide and raised a little
## on every clean pass – shared by all bots and kept for the session (per track and level)
const SEG := 10
static var _learned := {}
var seg_scale := PackedFloat32Array()
var _net_t := 0.0
var _rng := RandomNumberGenerator.new()
var best_laps: Array = []      # the bots' best laps this session: {time, name, car, speed, lat} (admin: set as default)
var default_line := {}         # a saved best lap the bots drive (BotProfiles.load_line), or {}


## The opponents of a race: [{id, name, car, paint, tuning}] (the same list goes to every machine online).
## `tuning`: the stages every bot gets on its car – the player's level (see player_tuning()).
static func make_roster(count: int, seed_v: int, tuning: Dictionary = {}) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var out: Array = []
	var cars: Array = []
	for id in Game.CARS:
		if not bool(Game.CARS[id].get("egg", false)):
			cars.append(id)
	var names := NAMES.duplicate()
	for k in clampi(count, 0, 7):
		var ni := r.randi() % names.size()
		var pers := BotProfiles.slot_personality(k)
		var all_p := BotProfiles.all_names()
		if pers == "" or not all_p.has(pers):
			pers = str(all_p[r.randi() % all_p.size()])
		out.append({"id": BOT_ID0 + k, "name": "KI " + str(names[ni]), "car": str(cars[r.randi() % cars.size()]),
			"paint": str(Game.PAINTS[r.randi() % Game.PAINTS.size()]["id"]), "tuning": tuning.duplicate(), "personality": pers})
		names.remove_at(ni)
	return out


## The tuning stages of the player's current car: the bots get the same level on theirs.
static func player_tuning() -> Dictionary:
	return Game.get_tuning(str(Game.settings.get("car", "r34")))


func add_bot(id: int, car, personality := "Ausgeglichen") -> void:
	var b := {"id": id, "car": car, "lap": 0, "last_prog": -1.0, "crossed": false, "lap_start": 0.0, "finished": false,
		"time": 0.0, "best": 0.0, "stuck_t": 0.0, "off_t": 0.0, "wrong_t": 0.0, "lane": _rng.randf_range(-1.0, 1.0),
		"lane_t": 0.0, "err": 0.0, "err_t": 0.0, "progress": 0.0, "personality": personality,
		"base_grip": car.grip, "base_torque": car.max_torque}
	bots.append(b)
	set_personality(b, personality)
	car.ai_fn = _drive.bind(b)
	car.respawn_fn = Callable()


## A bot's driving parameters: level + personality (+ live changes from the admin panel).
func set_personality(b: Dictionary, personality: String, overrides := {}) -> void:
	b["personality"] = personality
	var p := BotProfiles.resolve(LEVELS[clampi(level, 0, LEVELS.size() - 1)], personality)
	for k in overrides:
		p[k] = overrides[k]
	b["p"] = p
	var car = b["car"]
	if is_instance_valid(car):
		car.grip = float(b["base_grip"]) * float(p.get("grip", 1.0))
		car.max_torque = float(b["base_torque"]) * float(p.get("power", 1.0))


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
	if world._bots_parked:
		return      # a party minigame is on: the bots wait (no lap counting, no stuck resets)
	var tr = world.track
	var length: float = tr.length
	if seg_scale.is_empty():
		var key := "%s/%d" % [str(tr.track_id), level]
		if not _learned.has(key):
			var arr := PackedFloat32Array()
			arr.resize(int(ceil(float(tr.sample_count()) / SEG)))
			arr.fill(1.0)
			_learned[key] = arr
		seg_scale = _learned[key]
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
					_lap_done(b, t)
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
		_learn(b, delta)
		_record_line(b)
	# online host: everybody sees the bots
	if world.online and Net.is_host():
		_net_t -= delta
		if _net_t <= 0.0:
			_net_t = 1.0 / 30.0
			for b in bots:
				var c = b["car"]
				if is_instance_valid(c):
					Net.send_bot_state(int(b["id"]), c.get_net_state(total_progress(b), int(b["lap"]), 0.0, 0.0, 0.0))


## Speed and place across the road at every track sample of the current lap (for its best lap).
func _record_line(b: Dictionary) -> void:
	var car = b["car"]
	var tr = world.track
	var n: int = tr.sample_count()
	if not b.has("rec_v") or (b["rec_v"] as PackedFloat32Array).size() != n:
		var v := PackedFloat32Array()
		v.resize(n)
		v.fill(-1.0)
		b["rec_v"] = v
		var l := PackedFloat32Array()
		l.resize(n)
		b["rec_l"] = l
	var i: int = maxi(car.track_hint, 0)
	var rel: Vector3 = car.global_position - tr.samples[i]
	var rv: PackedFloat32Array = b["rec_v"]
	var rl: PackedFloat32Array = b["rec_l"]
	rv[i] = car.speed
	rl[i] = rel.dot(tr.rights[i])
	b["rec_v"] = rv
	b["rec_l"] = rl


func _lap_done(b: Dictionary, t: float) -> void:
	var rv: PackedFloat32Array = b.get("rec_v", PackedFloat32Array())
	if not rv.is_empty():
		# fill the samples it skipped (fast) from their neighbours
		var rl: PackedFloat32Array = b["rec_l"]
		var n := rv.size()
		var filled := 0
		for i in n:
			if rv[i] >= 0.0:
				filled += 1
		if filled > n * 0.6:
			var last_v := -1.0
			var last_l := 0.0
			for pass_i in 2:
				for i in n:
					if rv[i] >= 0.0:
						last_v = rv[i]
						last_l = rl[i]
					elif last_v >= 0.0:
						rv[i] = last_v
						rl[i] = last_l
			var car = b["car"]
			best_laps.append({"time": t, "name": car.player_name, "car": car.car_id, "speed": rv.duplicate(), "lat": rl.duplicate(),
				"personality": b.get("personality", "")})
			best_laps.sort_custom(func(x, y): return float(x["time"]) < float(y["time"]))
			if best_laps.size() > 10:
				best_laps.resize(10)
		rv.fill(-1.0)
		b["rec_v"] = rv


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
	var lv: Dictionary = b.get("p", LEVELS[clampi(level, 0, LEVELS.size() - 1)])
	var tr = world.track
	var n: int = tr.sample_count()
	if default_line.is_empty() and not b.has("line_checked"):
		b["line_checked"] = true
		var dl := BotProfiles.load_line(str(tr.track_id))
		if not dl.is_empty() and (dl["speed"] as PackedFloat32Array).size() == n:
			default_line = dl
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
	var lat := -clampf(k_line * _tune("LINEK", 260.0), -1.0, 1.0) * hw * float(lv.get("line_w", 0.75)) * float(lv["line"])
	lat += float(b["lane"]) * hw * 0.25 * float(lv.get("lane", 1.0)) * (1.0 - absf(k_line) * 120.0) * (1.0 - 0.7 * float(lv["line"]))
	if not default_line.is_empty():
		# the saved best lap: its line across the road
		lat = (default_line["lat"] as PackedFloat32Array)[ti]
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
	# the car's real (tuned) grip: better tyres and suspension let the bots corner faster too
	var g: float = car.grip
	var a_lat := 9.81 * g * (1.0 - 0.3 * wet) * float(lv["corner"]) * _tune("CORNER", 1.0)
	var decel := 9.81 * g * 0.95 * (1.0 - 0.3 * wet) / float(lv["brake"]) * minf(car.brake_gain, 1.3)
	var v_target: float = lv["vmax"]
	var reach := int(clampf(v * v / (2.0 * decel) + 40.0, 40.0, 260.0) / sp)
	for d in range(2, reach, 3):
		var k := 0.0
		for e in range(-2, 3, 2):
			k = maxf(k, absf(tr.curvature[(i + d + e) % n]))
		if k < 1e-4:
			continue
		var v_c := sqrt(a_lat * _seg_scale_at((i + d) % n) / k)
		var dist := d * sp - 6.0
		var v_now := sqrt(v_c * v_c + 2.0 * decel * maxf(dist, 0.0))
		v_target = minf(v_target, v_now)
	if not default_line.is_empty():
		# … and its speeds (a little ahead, so it brakes where that lap braked); never faster than grip allows
		var dv: PackedFloat32Array = default_line["speed"]
		var v_line := dv[(i + int(clampf(v * 0.35, 3.0, 25.0) / sp)) % n] * float(lv.get("pace", 1.0))
		v_target = minf(v_target * 1.12, v_line + 1.0)
	v_target *= 1.0 + float(b["err"])
	var thr := 0.0
	var brk := 0.0
	if v < v_target - 3.0:
		thr = float(lv["throttle"])
	elif v < v_target:
		thr = float(lv["throttle"]) * 0.55
	elif v > v_target + 1.5:
		brk = clampf((v - v_target) / 6.0, 0.25, 1.0)
	# edge guard: where will the car be in half a second? Beyond the asphalt -> more lock, lift, brake
	var rel: Vector3 = car.global_position - tr.samples[i]
	var lat_now: float = rel.dot(tr.rights[i])
	var lat_v: float = car.linear_velocity.dot(tr.rights[i])
	var pred := lat_now + lat_v * float(lv.get("pred", 0.5))
	var lim: float = float(tr.hws[i]) - float(lv.get("edge", 1.0))
	if absf(pred) > lim:
		var over := absf(pred) - lim
		steer = clampf(steer - signf(pred) * minf(over * _tune("EDGEK", 0.25), 0.8), -1.0, 1.0)
		thr *= clampf(1.0 - over * 0.3, 0.2, 1.0)
		if over > 1.5 and v > 15.0:
			brk = maxf(brk, clampf((over - 1.5) * 0.25, 0.0, 0.6))
	# sliding: progressively less throttle (power oversteer in the drift-happy cars costs time)
	var s0 := float(lv.get("slide0", 0.22))
	if absf(slide) > s0:
		thr *= clampf(1.0 - (absf(slide) - s0) / _tune("SLIDEW", 0.001), float(lv.get("slidemin", 0.35)), 1.0)
	# corner exit: with a lot of lock the throttle comes in gradually (no power oversteer)
	if thr > 0.0:
		thr = minf(thr, 1.0 - float(lv.get("exit", 0.0)) * minf(absf(steer), 1.0))
	# traction control: wheelspin on the driven rear wheels costs time – ease off like a good driver
	var rspin := (maxf(float(car.wheels[2]["spin"]), 0.0) + maxf(float(car.wheels[3]["spin"]), 0.0)) * 0.5
	if rspin > 1.2 and thr > 0.0:
		thr *= clampf(1.0 - (rspin - 1.2) / 5.0, 0.35, 1.0)
	# nitro on the straights: well below the target speed, nothing tight ahead, not sliding
	var nitro := false
	if float(lv["nitro"]) > 0.5 and thr > 0.9 and v > 12.0 and v < v_target - 6.0 and absf(slide) < 0.08:
		var straight := true
		for d in range(4, int(90.0 / sp), 4):
			if absf(tr.curvature[(i + d) % n]) > 1.0 / 220.0:
				straight = false
				break
		nitro = straight
	if bool(b["finished"]):
		thr = 0.0
		brk = 0.4
		nitro = false
	return [thr, brk, steer, false, nitro]


## Tuning knobs for testing (environment variables), default otherwise.
static func _tune(key: String, def: float) -> float:
	var v := OS.get_environment("AI_" + key)
	return float(v) if v != "" else def


func _seg_scale_at(i: int) -> float:
	if seg_scale.is_empty():
		return 1.0
	return seg_scale[clampi(i / SEG, 0, seg_scale.size() - 1)]


## Learning: running wide off the asphalt lowers the corner speed for the 60 m before that spot;
## a clean stretch nudges it back up (a bit faster every lap until the limit is found).
func _learn(b: Dictionary, delta: float) -> void:
	if seg_scale.is_empty() or world.state != "running":
		return
	var car = b["car"]
	var tr = world.track
	var n: int = tr.sample_count()
	var i: int = maxi(car.track_hint, 0)
	var rel: Vector3 = car.global_position - tr.samples[i]
	var lat: float = absf(rel.dot(tr.rights[i]))
	b["learn_cool"] = float(b.get("learn_cool", 0.0)) - delta
	var seg := i / SEG
	if lat > float(tr.hws[i]) + 0.3 and car.speed > 8.0:
		if float(b["learn_cool"]) <= 0.0:
			b["learn_cool"] = 1.2
			for d in range(0, int(60.0 / tr.SPACING), SEG):
				var sg := ((i - d + n) % n) / SEG
				seg_scale[sg] = maxf(seg_scale[sg] * 0.96, 0.55)
		b["clean_seg"] = -1
	elif seg != int(b.get("clean_seg", -1)):
		# entered a new segment cleanly: the previous one may be taken a touch faster next time
		var prev_seg := int(b.get("clean_seg", -1))
		if prev_seg >= 0 and float(b["learn_cool"]) <= -1.0:
			seg_scale[prev_seg] = minf(seg_scale[prev_seg] * 1.006, 1.2)
		b["clean_seg"] = seg
