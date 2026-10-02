extends Node
## Neo Tokyo: a car driving out through the fog at the city's border comes back turned round.
## Run: godot --headless --path . res://tests/fog_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var fog = world.scenery.city.fog
	var r: Rect2 = fog.rect
	var car = world.local_car
	# heading out of the east side, 10 m inside the border
	var start := Vector3(r.end.x - 10.0, 0.6, r.get_center().y)
	car.place(Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), start))
	var turned := false
	for f in 120 * 4:
		car.linear_velocity = Vector3(car.linear_velocity.x, car.linear_velocity.y, car.linear_velocity.z) if turned else Vector3(15, car.linear_velocity.y, 0)
		await get_tree().physics_frame
		if not turned and car.linear_velocity.x < 0.0:
			turned = true
	var p: Vector3 = car.global_position
	var fwd: Vector3 = -car.global_transform.basis.z
	print("FOG: border x %.0f, car x %.1f, heading x %.2f, turned %s" % [r.end.x, p.x, fwd.x, turned])
	var ok: bool = turned and p.x < r.end.x + 4.0 and fwd.x < 0.0
	print("FOG TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
