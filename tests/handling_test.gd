extends Node
## Handling probes on the open playground pad (dry):
##  BURNOUT – standstill, full throttle for 1.5 s: peak revs, speed
##  DRIFT   – 60 km/h in 2nd, handbrake flick, then full throttle + full lock for 2.5 s:
##            revs (share of the redline), speed change, drift angle, rear wheel spin
##  STRAIGHT – in a drift: let go of everything vs. pull the handbrake – the handbrake must pull the
##             car back in line (body slip under 6 degrees within a second, faster than without)
##  LOCK    – 60 km/h straight, handbrake + full throttle for 1 s: the rear wheels must stand still
##            (locked, the clutch is in) and the car must slow down
## Run: godot --headless --path . res://tests/handling_test.tscn  (ENGINE=1 for engine stage 1)

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var stage := int(OS.get_environment("ENGINE")) if OS.get_environment("ENGINE") != "" else 0
	var ok := true
	for cid in ["r34", "mustang", "m3gt3"]:
		Game.settings["car"] = cid
		Game.settings["tuning"] = {cid: {"engine": stage}}
		# RESPONSE=0.4: throttle response from the tuning menu (default 100 %)
		Game.settings["response"] = {cid: float(OS.get_environment("RESPONSE"))} if OS.get_environment("RESPONSE") != "" else {}
		Game.settings["transmission"] = "manual"
		var world := World.new()
		world.setup({"track": "playground", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry", "weather_seed": 3, "online": false})
		add_child(world)
		for f in 10:
			await get_tree().physics_frame
		var car = world.local_car
		car.transmission = "manual"
		var pr: Rect2 = world.terrain.pad_rect()
		var start := Vector3(pr.get_center().x, 0.5, pr.end.y - 30.0)
		# --- burnout from a standstill ---
		car.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), start + Vector3(-90, 0, 0))
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.gear = 1
		for f in 60:
			await get_tree().physics_frame
		Input.action_press("accelerate")
		var peak := 0.0
		var t := 0.0
		var rpm_at := {}
		while t < 1.5:
			await get_tree().physics_frame
			t += 1.0 / 120.0
			peak = maxf(peak, car.rpm / car.redline)
			for mark in [0.25, 0.5, 1.0]:
				if not rpm_at.has(mark) and t >= mark:
					rpm_at[mark] = car.rpm / car.redline
		Input.action_release("accelerate")
		if peak < 0.9:
			ok = false   # a burnout from a standstill must reach the limiter
		print("BURNOUT %s stage%d: rpm@0.25s %.2f @0.5s %.2f @1s %.2f peak %.2f, speed %.0f km/h" % [cid, stage, rpm_at[0.25], rpm_at[0.5], rpm_at[1.0], peak, car.speed_kmh()])
		# --- power drift ---
		var fwd := Vector3(1, 0, 0)
		car.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), start + Vector3(-110, 0, -60))
		car.angular_velocity = Vector3.ZERO
		car.linear_velocity = fwd * (60.0 / 3.6)
		car.gear = 2
		car.rpm = car.redline * 0.6
		for f in 12:
			car.linear_velocity = fwd * (60.0 / 3.6)
			await get_tree().physics_frame
		var v0: float = car.speed_kmh()
		Input.action_press("steer_left")
		Input.action_press("handbrake")
		Input.action_press("accelerate")
		for f in 30:
			await get_tree().physics_frame
		Input.action_release("handbrake")
		var rpm_sum := 0.0
		var ang_sum := 0.0
		var spin_sum := 0.0
		var n := 0
		var fwd_acc := 0.0
		var prev_v: float = car.speed_kmh()
		t = 0.0
		while t < 2.5:
			await get_tree().physics_frame
			t += 1.0 / 120.0
			rpm_sum += car.rpm / car.redline
			ang_sum += absf(car.drift_angle_deg())
			spin_sum += (absf(float(car.wheels[2]["spin"])) + absf(float(car.wheels[3]["spin"]))) * 0.5
			n += 1
		Input.action_release("accelerate")
		Input.action_release("steer_left")
		print("DRIFT %s stage%d: v %.0f -> %.0f km/h, rpm avg %.2f, angle avg %.0f deg, rear spin avg %.1f m/s, gear %d" % [cid, stage, v0, car.speed_kmh(), rpm_sum / n, ang_sum / n, spin_sum / n, car.gear])
		# --- held drift: a "driver" counter-steers to hold about 35 degrees at full throttle ---
		car.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), start + Vector3(-110, 0, -60))
		car.angular_velocity = Vector3.ZERO
		car.linear_velocity = fwd * (60.0 / 3.6)
		car.gear = 2
		car.rpm = car.redline * 0.6
		for f in 12:
			car.linear_velocity = fwd * (60.0 / 3.6)
			await get_tree().physics_frame
		Input.action_press("steer_left")
		Input.action_press("handbrake")
		Input.action_press("accelerate")
		for f in 24:
			await get_tree().physics_frame
		Input.action_release("handbrake")
		t = 0.0
		var ang2 := 0.0
		var rpm2 := 0.0
		var n2 := 0
		var v_start: float = car.speed_kmh()
		while t < 3.0:
			var ang: float = car.drift_angle_deg()   # signed: + = sliding with the nose to the left
			var err := (absf(ang) - 35.0) / 25.0
			Input.action_release("steer_left")
			Input.action_release("steer_right")
			# too much angle -> counter-steer (right), too little -> steer into the corner (left)
			if err > 0.0:
				Input.action_press("steer_right", clampf(err, 0.0, 1.0))
			else:
				Input.action_press("steer_left", clampf(-err, 0.0, 1.0))
			await get_tree().physics_frame
			t += 1.0 / 120.0
			ang2 += absf(ang)
			rpm2 += car.rpm / car.redline
			n2 += 1
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		Input.action_release("accelerate")
		if car.speed_kmh() < v_start - 10.0:
			ok = false   # flat out in a held drift the car must keep its speed
		print("HELD %s stage%d: v %.0f -> %.0f km/h over 3 s, angle avg %.0f deg, rpm avg %.2f, gear %d" % [cid, stage, v_start, car.speed_kmh(), ang2 / n2, rpm2 / n2, car.gear])
		# --- handbrake in a drift: straightens the car ---
		var slips := {}
		for use_hb in [false, true]:
			car.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), start + Vector3(-110, 0, -60))
			car.angular_velocity = Vector3.ZERO
			car.gear = 2
			for f in 12:
				car.linear_velocity = fwd * (65.0 / 3.6)
				await get_tree().physics_frame
			Input.action_press("steer_left")
			Input.action_press("handbrake")
			Input.action_press("accelerate")
			for f in 24:
				await get_tree().physics_frame
			Input.action_release("handbrake")
			for f in 120:
				await get_tree().physics_frame
			var s0: float = absf(rad_to_deg(car.slip_angle))
			Input.action_release("accelerate")
			Input.action_release("steer_left")
			if use_hb:
				Input.action_press("handbrake")
			var s05 := 0.0
			for f in 120:
				await get_tree().physics_frame
				if f == 59:
					s05 = absf(rad_to_deg(car.slip_angle))
			var s10: float = absf(rad_to_deg(car.slip_angle))
			Input.action_release("handbrake")
			slips[use_hb] = [s0, s05, s10, bool(car.hb_straighten) if use_hb else false, car.speed_kmh()]
		print("STRAIGHT %s: drift %.0f deg -> without handbrake %.0f / %.0f deg, with handbrake %.0f / %.0f deg after 0.5 / 1 s (mode %s, %.0f km/h)" % [cid,
			slips[false][0], slips[false][1], slips[false][2], slips[true][1], slips[true][2], slips[true][3], slips[true][4]])
		if slips[true][0] < 13.0 or slips[true][2] > 6.0 or slips[true][2] > slips[false][2] + 1.0:
			ok = false   # in a drift the handbrake must pull the car back in line
		# --- handbrake with the throttle down: the rear wheels lock ---
		car.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), start + Vector3(-110, 0, -60))
		car.angular_velocity = Vector3.ZERO
		car.gear = 2
		for f in 12:
			car.linear_velocity = fwd * (60.0 / 3.6)
			await get_tree().physics_frame
		var v_l0: float = car.speed_kmh()
		Input.action_press("accelerate")
		Input.action_press("handbrake")
		var roll := 0.0
		for f in 120:
			await get_tree().physics_frame
			if f >= 20:
				for wi in [2, 3]:
					if not bool(car.wheels[wi]["grounded"]):
						continue
					roll = maxf(roll, absf(float(car.wheels[wi]["v_long"]) + float(car.wheels[wi]["spin"])))
		Input.action_release("handbrake")
		Input.action_release("accelerate")
		print("LOCK %s: v %.0f -> %.0f km/h, rear wheel surface speed max %.2f m/s, rpm %.2f" % [cid, v_l0, car.speed_kmh(), roll, car.rpm / car.redline])
		if roll > 0.3 or car.speed_kmh() > v_l0 - 8.0:
			ok = false   # handbrake + throttle: the rears must stay locked and the car slow down
		remove_child(world)
		world.queue_free()
		await get_tree().process_frame
	print("HANDLING TEST %s" % ("OK" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)
