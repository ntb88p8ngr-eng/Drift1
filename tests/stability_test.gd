extends Node
## High-speed stability: every car at 120 and 170 km/h on a big flat plane does a quick lane change
## with full (keyboard) steering – left, right, let go – while holding its speed. It must not spin
## out, the drift angle has to stay moderate and the car has to settle (no growing pendulum).
## With --abs/--esp the assists are switched on. Run: godot --headless --path . res://tests/stability_test.tscn

const Car = preload("res://scripts/car/car.gd")


func _ready() -> void:
	Game.persist = false
	var args := OS.get_cmdline_user_args()
	Game.settings["abs"] = args.has("--abs")
	Game.settings["esp"] = args.has("--esp")
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	add_child(ground)
	var fails := 0
	for cid in ["r34", "mustang", "m3gt3"]:
		for kmh in [120.0, 170.0]:
			var car := Car.new()
			car.car_id = cid
			car.paint = Game.get_paint("red", "")
			car.transmission = "auto"
			add_child(car)
			var v: float = kmh / 3.6
			car.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 1500)))
			car.gear = 5
			for f in 60:
				car.linear_velocity = Vector3(0, car.linear_velocity.y, -v)
				await get_tree().physics_frame
			var max_slip := 0.0
			var yaw0: float = car.global_rotation.y
			var late_rate := 0.0
			var t := 0.0
			while t < 6.0:
				# hold the speed with the throttle
				Input.action_release("accelerate")
				if car.speed < v:
					Input.action_press("accelerate", clampf((v - car.speed) * 0.5, 0.2, 1.0))
				Input.action_release("steer_left")
				Input.action_release("steer_right")
				if t > 0.5 and t < 1.1:
					Input.action_press("steer_left", 1.0)
				elif t >= 1.1 and t < 1.7:
					Input.action_press("steer_right", 1.0)
				await get_tree().physics_frame
				t += 1.0 / 120.0
				max_slip = maxf(max_slip, absf(car.slip_angle))
				if t > 4.0:
					late_rate = maxf(late_rate, absf(car.angular_velocity.y))
			Input.action_release("accelerate")
			var turned := absf(wrapf(car.global_rotation.y - yaw0, -PI, PI))
			var spun := turned > deg_to_rad(60.0) or max_slip > deg_to_rad(35.0)
			var settled := late_rate < 0.15
			if spun or not settled:
				fails += 1
			print("%s %-8s %3d km/h: max drift %4.1f°, heading change %5.1f°, yaw rate after 4 s %.2f rad/s, end speed %3.0f km/h" % [
				"FAIL" if (spun or not settled) else "ok  ", cid, int(kmh), rad_to_deg(max_slip), rad_to_deg(turned), late_rate, car.speed_kmh()])
			car.queue_free()
			await get_tree().physics_frame
	print("STABILITY TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
