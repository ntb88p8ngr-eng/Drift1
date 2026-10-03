extends Node
## Neo Tokyo's street furniture: a car at walking pace shoves a bench and a bin away (they move,
## the car hardly slows), a car at 50 km/h smashes a bus shelter into pieces.
## Run: godot --headless --path . res://tests/props_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "tokyo", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var lamps = world.scenery.city.lamps
	print("PROPS: %s" % str(lamps.stats))
	var car = world.local_car
	car.controls_locked = true
	var ok := true
	for job in [["bench", 4.0], ["bin", 4.0], ["shelter", 14.0], ["tsign0", 12.0], ["tsign3", 12.0]]:
		var kind: String = job[0]
		var speed: float = job[1]
		var pl = null
		for p in lamps.poles:
			if p["kind"] == kind and not p["broken"]:
				pl = p
				break
		if pl == null:
			print("PROPS: no %s" % kind)
			ok = false
			continue
		var xf: Transform3D = pl["xf"]
		var face: Vector3 = -xf.basis.z           # towards the road (a bench sits with its back to it)
		if kind == "bench":
			face = -face
		var dir := -face                          # drive in from the road side
		var target: Vector3 = xf * lamps._centre_of(kind)
		target.y = 0.0
		var before: int = lamps.get_child_count()
		car.place(Transform3D(Basis.looking_at(dir, Vector3.UP), target - dir * 7.0 + Vector3(0, 0.6, 0)))
		for f in 10:
			await get_tree().physics_frame
		var hit := false
		for f in 400:
			car.linear_velocity = Vector3(dir.x * speed, car.linear_velocity.y, dir.z * speed)
			await get_tree().physics_frame
			if pl["broken"]:
				hit = true
				break
		for f in 120:
			car.linear_velocity = Vector3(dir.x * speed, car.linear_velocity.y, dir.z * speed)
			await get_tree().physics_frame
		var bodies: Array = []
		for n in lamps.get_children().slice(before):
			if n is RigidBody3D:
				bodies.append(n)
		var moved := 0.0
		for b in bodies:
			moved = maxf(moved, (b as Node3D).global_position.distance_to(target))
		print("PROPS: %s at %.0f m/s: hit %s, %d pieces, moved up to %.1f m" % [kind, speed, str(hit), bodies.size(), moved])
		var want := 5 if kind == "shelter" else 1
		if kind.begins_with("tsign"):
			want = 1
		ok = ok and hit and bodies.size() >= want and moved > 1.0
		car.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0) + target + Vector3(0, 0, 30)))
	print("PROPS TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
