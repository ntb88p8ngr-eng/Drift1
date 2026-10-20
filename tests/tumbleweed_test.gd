extends Node
## Utah: while driving, tumbleweeds come rolling across the road ahead now and then (and hop along).
## The car is carried along the lap at 25 m/s for 90 s; counts the ones that pass within 15 m of it.
## Run: godot --headless --fixed-fps 60 --path . res://tests/tumbleweed_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "utah", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var de = world.scenery.desert
	var tr = world.track
	var car = world.local_car
	car.freeze = true
	var hz := float(Engine.physics_ticks_per_second)
	var d := 100.0
	var close := {}
	var max_hop := 0.0
	var in_view := 0
	for f in int(90.0 * hz):
		d += 25.0 / hz
		var i: int = tr.index_at(fposmod(d, tr.length))
		car.global_transform = Transform3D(Basis.looking_at(tr.tangents[i], Vector3.UP), (tr.samples[i] as Vector3) + Vector3(0, 0.4, 0))
		car.linear_velocity = (tr.tangents[i] as Vector3) * 25.0
		await get_tree().physics_frame
		for b in de._gust_weeds:
			var p: Vector3 = b.global_position
			var dist := p.distance_to(car.global_position)
			if dist < 15.0:
				close[b.get_instance_id()] = true
			if dist < 120.0:
				in_view += 1
				max_hop = maxf(max_hop, p.y - de.terrain.height_at(p.x, p.z) - float(b.get_meta("r", 0.5)))
	var n := close.size()
	print("TUMBLEWEED: %d sent, %d different ones within 15 m of the car in 90 s, %.0f s with one within 120 m, highest hop %.2f m" % [int(de.stats.get("gusts", 0)), n, in_view / hz, max_hop])
	var ok := n >= 2 and max_hop > 0.15 and max_hop < 3.0
	print("TUMBLEWEED TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
