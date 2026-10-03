extends Node
## Trees can be felled: a car driven into a tree near the road at 15 m/s knocks it over (a falling
## body, the instances hidden), and a city bench is shoved away.
## Run: godot --headless --path . res://tests/tree_test.tscn [-- --track=ridge]

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var track := "ridge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track = a.substr(8)
	var world := World.new()
	world.setup({"track": track, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var th = world.scenery.trees
	print("TREES: %s" % str(th.stats))
	var car = world.local_car
	# a registered tree close to the road
	var target = null
	var best := 1e9
	for g in th._grid:
		for t in th._grid[g]:
			var o: Vector3 = (t["xf"] as Transform3D).origin
			var d: float = world.terrain.distance_to_road(o.x, o.z)
			if d > 12.0 and d < best:
				best = d
				target = t
	if target == null:
		print("TREE TEST: FAIL (no tree)")
		get_tree().quit(1)
		return
	var o: Vector3 = (target["xf"] as Transform3D).origin
	# come from the woods (the road side has the track wall)
	var dir := Vector3(1, 0, 0)
	for k in 16:
		var d2 := Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0))
		if world.terrain.distance_to_road(o.x - d2.x * 8.0, o.z - d2.z * 8.0) > world.terrain.distance_to_road(o.x - dir.x * 8.0, o.z - dir.z * 8.0):
			dir = d2
	var start := o - dir * 8.0
	start.y = world.terrain.height_at(start.x, start.z) + 0.6
	car.controls_locked = true
	car.contact_monitor = true
	car.max_contacts_reported = 4
	car.place(Transform3D(Basis.looking_at(dir, Vector3.UP), start))
	for f in 10:
		await get_tree().physics_frame
	var down := false
	for f in 500:
		car.linear_velocity = Vector3(dir.x * 15.0, car.linear_velocity.y, dir.z * 15.0)
		await get_tree().physics_frame
		if false:
			print("  f%d car %s dist %.1f v %.1f %s" % [f, str(car.global_position), Vector2(car.global_position.x - o.x, car.global_position.z - o.z).length(), car.linear_velocity.length(), str(car.get_colliding_bodies())])
		if target["down"]:
			down = true
			break
	var falling := th.get_children().filter(func(n): return n is RigidBody3D)
	var tilt := 0.0
	for f in 120:
		await get_tree().physics_frame
	if not falling.is_empty():
		tilt = rad_to_deg((falling[0] as Node3D).global_transform.basis.y.angle_to(Vector3.UP))
	print("TREE: tree %.1f m off the road at %s, felled %s, falling bodies %d, tilt after 2 s %.0f°, car speed %.1f" % [best, str(o), str(down), falling.size(), tilt, car.linear_velocity.length()])
	var ok: bool = down and falling.size() == 1 and tilt > 25.0
	print("TREE TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
