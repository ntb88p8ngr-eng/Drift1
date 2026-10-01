extends Node
## Grüne Hölle profile: the road is 18 m wide, the Döttinger Höhe 24 m, the Karussell a banked
## hairpin. Checks the widths and the bank, drops the car across the whole banked road (it must rest
## on the tilted surface), checks the ground doesn't poke through beside it, and lets a bot drive
## through the Karussell.
## Run: godot --headless --path . res://tests/banking_test.tscn

const World = preload("res://scripts/world/world.gd")
const RaceAI = preload("res://scripts/world/race_ai.gd")

var fails := 0


func _fail(msg: String) -> void:
	print("FAIL: " + msg)
	fails += 1


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "gruene_hoelle", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 1, "online": false})
	add_child(world)
	for f in 5:
		await get_tree().physics_frame
	var tr = world.track
	var car = world.local_car
	var n: int = tr.sample_count()
	var secs := {}
	for sec in tr.meta["sections"]:
		secs[str(sec[0])] = int(float(sec[1]) / tr.SPACING) % n
	# --- widths ---
	var w_base: float = tr.hws[secs["Hatzenbach"]] * 2.0
	var mid: int = (secs["Döttinger Höhe"] + secs["Antoniusbuche"]) / 2
	var w_straight: float = tr.hws[mid] * 2.0
	print("WIDTH base %.1f m, Döttinger Höhe %.1f m" % [w_base, w_straight])
	if absf(w_base - 18.0) > 0.01 or absf(w_straight - 24.0) > 0.01:
		_fail("widths")
	var s: Array = tr.surface_at(tr.edge_point(mid, 11.0) + Vector3(0, 0.1, 0), mid)
	if str(s[1]) != "asphalt":
		_fail("11 m off the centre of the Döttinger Höhe is not asphalt (%s)" % s[1])
	# --- banking ---
	var kc: int = secs["Karussell"]
	var top := 0.0
	var top_i := kc
	var span := 0
	for d in range(-120, 121):
		var i := (kc + d + n) % n
		if absf(tr.bank[i]) > 0.01:
			span += 1
		if absf(tr.bank[i]) > absf(top):
			top = tr.bank[i]
			top_i = i
	print("BANK Karussell: max %.1f deg over %d m, outside is the %s side (curvature %+.4f)" % [
		rad_to_deg(atan(absf(top))), span * 2, "right" if top > 0.0 else "left", tr.curvature[top_i]])
	if absf(rad_to_deg(atan(absf(top))) - 24.0) > 0.5 or span * 2 < 80:
		_fail("bank angle / length")
	if signf(top) != signf(tr.curvature[top_i]):
		_fail("the inside of the corner is the high side")
	# a smooth entry: no step in the bank (roll) and no kink in the line
	var max_db := 0.0
	var max_dk := 0.0
	for d in range(-180, 181):
		var i := (kc + d + n) % n
		var j := (i + 1) % n
		max_db = maxf(max_db, absf(tr.bank[j] - tr.bank[i]))
		max_dk = maxf(max_dk, absf(tr.curvature[j] - tr.curvature[i]))
	print("ENTRY: bank change up to %.2f deg per 2 m, curvature change up to %.4f per 2 m" % [rad_to_deg(atan(max_db)), max_dk])
	if rad_to_deg(atan(max_db)) > 1.3 or max_dk > 0.0022:
		_fail("the Karussell entry is not smooth")
	var far := 0
	for d in range(-400, 401, 40):
		if absf(tr.bank[(kc + d + 2000 + n) % n]) > 0.0:
			far += 1
	if far > 0:
		_fail("bank found away from the Karussell")
	# ground beside the banked road: never above the road plane at the edges
	var worst := -1e9
	for d in range(-30, 31, 3):
		var i := (top_i + d + n) % n
		for lat: float in [-tr.hws[i] - 0.5, tr.hws[i] + 0.5]:
			var p: Vector3 = tr.edge_point(i, lat)
			worst = maxf(worst, world.terrain.height_at(p.x, p.z) - (p.y + tr.ROAD_Y))
	print("GROUND beside the banked road: at most %.2f m above the road plane" % worst)
	if worst > 0.25:
		_fail("ground pokes through beside the banking")
	# the road has its own collision (it faced downwards once, the cars ran on the terrain)
	for probe_i in [secs["Hatzenbach"], top_i]:
		for lat: float in [-7.0, 0.0, 7.0]:
			var pq: Vector3 = tr.edge_point(probe_i, lat)
			var q2 := PhysicsRayQueryParameters3D.create(pq + Vector3(0, 6, 0), pq - Vector3(0, 6, 0), 1)
			var h2 := world.get_world_3d().direct_space_state.intersect_ray(q2)
			if h2.is_empty() or str(h2.collider.name) != "RoadBody" or absf(float(h2.position.y) - pq.y - tr.ROAD_Y) > 0.02:
				_fail("no road collision at sample %d, %+.0f m (hit %s)" % [probe_i, lat, h2.collider.name if h2 else "-"])
	# drop the car across the banked road: it must come to rest on the tilted surface
	for lat: float in [-7.0, -3.5, 0.0, 3.5, 7.0]:
		car.place(tr.transform_at(top_i, lat, 1.2))
		for f in 150:
			await get_tree().physics_frame
		var p: Vector3 = car.global_position
		var proj: Array = tr.project(p)
		var road_y: float = tr.edge_point(int(proj[0]), float(proj[2])).y + tr.ROAD_Y
		var up: Vector3 = car.global_transform.basis.y
		print("  dropped at %+.1f m: %.2f m above the road plane, body tilt %.1f deg, speed %.1f m/s" % [lat, p.y - road_y, rad_to_deg(up.angle_to(Vector3.UP)), car.speed])
		if absf(p.y - road_y) > 0.25:
			_fail("car at %+.1f m does not rest on the banked road" % lat)
	# --- a bot drives through the Karussell ---
	var ai := RaceAI.new()
	ai.world = world
	ai.level = 2
	world.add_child(ai)
	world.state = "running"
	car.place(tr.transform_at((kc - 160 + n) % n, 0.0, 0.6))
	car.linear_velocity = -car.global_transform.basis.z * 18.0
	ai.add_bot(1001, car)
	var p_start: float = tr.project(car.global_position)[1]
	var resets := 0
	var last: Vector3 = car.global_position
	var max_tilt := 0.0
	var t := 0.0
	while t < 30.0:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		if car.global_position.distance_to(last) > 8.0:
			resets += 1
		last = car.global_position
		var proj2: Array = tr.project(car.global_position, car.track_hint)
		if absf(tr.bank[int(proj2[0])]) > 0.2:
			max_tilt = maxf(max_tilt, rad_to_deg(car.global_transform.basis.y.angle_to(Vector3.UP)))
	var gone: float = fposmod(float(tr.project(car.global_position)[1]) - p_start, tr.length)
	print("BOT through the Karussell: %.0f m in 30 s, %d resets, car tilt on the banking up to %.0f deg" % [gone, resets, max_tilt])
	if gone < 500.0 or resets > 0:
		_fail("the bot did not get through the Karussell")
	if max_tilt < 12.0:
		_fail("the car does not lean with the banking")
	print("BANKING TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
