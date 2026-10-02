extends Node
## NPC traffic on the city track: the cars move along the lap, and a traffic car stops behind a car
## standing in its lane (no pushing through).
## Run: godot --headless --path . res://tests/traffic_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": true})
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
	car.place(Transform3D(Basis.looking_at(tr.tangents[i], Vector3.UP), tr.edge_point(i, tr.half_w * tf.LANE) + Vector3(0, 0.6, 0)))
	car.freeze = true         # parked: stays put whatever happens
	var start_pos: Vector3 = car.global_position
	for f in 120 * 8:
		await get_tree().physics_frame
	var gap := fposmod(block_p - float(t0["progress"]), tr.length) - float(t0["size"].z) * 0.5 - 2.3
	print("TRAFFIC: stopped with %.1f m between the bumpers (speed %.1f), parked car pushed %.1f m" % [gap, float(t0["v"]), car.global_position.distance_to(start_pos)])
	if float(t0["v"]) > 0.5 or gap < 0.5 or gap > 8.0:
		print("FAIL: traffic does not stop for a car in its lane"); fails += 1
	print("TRAFFIC TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
