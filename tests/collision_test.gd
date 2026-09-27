extends Node
## A car driven into a street lamp knocks it over; a car driven into the grandstand is stopped.
## Run: godot --headless --path . res://tests/collision_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "ridge", "mode": "free", "laps": 1, "time_of_day": "noon", "weather": "dry", "day_cycle": 0, "weather_seed": 1, "online": false})
	add_child(world)
	for f in 5:
		await get_tree().physics_frame
	var car = world.local_car
	var ok := true
	# --- lamp ---
	var lamps: Array = world.scenery.find_children("Lamp", "RigidBody3D", false, false)
	var lamp: RigidBody3D = lamps[0]
	var fwd: Vector3 = -lamp.global_basis.z     # the arm points over the road
	# from behind (the barrier is on the road side of the lamp)
	var start: Vector3 = lamp.global_position - fwd * 8.0
	start.y = world.terrain.height_at(start.x, start.z) + 0.8
	car.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), start)
	for f in 150:
		if f < 40:
			car.linear_velocity = Vector3(fwd.x * 14.0, car.linear_velocity.y, fwd.z * 14.0)
		await get_tree().physics_frame
	var tilt := rad_to_deg(lamp.global_basis.y.angle_to(Vector3.UP))
	print("COLLISION lamp frozen=%s tilt=%.0f°" % [lamp.freeze, tilt])
	if lamp.freeze or tilt < 20.0:
		ok = false
	# --- grandstand ---
	var g: Transform3D = world.track.gantry_xf
	var stand: Vector3 = g * Vector3(world.track.stand_x + 7.0, 0, 0)
	var dir: Vector3 = (stand - (g * Vector3(0, 0, 0))).normalized()
	dir.y = 0
	var p0: Vector3 = stand - dir * 4.2 + Vector3(0, 0.8, 0)   # between barrier and stand
	car.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), p0)
	car.linear_velocity = dir * 12.0
	for f in 150:
		if f < 20:
			car.linear_velocity = Vector3(dir.x * 12.0, car.linear_velocity.y, dir.z * 12.0)
		await get_tree().physics_frame
	var through: float = (car.global_position - stand).dot(dir)
	print("COLLISION grandstand: car %.1f m past the stand centre (<0 = stopped in front)" % through)
	if through > 0.5:
		ok = false
	print("COLLISION TEST %s" % ("OK" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)
