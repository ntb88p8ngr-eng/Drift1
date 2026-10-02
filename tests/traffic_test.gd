extends Node
## NPC traffic on the city track: the cars move along the lap smoothly (no stutter: the speed seen
## from frame to frame never jumps), change lanes, a traffic car stops behind a car standing in its
## lane (no pushing through), and one knocked aside steers back into a lane and drives on.
## Run: godot --headless --path . res://tests/traffic_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 3})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var fails := 0
	var tf = world.traffic
	if tf == null or tf.cars.is_empty():
		print("FAIL: no traffic"); get_tree().quit(1); return
	var p0: Array = []
	var lanes0: Array = []
	for t in tf.cars:
		p0.append(t.progress)
		lanes0.append(t.lane)
	# smooth: the speed measured from the drawn positions frame to frame never jumps
	var watch := mini(tf.cars.size(), 12)
	var last_pos: Array = []
	var last_v: Array = []
	for k in watch:
		last_pos.append((tf.cars[k].xf as Transform3D).origin)
		last_v.append(-1.0)
	var worst_jump := 0.0
	var changes := 0
	var t_end := Time.get_ticks_msec() + 5000
	var frames := 0
	# process_frame comes before the nodes' _process: the positions read now were made last frame,
	# with last frame's time step (and the traffic caps a step at 0.05 s)
	var dt := 0.0
	while Time.get_ticks_msec() < t_end or frames < 240:
		await get_tree().process_frame
		frames += 1
		var dt_now := minf(get_process_delta_time(), 0.05)
		if dt <= 0.0:
			dt = dt_now
			continue
		for k in watch:
			var pos: Vector3 = (tf.cars[k].xf as Transform3D).origin
			var vm: float = pos.distance_to(last_pos[k]) / dt
			if float(last_v[k]) >= 0.0:
				worst_jump = maxf(worst_jump, absf(vm - float(last_v[k])))
			last_v[k] = vm
			last_pos[k] = pos
		dt = dt_now
	var moved := 0.0
	for k in tf.cars.size():
		moved += fposmod(tf.cars[k].progress - float(p0[k]), world.track.length)
		if tf.cars[k].lane != float(lanes0[k]):
			changes += 1
	moved /= tf.cars.size()
	print("TRAFFIC: %d cars, %.0f m on average in %d frames, worst speed jump between frames %.2f m/s, %d changed lanes" % [tf.cars.size(), moved, frames, worst_jump, changes])
	if moved < 20.0:
		print("FAIL: traffic hardly moves"); fails += 1
	if worst_jump > 1.5:
		print("FAIL: the traffic stutters"); fails += 1
	# knocked aside (a hit from the side): back into a lane and on its way
	var tr = world.track
	var car = world.local_car
	var tk = tf.cars[3]
	var ki: int = tr.index_at(tk.progress)
	car.place(Transform3D(Basis.looking_at(tr.tangents[ki], Vector3.UP), tr.edge_point(ki, -tr.half_w * 3.0) + Vector3(0, 0.6, 0)))
	car.freeze = true
	for f in 30:
		await get_tree().physics_frame
	var rend = world.traffic_cars
	var bk: int = rend._body_of.get(tk.id, -1)
	if bk < 0:
		print("FAIL: the traffic car near the player isn't solid"); fails += 1
	else:
		var body: RigidBody3D = rend._bodies[bk]
		var kf: Vector3 = -tk.xf.basis.z
		body.linear_velocity += Vector3(-kf.z, 0, kf.x) * 7.0
		body.angular_velocity = Vector3(0, 2.0, 0)
		var max_off := 0.0
		for f in 120 * 12:
			await get_tree().physics_frame
			max_off = maxf(max_off, absf(tk.lat - tk.lane * tr.half_w * 0.42))
		var off_now := absf(tk.lat - tk.lane * tr.half_w * 0.42)
		print("TRAFFIC: knocked car: up to %.1f m out of its lane, after 12 s %.2f m, speed %.1f" % [max_off, off_now, tk.v])
		if max_off < 0.5:
			print("FAIL: the knock didn't move the car"); fails += 1
		if off_now > 0.4 or tk.v < 1.0:
			print("FAIL: the knocked car didn't find its lane again"); fails += 1
	car.freeze = false
	# park the player 30 m in front of the first traffic car, in its lane
	var t0 = tf.cars[0]
	var block_p := fposmod(t0.progress + 30.0, tr.length)
	var i: int = tr.index_at(block_p)
	car.place(Transform3D(Basis.looking_at(tr.tangents[i], Vector3.UP), tr.edge_point(i, tr.half_w * 0.42 * t0.lane) + Vector3(0, 0.6, 0)))
	car.freeze = true         # parked: stays put whatever happens
	var start_pos: Vector3 = car.global_position
	for f in 120 * 10:
		await get_tree().physics_frame
	var gap: float = fposmod(block_p - t0.progress, tr.length) - t0.half - 2.3
	print("TRAFFIC: stopped with %.1f m between the bumpers (speed %.1f), parked car pushed %.1f m" % [gap, t0.v, car.global_position.distance_to(start_pos)])
	# it may also have passed in the other lane
	var passed: bool = absf(t0.lat - t0.lane * tr.half_w * 0.42) < 0.5 and t0.lane * tr.half_w * 0.42 * signf(tr.half_w) != 0.0 and fposmod(t0.progress - block_p, tr.length) < tr.length * 0.5 and fposmod(t0.progress - block_p, tr.length) > 0.0
	if not passed and (t0.v > 0.5 or gap < 0.5 or gap > 9.0):
		print("FAIL: traffic does not stop for (or pass) a car in its lane"); fails += 1
	# the city streets: cars move, take the junctions in turn (no overlaps), nothing jams for good
	var ct = world.city_traffic
	if ct == null or ct.cars.is_empty():
		print("FAIL: no city traffic"); fails += 1
	else:
		var odo0: Array = []
		for c in ct.cars:
			odo0.append(c.odo)
		var overlaps := 0
		for sec in 10:
			for f in 120:
				await get_tree().physics_frame
			for a in ct.cars.size():
				for b2 in range(a + 1, ct.cars.size()):
					if (ct.cars[a].xf.origin as Vector3).distance_to(ct.cars[b2].xf.origin) < 1.6:
						overlaps += 1
						for c in [ct.cars[a], ct.cars[b2]]:
							var pp = ct.paths[c.path]
							print("  overlap: car %d path %d conn %s len %.1f s %.1f v %.1f next %d at %s" % [c.id, c.path, pp.conn, pp.length, c.s, c.v, c.next, str(c.xf.origin)])
		var still := 0
		var dist := 0.0
		for k in ct.cars.size():
			var d: float = ct.cars[k].odo - float(odo0[k])
			dist += d
			if d < 5.0:
				still += 1
		print("CITY TRAFFIC: %d cars, %.0f m on average in 10 s, %d hardly moved, %d overlaps" % [ct.cars.size(), dist / ct.cars.size(), still, overlaps])
		if dist / ct.cars.size() < 40.0:
			print("FAIL: city traffic hardly moves"); fails += 1
		if still > ct.cars.size() / 4:
			print("FAIL: too many cars stuck"); fails += 1
		if overlaps > 0:
			print("FAIL: traffic cars drive into each other"); fails += 1
	print("TRAFFIC TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
