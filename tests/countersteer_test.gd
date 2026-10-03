extends Node
## A car sliding on all four tyres (35° slip, spinning) can be caught by counter-steering:
## compared with no steering, the slip and the rotation come down clearly.
## Run: godot --headless --path . res://tests/countersteer_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var car_id := "r34"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			car_id = a.substr(6)
	Game.settings["car"] = car_id
	Game.settings["owned_cars"] = [car_id]
	var world := World.new()
	world.setup({"track": "playground", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var car = world.local_car
	var results := {}
	for mode in ["none", "counter"]:
		var xf: Transform3D = car.global_transform
		var p0 := Vector3(0, xf.origin.y + 0.05, 40.0)
		car.place(Transform3D(Basis(Vector3.UP, 0.0), p0))
		for f in 30:
			await get_tree().physics_frame
		# moving along -Z at 60 km/h, nose turned 35° to the left, rotating further left
		var ang := deg_to_rad(35.0)
		car.global_transform = Transform3D(Basis(Vector3.UP, ang), car.global_position)
		car.linear_velocity = Vector3(0, 0, -16.7)
		car.angular_velocity = Vector3(0, 1.2, 0)
		var slip0: float = 0.0
		# counter-steer: steer right (into the slide)
		if mode == "counter":
			Input.action_press("steer_right")
		Input.action_press("accelerate", 0.4)
		for f in 120:
			await get_tree().physics_frame
			if f == 2:
				slip0 = car.slip_angle
		Input.action_release("steer_right")
		var slip1: float = car.slip_angle
		var yaw1: float = car.angular_velocity.y
		# hands straight again: no snap into a slide the other way
		var worst := 0.0
		for f in 90:
			await get_tree().physics_frame
			worst = maxf(worst, absf(car.slip_angle))
		Input.action_release("accelerate")
		results[mode] = [slip0, slip1, yaw1, worst]
		print("COUNTER: %s: slip %.0f° -> %.0f° after 1 s (yaw rate %.2f), then wheel straight: up to %.0f°" % [mode, rad_to_deg(slip0), rad_to_deg(slip1), yaw1, rad_to_deg(worst)])
	var ok: bool = absf(results["counter"][1]) < absf(results["none"][1]) * 0.6 and absf(results["counter"][1]) < deg_to_rad(28.0) \
		and float(results["counter"][3]) < deg_to_rad(35.0)
	print("COUNTERSTEER TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
