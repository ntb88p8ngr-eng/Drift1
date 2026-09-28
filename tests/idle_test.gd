extends Node
## Car in gear with no input must stay put (flat and on a slope), also after driving and after reverse.
## Run: godot --headless --path . res://tests/idle_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var track_id := "ridge"
	var at := 10
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr(8)
		elif a.begins_with("--sample="):
			at = int(a.substr(9))
		elif a.begins_with("--km="):
			at = -int(float(a.substr(5)) * 1000.0)
	var world := World.new()
	world.setup({"track": track_id, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 1, "online": false})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var car = world.local_car
	var tr = world.track
	if at < 0:
		at = int(-at / tr.SPACING)
	var fails := 0
	for case in ["rest", "after_drive", "after_reverse"]:
		car.place(tr.transform_at(at, 0.0, 0.6))
		car.controls_locked = false
		for f in 60:
			await get_tree().physics_frame
		if case == "after_drive":
			Input.action_press("accelerate", 1.0)
			for f in 90:
				await get_tree().physics_frame
			Input.action_release("accelerate")
			Input.action_press("brake", 1.0)
			while car.forward_speed > 0.3:
				await get_tree().physics_frame
			Input.action_release("brake")
		elif case == "after_reverse":
			Input.action_press("brake", 1.0)
			for f in 150:
				await get_tree().physics_frame
			Input.action_release("brake")
			Input.action_press("accelerate", 1.0)
			while car.forward_speed < -0.3:
				await get_tree().physics_frame
			Input.action_release("accelerate")
		var p0: Vector3 = car.global_position
		var worst := 0.0
		for f in 120 * 6:
			await get_tree().physics_frame
			worst = maxf(worst, absf(car.forward_speed))
		var d: Vector3 = car.global_position - p0
		var moved := Vector2(d.x, d.z).length()
		var ok := moved < 0.3
		if not ok:
			fails += 1
		print("  %s %s (slope %.1f %%): moved %.2f m in 6 s, max speed %.2f m/s, gear %d, rpm %.0f" % ["ok  " if ok else "FAIL", case, -car.global_transform.basis.z.y * 100.0, moved, worst, car.gear, car.rpm])
	print("IDLE TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
