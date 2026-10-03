extends Node
## The "Bouncing Yaris": standing still it keeps bouncing (never settles) but stays on the ground,
## and driving it still works. Run: godot --headless --path . res://tests/bounce_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	Game.settings["car"] = "yaris"
	Game.settings["owned_cars"] = ["yaris"]
	var world := World.new()
	world.setup({"track": "playground", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var car = world.local_car
	print("BOUNCE: car ", car.car_id, " bounce ", car.bounce)
	var ys: Array = []
	for f in 120 * 8:
		await get_tree().physics_frame
		if f > 120 * 4:
			ys.append(car.global_position.y)
	var lo: float = ys.min()
	var hi: float = ys.max()
	print("BOUNCE: standing, height %.2f .. %.2f (amplitude %.2f m)" % [lo, hi, hi - lo])
	# drive
	var p0: Vector3 = car.global_position
	Input.action_press("accelerate")
	for f in 120 * 5:
		await get_tree().physics_frame
	Input.action_release("accelerate")
	var dist: float = car.global_position.distance_to(p0)
	print("BOUNCE: drove %.0f m in 5 s, up %.2f" % [dist, car.global_transform.basis.y.y])
	var ok: bool = hi - lo > 0.04 and hi - lo < 1.5 and dist > 20.0 and car.global_transform.basis.y.y > 0.5
	print("BOUNCE TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
