extends Node
## Full-throttle acceleration in automatic on a flat, grippy plane: with grip the revs must follow the
## road speed (no riding the limiter in 2nd while the car lags behind), the box shifts up when the
## road speed is there, and after the 2-3 shift the engine is still in its power band (no hole).
## Run: godot --headless --path . res://tests/shift_test.tscn

const Car = preload("res://scripts/car/car.gd")


func _ready() -> void:
	Game.persist = false
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	var ok := true
	for cid in ["r34", "mustang", "m3gt3"]:
		Game.settings["tuning"] = {}
		Game.settings["response"] = {}
		var car := Car.new()
		car.car_id = cid
		car.paint = Game.get_paint("red")
		car.transmission = "auto"
		car.input_enabled = false
		var full := [1.0, 0.0, 0.0, false]
		car.ai_fn = func() -> Array: return full
		add_child(car)
		car.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 1500)))
		full[0] = 0.0
		for f in 60:
			await get_tree().physics_frame
		full[0] = 1.0
		var t := 0.0
		var lim2 := 0.0
		var slip2 := 0.0
		var n2 := 0
		var in_gear := 0.0
		var last_gear: int = car.gear
		var after3 := -1.0
		var boost3 := -1.0
		var t3 := -1.0
		var log := ""
		while t < 9.0:
			await get_tree().physics_frame
			t += 1.0 / 120.0
			var g: int = car.gear
			if g != last_gear:
				if last_gear == 2 and g == 3:
					t3 = t
				last_gear = g
				in_gear = 0.0
			in_gear += 1.0 / 120.0
			var ground_rpm: float = absf(car.forward_speed / car.radius * 60.0 / TAU * car._gear_ratio())
			if g == 2 and in_gear > 0.4 and car.shift_timer <= 0.0:
				slip2 += (car.rpm - ground_rpm) / car.redline
				n2 += 1
				if car.rpm > car.redline * 0.95:
					lim2 += 1.0 / 120.0
			if t3 > 0.0 and after3 < 0.0 and t > t3 + 0.5:
				after3 = car.rpm / car.redline
				boost3 = car.boost
			if fmod(t, 0.5) < 1.0 / 120.0:
				log += " %.1fs:g%d %.2f/%.2f %.0fkm/h" % [t, g, car.rpm / car.redline, ground_rpm / car.redline, car.speed_kmh()]
		var s2 := slip2 / maxf(n2, 1)
		print("SHIFT %s: 2nd: %.2f s on the limiter, revs %.2f above road speed; 0.5 s after 2-3: rpm %.2f boost %.2f; %.0f km/h after 9 s" % [cid, lim2, s2, after3, boost3, car.speed_kmh()])
		print("   ", log)
		# AWD (R34): with its grip the revs must follow the road speed in 2nd; the rear-drive cars may
		# spin their tyres in 2nd (their torque is above the grip), but not for long
		var awd: bool = car.rear_split < 1.0
		if (awd and (lim2 > 0.8 or s2 > 0.12)) or lim2 > 1.5 or (after3 >= 0.0 and after3 < (0.55 if awd else 0.4)):
			print("FAIL: %s" % cid)
			ok = false
		remove_child(car)
		car.queue_free()
		await get_tree().process_frame
	print("SHIFT TEST %s" % ("OK" if ok else "FAILED"))
	get_tree().quit(0 if ok else 1)
