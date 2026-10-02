extends Node
## Neo Tokyo: a car driven into a pedestrian knocks them apart into flying blocks.
## Run: godot --headless --path . res://tests/people_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var people = world.scenery.people
	var fails := 0
	# somebody standing on the ground in the city, away from the race route
	var target = null
	for key in people._grid:
		for e in people._grid[key]:
			var o: Vector3 = (e[2] as Transform3D).origin
			if absf(o.y) < 0.3 and world.terrain.distance_to_road(o.x, o.z) > 60.0:
				target = e
				break
		if target != null:
			break
	var o: Vector3 = (target[2] as Transform3D).origin
	var car = world.local_car
	var dir := Vector3(1, 0, 0)
	car.place(Transform3D(Basis.looking_at(dir, Vector3.UP), o - dir * 10.0 + Vector3(0, 0.7, 0)))
	for f in 90:
		await get_tree().physics_frame        # settle on its wheels first
	car.linear_velocity = dir * 14.0
	# the blocks must never push the car: no jump, no extra speed
	var max_up := 0.0
	var max_speed := 0.0
	for f in 120:
		await get_tree().physics_frame
		max_up = maxf(max_up, car.linear_velocity.y)
		max_speed = maxf(max_speed, car.linear_velocity.length())
	var pieces: int = people._pieces.size()
	print("PEOPLE: %s, pieces flying %d, car: max upward %.2f m/s, max speed %.1f m/s" % [str(people.stats), pieces, max_up, max_speed])
	if bool(target[4]) or pieces < 10:
		print("FAIL: the pedestrian wasn't knocked over"); fails += 1
	if max_up > 1.5 or max_speed > 14.5:
		print("FAIL: the blocks threw the car about"); fails += 1
	print("PEOPLE TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
