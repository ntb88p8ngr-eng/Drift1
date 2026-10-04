extends RefCounted
## Drift scoring: points = angle × speed × time, a growing chain multiplier, bonuses for
## direction changes (transitions) and for sliding close to a wall. The chain is banked after a
## short grace period without drifting and lost on wall contact or when leaving the track.
## Tricks: a full 360° rotation (relative to the track direction) with the rear tyres spinning the
## whole time and all four wheels on the track, and the reverse entry (sliding into a corner with
## more than 100° of angle – tail first – and catching it back into a normal drift).

const MIN_SPEED := 7.0       # m/s
const MIN_ANGLE := 12.0      # degrees
const MAX_ANGLE := 115.0
const GRACE := 1.4
const MAX_MULT := 6.0
const SPIN_BONUS := 2500.0
const REVERSE_BONUS := 3000.0
const REVERSE_MIN_ANGLE := 100.0
const REVERSE_MIN_TIME := 0.25

var chain := 0.0
var total := 0.0
var best_chain := 0.0
var multiplier := 1.0
var chain_time := 0.0
var grace := 0.0
var angle := 0.0
var drifting := false
var near_wall := false
var enabled := true
var _last_side := 0.0
var _offroad_time := 0.0
var _rel_yaw := 0.0         # heading relative to the track direction (rad), last frame
var _yaw_acc := 0.0         # accumulated relative rotation while the rear tyres keep spinning
var _spin_grace := 0.0
var _spin_count := 0
var _rev_time := 0.0
var _rev_peak := 0.0
var _rev_hold := 0.0
var _has_yaw := false
var _query: PhysicsRayQueryParameters3D

## Filled on every update: Array of [type, value, …]; types: "start", "transition", "bank", "fail",
## "spin" [points, count], "reverse" [points]
var events: Array = []


func _init() -> void:
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = 1


func effective_multiplier() -> float:
	return clampf(multiplier + floor(chain_time / 3.0) * 0.5, 1.0, MAX_MULT)


func update(car, delta: float, space: PhysicsDirectSpaceState3D) -> void:
	events.clear()
	if not enabled:
		return
	angle = car.drift_angle_deg()
	var spd: float = car.speed
	var surface: String = car.surface_name
	var on_track := surface == "asphalt" or surface == "curb" or surface == "sand_road"
	var ok: bool = spd > MIN_SPEED and angle > MIN_ANGLE and angle < MAX_ANGLE and int(car.grounded_wheels) >= 3 and float(car.forward_speed) > 2.0
	if chain > 0.0 and not on_track:
		_offroad_time += delta
		if _offroad_time > 0.6:
			fail("Offroad")
			return
	else:
		_offroad_time = 0.0
	_update_tricks(car, delta, on_track, spd, angle)
	if ok and on_track:
		if not drifting:
			drifting = true
			events.append(["start", 0.0])
		var side := signf(float(car.slip_angle))
		if _last_side != 0.0 and side != _last_side and chain_time > 0.35:
			multiplier = minf(multiplier + 0.5, MAX_MULT)
			events.append(["transition", effective_multiplier()])
		_last_side = side
		chain_time += delta
		grace = GRACE
		near_wall = _check_near_wall(car, space)
		var bonus := 1.5 if near_wall else 1.0
		chain += (angle - MIN_ANGLE * 0.5) * spd * delta * 1.6 * bonus * effective_multiplier()
	elif drifting:
		near_wall = false
		grace -= delta
		if grace <= 0.0:
			bank()


func _update_tricks(car, delta: float, on_track: bool, spd: float, ang: float) -> void:
	# --- 360: rotation relative to the track direction while the rear wheels spin ---
	var fwd: Vector3 = -(car.global_transform as Transform3D).basis.z
	var heading := atan2(-fwd.x, -fwd.z)
	var track_dir := heading
	if car.track and int(car.track_hint) >= 0:
		var t: Vector3 = car.track.tangents[int(car.track_hint)]
		track_dir = atan2(-t.x, -t.z)
	var rel := wrapf(heading - track_dir, -PI, PI)
	var d_rel := wrapf(rel - _rel_yaw, -PI, PI) if _has_yaw else 0.0
	_rel_yaw = rel
	_has_yaw = true
	var wheels: Array = car.wheels
	var rear_spin := 0.0
	if wheels.size() >= 4:
		rear_spin = (absf(float(wheels[2]["spin"])) + absf(float(wheels[3]["spin"]))) * 0.5
	var spinning: bool = rear_spin > 2.5 and float(car.throttle) > 0.3
	var all_on: bool = on_track and int(car.grounded_wheels) >= 3 and _wheels_on_track(car)
	_spin_grace = 0.35 if spinning else _spin_grace - delta
	if _spin_grace > 0.0 and all_on:
		_yaw_acc += d_rel
		if absf(d_rel) / maxf(delta, 1e-4) > 1.0:
			grace = GRACE   # keep the combo alive while rotating
		if absf(_yaw_acc) >= TAU:
			_yaw_acc -= signf(_yaw_acc) * TAU
			_spin_count += 1
			var pts := SPIN_BONUS * _spin_count * effective_multiplier()
			chain += pts
			multiplier = minf(multiplier + 1.0, MAX_MULT)
			if not drifting:
				drifting = true
			grace = GRACE
			events.append(["spin", pts, _spin_count])
	else:
		_yaw_acc = 0.0
		_spin_count = 0

	# --- reverse entry: tail first into the corner, then caught into a normal drift ---
	var fwd_ok: bool = on_track and spd > 8.0
	if fwd_ok and ang > REVERSE_MIN_ANGLE and ang < 172.0:
		_rev_time += delta
		_rev_peak = maxf(_rev_peak, ang)
		_rev_hold = 2.0
		grace = maxf(grace, GRACE)
	elif _rev_time > 0.0:
		if ang >= 172.0 or not on_track:
			_rev_time = 0.0   # spun round or left the track – no reverse entry
			_rev_peak = 0.0
		elif ang > MIN_ANGLE and ang < 80.0 and float(car.forward_speed) > 2.0:
			if _rev_time >= REVERSE_MIN_TIME:
				var pts2 := REVERSE_BONUS * (1.0 + (_rev_peak - REVERSE_MIN_ANGLE) / 60.0) * effective_multiplier()
				chain += pts2
				multiplier = minf(multiplier + 1.0, MAX_MULT)
				drifting = true
				grace = GRACE
				events.append(["reverse", pts2])
			_rev_time = 0.0
			_rev_peak = 0.0
		else:
			_rev_hold -= delta
			if _rev_hold <= 0.0:
				_rev_time = 0.0
				_rev_peak = 0.0


func _wheels_on_track(car) -> bool:
	for w in car.wheels:
		var sname := str(w["surface"])
		if bool(w["grounded"]) and sname != "asphalt" and sname != "curb" and sname != "sand_road":
			return false
	return true


func bank() -> void:
	if chain > 0.0:
		total += chain
		best_chain = maxf(best_chain, chain)
		events.append(["bank", chain])
	_reset_chain()


func fail(reason: String = "Wand") -> void:
	if chain > 0.0:
		events.append(["fail", chain, reason])
	_reset_chain()


func _reset_chain() -> void:
	chain = 0.0
	multiplier = 1.0
	chain_time = 0.0
	drifting = false
	_last_side = 0.0
	_offroad_time = 0.0
	_yaw_acc = 0.0
	_spin_count = 0
	_rev_time = 0.0
	_rev_peak = 0.0


func _check_near_wall(car, space: PhysicsDirectSpaceState3D) -> bool:
	if space == null:
		return false
	var xf: Transform3D = car.global_transform
	var rear := xf * Vector3(0, 0.6, 2.0)
	var ex: Array[RID] = [car.get_rid()]
	_query.exclude = ex
	for dir: Vector3 in [xf.basis.x, -xf.basis.x, xf.basis.z]:
		_query.from = rear
		_query.to = rear + (dir as Vector3) * 2.2
		if not space.intersect_ray(_query).is_empty():
			return true
	return false
