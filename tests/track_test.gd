extends Node
## Loads a track and drops the car at spots all around the lap: it has to come to rest on the road
## (not sink into the terrain, not float above it). Prints the load time.
## Run: godot --headless --path . res://tests/track_test.tscn -- --track=gruene_hoelle

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var track_id := "gruene_hoelle"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--track="):
			track_id = a.substr(8)
	var t0 := Time.get_ticks_msec()
	var world := World.new()
	world.setup({"track": track_id, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 1, "online": false})
	add_child(world)
	print("TRACK: %s loaded in %d ms, %.0f m, %d samples, height %.1f … %.1f m" % [track_id, Time.get_ticks_msec() - t0,
		world.track.length, world.track.sample_count(), world.track.min_y, world.track.max_y])
	var car = world.local_car
	var tr = world.track
	var fails := 0
	var n: int = tr.sample_count()
	var spots: Array = []
	for k in 24:
		spots.append(int(float(k) / 24.0 * n))
	for sec in tr.meta.get("sections", []):
		spots.append(int(float(sec[1]) / tr.SPACING) % n)
	for i in spots:
		car.place(tr.transform_at(i, 0.0, 0.6))
		for f in 50:
			await get_tree().physics_frame
		var p: Vector3 = car.global_position
		var proj: Array = tr.project(p, i)
		var road_y: float = tr.samples[proj[0]].y + tr.ROAD_Y
		var body_y: float = p.y - road_y
		# the car body rests 0.16 m under the road surface on every track (its origin sits between the axles)
		var ok: bool = body_y > -0.3 and body_y < 0.1 and absf(float(proj[2])) < tr.half_w
		if not ok:
			fails += 1
		var name: String = tr.section_at(float(proj[1]))
		print("  %s sample %5d (%s): body %.2f m above the road, lateral %.1f" % ["ok  " if ok else "FAIL", i, name, body_y, float(proj[2])])
	# drive a few hundred metres on steep and twisty stretches (simple autopilot: ~90 km/h, steer at a
	# point 24 m ahead) – the car has to stay on the road surface the whole time
	if tr.elevated:
		for km in [4.3, 9.4, 11.5, 15.5]:
			var i0 := int(km * 1000.0 / tr.SPACING) % n
			car.place(tr.transform_at(i0, 0.0, 0.6))
			car.controls_locked = false
			var lo := 1e9
			var hi := -1e9
			var worst_lat := 0.0
			var cam_up := -1e9
			var hint := i0
			for f in 120 * 9:
				var p: Vector3 = car.global_position
				var proj: Array = tr.project(p, hint)
				hint = proj[0]
				var ahead: Vector3 = tr.samples[(int(proj[0]) + 12) % n]
				var to := ahead - p
				var fwd: Vector3 = -car.global_transform.basis.z
				var err := Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z))
				var steer := clampf(err * 2.5 + float(proj[2]) * -0.03, -1.0, 1.0)
				Input.action_release("steer_left")
				Input.action_release("steer_right")
				if steer > 0.0:
					Input.action_press("steer_right", steer)
				else:
					Input.action_press("steer_left", -steer)
				var v: float = car.speed_kmh()
				Input.action_release("accelerate")
				Input.action_release("brake")
				if v < 85.0:
					Input.action_press("accelerate", 0.8)
				elif v > 100.0:
					Input.action_press("brake", 0.5)
				await get_tree().physics_frame
				var rel: float = p.y - (tr.samples[proj[0]].y + tr.ROAD_Y)
				lo = minf(lo, rel)
				hi = maxf(hi, rel)
				worst_lat = maxf(worst_lat, absf(float(proj[2])))
				if f > 120:
					cam_up = maxf(cam_up, world.camera.global_position.y - car.global_position.y)
			for act in ["accelerate", "brake", "steer_left", "steer_right"]:
				Input.action_release(act)
			# the chase camera stays a few metres above the car (not stuck at some absolute height)
			var ok: bool = lo > -0.6 and worst_lat < tr.wall_base and cam_up < 6.0
			if not ok:
				fails += 1
			print("  %s drive from %.1f km (%s): height over the road %.2f … %.2f m, max lateral %.1f m, camera ≤ %.1f m above the car, %.0f km/h" % ["ok  " if ok else "FAIL", km, tr.section_at(fposmod(km * 1000.0 - tr.start_dist, tr.length)), lo, hi, worst_lat, cam_up, car.speed_kmh()])
	print("TRACK: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
