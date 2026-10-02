extends Node
## NPC traffic on the city track: the cars move along the lap, and a traffic car stops behind a car
## standing in its lane (no pushing through).
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
	for t in tf.cars:
		p0.append(float(t["progress"]))
	for f in 120 * 5:
		await get_tree().physics_frame
	var moved := 0.0
	for k in tf.cars.size():
		moved += fposmod(float(tf.cars[k]["progress"]) - float(p0[k]), world.track.length)
	moved /= tf.cars.size()
	print("TRAFFIC: %d cars, %.0f m in 5 s on average" % [tf.cars.size(), moved])
	if moved < 30.0:
		print("FAIL: traffic hardly moves"); fails += 1
	# park the player 30 m in front of the first traffic car, in its lane
	var t0: Dictionary = tf.cars[0]
	var tr = world.track
	var block_p := fposmod(float(t0["progress"]) + 30.0, tr.length)
	var i: int = tr.index_at(block_p)
	var car = world.local_car
	car.place(Transform3D(Basis.looking_at(tr.tangents[i], Vector3.UP), tr.edge_point(i, tr.half_w * float(t0["lane"])) + Vector3(0, 0.6, 0)))
	car.freeze = true         # parked: stays put whatever happens
	var start_pos: Vector3 = car.global_position
	for f in 120 * 8:
		await get_tree().physics_frame
	var gap := fposmod(block_p - float(t0["progress"]), tr.length) - float(t0["half"]) - 2.3
	print("TRAFFIC: stopped with %.1f m between the bumpers (speed %.1f), parked car pushed %.1f m" % [gap, float(t0["v"]), car.global_position.distance_to(start_pos)])
	if float(t0["v"]) > 0.5 or gap < 0.5 or gap > 8.0:
		print("FAIL: traffic does not stop for a car in its lane"); fails += 1
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
