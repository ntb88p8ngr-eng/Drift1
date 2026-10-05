extends Node
## Utah's lake roads hold a car where they cross water: the ring road's bridge over the inflow and
## the roads out to the lap. A car dropped onto them from 1.5 m lands on the deck, not in the river.
## Run: godot --headless --path . res://tests/lake_bridge_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "utah", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var lake = world.scenery.get_node("Desert/Lake")
	var water = lake.water
	var car = world.local_car
	car.ai_fn = func() -> Array: return [0.0, 1.0, 0.0, false, false]
	var spots: Array = []
	# the ring's bridge: at the inflow
	var a_in: float = lake._river_angle(0)
	spots.append(["ring bridge", lake._ring_point(a_in)])
	spots.append(["ring bridge edge", lake._ring_point(a_in, float(water.ring_w) * 0.3)])
	# every ring/spoke road point that lies over water
	for k in 360:
		var a := TAU * k / 360.0
		var p: Vector3 = lake._ring_point(a)
		if lake.terrain.height_at(p.x, p.z) < p.y - 1.5:
			spots.append(["ring over low ground %d°" % k, p])
	# for reference: on the ring over solid ground
	spots.push_front(["ring on land", lake._ring_point(a_in + PI * 0.5)])
	var ok := true
	for s in spots:
		var p: Vector3 = s[1]
		car.place(Transform3D(Basis.IDENTITY, p + Vector3(0, 1.5, 0)))
		for f in 120:
			await get_tree().physics_frame
		var dy: float = car.global_position.y - p.y
		var held := dy > -0.5
		print("LAKE %s at %s: car %.2f m above the deck %s" % [s[0], p.snapped(Vector3.ONE * 0.1), dy, "" if held else "  <-- FELL"])
		ok = ok and held
	print("LAKE BRIDGE TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
