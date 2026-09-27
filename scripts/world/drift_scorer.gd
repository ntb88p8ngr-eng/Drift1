extends RefCounted
## Drift scoring: points = angle × speed × time, a growing chain multiplier, bonuses for
## direction changes (transitions) and for sliding close to a wall. The chain is banked after a
## short grace period without drifting and lost on wall contact or when leaving the track.

const MIN_SPEED := 7.0       # m/s
const MIN_ANGLE := 12.0      # degrees
const MAX_ANGLE := 115.0
const GRACE := 1.4
const MAX_MULT := 6.0

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
var _query: PhysicsRayQueryParameters3D

## Filled on every update: Array of [type, value]; types: "start", "transition", "bank", "fail"
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
	var on_track := surface == "asphalt" or surface == "curb"
	var ok: bool = spd > MIN_SPEED and angle > MIN_ANGLE and angle < MAX_ANGLE and int(car.grounded_wheels) >= 3 and float(car.forward_speed) > 2.0
	if chain > 0.0 and not on_track:
		_offroad_time += delta
		if _offroad_time > 0.6:
			fail("Offroad")
			return
	else:
		_offroad_time = 0.0
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
