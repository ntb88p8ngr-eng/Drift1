extends Node
## Grüne Hölle pit lane: a car put on the lane rolls along it (flat, nothing in the way).
## Run: godot --headless --path . res://tests/pit_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "gruene_hoelle", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var pd = world.scenery.festival.paddock
	var car = world.local_car
	var a: Vector3 = pd._at(pd.PIT_FROM + 20.0, pd._lat - 2.0)
	var b: Vector3 = pd._at(pd.PIT_FROM + 30.0, pd._lat - 2.0)
	var dir := (b - a)
	dir.y = 0.0
	a.y = world.terrain.height_at(a.x, a.z) + 0.6
	car.place(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), a))
	car.controls_locked = false
	for f in 60:
		await get_tree().physics_frame
	var y0: float = car.global_position.y
	var p0: Vector3 = car.global_position
	Input.action_press("accelerate", 1.0)
	var ymin := y0
	var ymax := y0
	for f in 120 * 4:
		await get_tree().physics_frame
		ymin = minf(ymin, car.global_position.y)
		ymax = maxf(ymax, car.global_position.y)
		if f % 60 == 0:
			var pr: Array = world.track.project(car.global_position, -1)
			print("  t %.1f: progress %.0f lateral %.1f y %+.2f ground %+.2f speed %.0f" % [f / 120.0,
				fposmod(float(world.track.dists[int(pr[0])]) - world.track.start_dist + world.track.length * 0.5, world.track.length) - world.track.length * 0.5,
				float(pr[2]), car.global_position.y - y0, world.terrain.height_at(car.global_position.x, car.global_position.z) - y0, car.speed * 3.6])
	Input.action_release("accelerate")
	var moved: float = car.global_position.distance_to(p0)
	print("PIT: moved %.0f m along the lane, height %.2f .. %.2f, speed %.0f km/h" % [moved, ymin - y0, ymax - y0, car.speed * 3.6])
	var ok := moved > 25.0 and ymax - ymin < 4.0
	print("PIT TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
