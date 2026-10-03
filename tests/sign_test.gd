extends Node
## Road signs can be knocked down: a car at 15 m/s drives into a sign beside the track – it breaks
## off (instances hidden) and flies away as one loose body.
## Run: godot --headless --path . res://tests/sign_test.tscn [-- --track=ridge]

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
	var sh = world.scenery.signs
	print("SIGNS: %s" % str(sh.stats))
	var target = null
	for s in sh._signs:
		if not (s["parts"] as Array).is_empty():
			target = s
			break
	if target == null:
		print("SIGN TEST: FAIL (no sign with instances)")
		get_tree().quit(1)
		return
	var o: Vector3 = target["foot"]
	var car = world.local_car
	car.controls_locked = true
	# come from away from the road (the barrier is on the other side)
	var dir := Vector3(1, 0, 0)
	for k in 16:
		var d2 := Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0))
		if world.terrain.distance_to_road(o.x - d2.x * 8.0, o.z - d2.z * 8.0) > world.terrain.distance_to_road(o.x - dir.x * 8.0, o.z - dir.z * 8.0):
			dir = d2
	var start := o - dir * 8.0
	start.y = world.terrain.height_at(start.x, start.z) + 0.6
	car.place(Transform3D(Basis.looking_at(dir, Vector3.UP), start))
	for f in 10:
		await get_tree().physics_frame
	var down := false
	for f in 300:
		car.linear_velocity = Vector3(dir.x * 15.0, car.linear_velocity.y, dir.z * 15.0)
		await get_tree().physics_frame
		if target["down"]:
			down = true
			break
	for f in 90:
		await get_tree().physics_frame
	var bodies := sh.get_children().filter(func(n): return n is RigidBody3D)
	var moved := 0.0
	for b in bodies:
		moved = maxf(moved, (b as Node3D).global_position.distance_to(o))
	print("SIGN: sign at %s with %d parts, knocked %s, bodies %d, moved %.1f m" % [str(o), (target["parts"] as Array).size(), str(down), bodies.size(), moved])
	var ok: bool = down and bodies.size() == 1 and moved > 1.5
	print("SIGN TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
