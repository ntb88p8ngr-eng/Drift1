extends Node
## Party mode offline: the race's bots play the minigames too (instead of waiting hidden). Each gets
## a little driver for the game – Red Light Green Light (stops on red, now and then too late and
## sent back), the offroad parkour (on along the course, back to the last checkpoint when stuck),
## king of the zone (into the zone and push), the donut duel (spinning on its own spot). Bowling is
## played on the player's own pins, so the bots' throws are only counted (they wait meanwhile).
## The arena games bring their own bot copies (party_arena.gd).

const PartySites = preload("res://scripts/world/party_sites.gd")

const DRIVEN := ["rlgl", "parkour", "koth", "donut"]
const RL_SAFE := 12.0          # as party.gd: right before the line moving on red is not caught
const PARKOUR_LIFT := 0.32     # as party.gd

var party            # party.gd
var world
var sites
var game := ""
var bots: Array = []           # {id, car, slot, value, done, along, hint, ...}
var started := false
var _count := 1
var _rng := RandomNumberGenerator.new()


static func plays(id: String) -> bool:
	return DRIVEN.has(id) or id == "bowling"


func setup(p_party, p_world, p_sites, id: String, ids: Array, seed_v: int) -> void:
	party = p_party
	world = p_world
	sites = p_sites
	game = id
	_count = ids.size()
	_rng.seed = hash([seed_v, "bots"])
	for k in ids.size():
		var bid := int(ids[k])
		if not world._bot_ids.has(bid) or not world.cars.has(bid) or not is_instance_valid(world.cars[bid]):
			continue
		var car = world.cars[bid]
		var b := {"id": bid, "car": car, "slot": k, "value": 0.0, "done": false, "along": 0.0, "hint": -1,
			"skill": _rng.randf_range(0.75, 1.0), "lane": _rng.randf_range(-0.35, 0.35), "late": false,
			"red_since": -1.0, "stuck": 0.0, "cp": 0.0, "yaw": 0.0, "yaw_acc": 0.0, "old_ai": car.ai_fn}
		bots.append(b)
		if DRIVEN.has(id):
			car.ai_fn = _drive.bind(b)
			car.controls_locked = true
			car.gear = 1
			if id == "parkour":
				car.set_lift(PARKOUR_LIFT)
				car.surface_override = func(p: Vector3) -> Array: return [0.6, "dirt"] if sites.in_mud(p) else [0.84, "dirt"]
			else:
				car.surface_override = func(_p: Vector3) -> Array: return [1.0, "asphalt"]
		else:
			# bowling: their two throws, by skill
			var v := 0
			for t in 2:
				v += clampi(int(round(_rng.randf_range(2.0, 10.5) * float(b["skill"]) + _rng.randf_range(0.0, 2.0))), 0, 10)
			b["value"] = float(v)
			b["done"] = true


## Whether the race bots are out on the course (else the world keeps them parked).
func on_course() -> bool:
	return DRIVEN.has(game)


func go() -> void:
	started = true
	for b in bots:
		if is_instance_valid(b["car"]):
			b["car"].controls_locked = false
			b["yaw"] = b["car"].global_rotation.y


## Every physics step: held on the start grid until GO, then their scores.
func step(delta: float, t: float) -> void:
	for b in bots:
		var car = b["car"]
		if not is_instance_valid(car) or not DRIVEN.has(game):
			continue
		if not started:
			car.place(sites.start_xf(game, int(b["slot"]), _count))
			continue
		var proj: Array = world.track.project(car.global_position, int(b["hint"]))
		b["hint"] = proj[0]
		var along := wrapf(float(proj[1]) - float(sites.sites[game]["p0"]), -float(world.track.length) * 0.5, float(world.track.length) * 0.5)
		b["along"] = along
		var lateral := float(proj[2])
		match game:
			"rlgl":
				if b["done"]:
					continue
				b["value"] = along - PartySites.RLGL_START
				if along > sites.rlgl_finish():
					b["value"] = 10000.0 - t
					b["done"] = true
					continue
				var light: int = party._rl_light(t)
				if light == 0:
					if float(b["red_since"]) < 0.0:
						b["red_since"] = t
						b["late"] = _rng.randf() < 0.18 * (1.2 - float(b["skill"]))
					if t - float(b["red_since"]) > 0.45 and car.speed > 0.9 and along < sites.rlgl_finish() - RL_SAFE:
						car.place(sites.start_xf(game, int(b["slot"]), _count))
						b["hint"] = -1
						b["late"] = false
				else:
					b["red_since"] = -1.0
			"parkour":
				if b["done"]:
					continue
				for cz in sites.pk_checkpoints():
					if along > float(cz) + 2.0 and float(cz) > float(b["cp"]):
						b["cp"] = cz
				b["value"] = along - PartySites.PK_START
				if along > sites.pk_finish():
					b["value"] = 10000.0 - t
					b["done"] = true
					continue
				# stuck on a log or a tyre wall: back to the last checkpoint (the player's [R])
				b["stuck"] = float(b["stuck"]) + delta if car.speed < 1.5 else 0.0
				if float(b["stuck"]) > 3.0 or car.global_position.y < float(world.track.kill_y):
					b["stuck"] = 0.0
					var cxf: Transform3D = sites.checkpoint_xf(float(b["cp"]))
					cxf.origin += cxf.basis.x * float(b["lane"]) * 4.0
					car.place(cxf)
					b["hint"] = -1
			"koth":
				var zone: Vector2 = party._zone
				if Vector2(along - zone.x, lateral - zone.y).length() < PartySites.KOTH_ZONE_R:
					b["value"] = float(b["value"]) + delta
			"donut":
				var yaw: float = car.global_rotation.y
				var dy := wrapf(yaw - float(b["yaw"]), -PI, PI)
				b["yaw"] = yaw
				var spot: Transform3D = sites.start_xf("donut", int(b["slot"]), _count)
				if car.speed > 1.5 and car.global_position.distance_to(spot.origin) < PartySites.DONUT_R:
					b["yaw_acc"] = float(b["yaw_acc"]) + dy
				b["value"] = floorf(absf(float(b["yaw_acc"])) / TAU)


## Their scores for the result table: id -> value.
func results() -> Dictionary:
	var out := {}
	for b in bots:
		out[int(b["id"])] = float(b["value"])
	return out


## The minigame is over: they stop where they are.
func stop() -> void:
	for b in bots:
		if is_instance_valid(b["car"]):
			b["car"].controls_locked = true


## Back to the race: their own driver again, on the race at the spot they left it (the world parks
## them there through the countdown).
func finish() -> void:
	for b in bots:
		var car = b["car"]
		if not is_instance_valid(car):
			continue
		car.ai_fn = b["old_ai"]
		car.surface_override = Callable()
		car.set_lift(0.0)
		car.controls_locked = false
		if car.has_meta("park_xf"):
			car.place(car.get_meta("park_xf"))


# ---------------------------------------------------------------------------
# The drivers: [throttle, brake, steer, handbrake, nitro]
# ---------------------------------------------------------------------------
func _drive(b: Dictionary) -> Array:
	var car = b["car"]
	if not started or not is_instance_valid(car):
		return [0.0, 0.0, 0.0, true]
	var t: float = party._t
	var along: float = b["along"]
	var hw := float(world.track.half_w) - 2.0
	match game:
		"rlgl":
			if b["done"]:
				return [0.0, 0.0, 0.0, true]      # over the line: stays there (brake held = reverse)
			var light: int = party._rl_light(t)
			var stop: bool = light == 2 or (light == 0 and not (bool(b["late"]) and t - float(b["red_since"]) < 0.7))
			var target: Vector3 = sites.course_xf(game, along + 14.0, float(b["lane"]) * hw).origin
			return _to(car, target, 0.0 if stop else 20.0 * float(b["skill"]))
		"parkour":
			if b["done"]:
				return [0.0, 0.0, 0.0, true]      # over the line: stays there (brake held = reverse)
			var lane := float(b["lane"]) * hw * (0.5 + 0.5 * sin(t * 0.4 + float(b["slot"])))
			var target: Vector3 = sites.course_xf(game, along + 10.0, lane).origin
			return _to(car, target, 9.0 + 4.0 * float(b["skill"]))
		"koth":
			var zone: Vector2 = party._zone
			var target: Vector3 = sites.course_xf(game, zone.x, zone.y).origin
			var to: Vector3 = target - car.global_position
			to.y = 0.0
			var d := to.length()
			var fwd: Vector3 = -car.global_transform.basis.z
			fwd.y = 0.0
			var alpha := fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP) if d > 0.1 else 0.0
			var dt := 1.0 / float(Engine.physics_ticks_per_second)
			# the zone moved behind them or they are stuck (against a car, the kerb): back up while
			# turning, then on towards it – a three-point turn on the narrow road
			b["k_rev"] = float(b.get("k_rev", 0.0)) - dt
			b["k_cd"] = float(b.get("k_cd", 0.0)) - dt
			b["k_stuck"] = float(b.get("k_stuck", 0.0)) + dt if car.speed < 1.0 and d > PartySites.KOTH_ZONE_R else 0.0
			if float(b["k_rev"]) <= 0.0 and float(b["k_cd"]) <= 0.0 and (float(b["k_stuck"]) > 1.2 or (absf(alpha) > 2.0 and d > PartySites.KOTH_ZONE_R and car.speed < 5.0)):
				b["k_rev"] = 1.3
				b["k_cd"] = 2.2
				b["k_stuck"] = 0.0
			if float(b["k_rev"]) > 0.0:
				return [0.0, 0.9, clampf(alpha * 1.8, -1.0, 1.0), false]
			return _to(car, target, clampf(d * 0.9, 3.0, 16.0))
		"donut":
			var spot: Transform3D = sites.start_xf("donut", int(b["slot"]), _count)
			var off: Vector3 = car.global_position - spot.origin
			off.y = 0.0
			if off.length() > PartySites.DONUT_R - 7.0:
				return _to(car, spot.origin, 6.0)       # drifted off: back to the spot
			# full lock and throttle; a pull on the handbrake whenever it turns too slowly breaks the
			# rear loose again (the spin keeps going on the throttle)
			# (a short pull only: the handbrake also opens the clutch – held, no drive at all)
			var spin := absf(float(car.angular_velocity.y))
			var dt := 1.0 / float(Engine.physics_ticks_per_second)
			b["hb_t"] = float(b.get("hb_t", 0.0)) - dt
			b["hb_cd"] = float(b.get("hb_cd", 0.0)) - dt
			if float(b["hb_cd"]) <= 0.0 and car.speed > 4.0 and spin < 1.2 and off.length() < 6.0:
				b["hb_t"] = 0.12
				b["hb_cd"] = 2.0
			# flat out from a standstill (the clutch slips, the rear tyres spin): a burnout on full lock
			var thr := 1.0 if car.speed < 7.0 else 0.75
			return [thr, 0.0, 1.0 if int(b["slot"]) % 2 == 0 else -1.0, float(b["hb_t"]) > 0.0, false]
	return [0.0, 0.0, 0.0, false]


## Drive towards target at speed v (pure pursuit, like the race bots).
func _to(car, target: Vector3, v: float) -> Array:
	var xf: Transform3D = car.global_transform
	var to := target - xf.origin
	to.y = 0.0
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var alpha := fwd.signed_angle_to(to.normalized(), Vector3.UP) if to.length() > 0.1 else 0.0
	var steer := clampf(-alpha * 1.8, -1.0, 1.0)
	var spd: float = car.forward_speed
	var thr := 0.0
	var brk := 0.0
	if v <= 0.1:
		brk = 1.0 if spd > 0.3 else 0.0
	elif spd < v:
		thr = clampf((v - spd) * 0.4, 0.25, 1.0)
	elif spd > v + 2.0:
		brk = clampf((spd - v) * 0.15, 0.0, 0.8)
	return [thr, brk, steer, false, false]
