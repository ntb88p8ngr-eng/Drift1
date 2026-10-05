extends Node
## Back onto the road from the side: a car starts beside the road (sand, grass) at a slow pace,
## angled towards it, and drives on. Counts how often it stops dead at the edge (the nose against
## the step) and the hardest hit. Run: godot --headless --path . res://tests/rejoin_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	for tid in ["utah"]:
		var world := World.new()
		world.setup({"track": tid, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
			"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
		add_child(world)
		if not world.is_loaded:
			await world.loaded
		var car = world.local_car
		var tr = world.track
		var n: int = tr.sample_count()
		var tries := 0
		var ok := 0
		var worst := 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var holder := {"thr": 0.6}
		car.ai_fn = func() -> Array: return [holder["thr"], 0.0, 0.0, false, false]
		car.controls_locked = false
		for k in 40:
			var i := rng.randi() % n
			var side := 1.0 if k % 2 == 0 else -1.0
			var wi: float = float(tr.off_left[i] if side < 0.0 else tr.off_right[i]) + 0.3 if tr.raised else float(tr.hws[i])
			if str(tr.def.get("wall", "none")) != "none" and not tr.in_wall_gap(i, side):
				continue
			var p: Vector3 = tr.edge_point(i, side * (wi + 6.0))
			var g: float = world.terrain.height_at(p.x, p.z)
			if absf(g - tr.edge_point(i, side * wi).y) > 1.5 or world.terrain.distance_to_road(p.x, p.z) < wi + 4.0:
				continue
			# heading: 50° across the road, towards it, along the driving direction
			var into: Vector3 = -tr.rights[i] * side
			var dir: Vector3 = (tr.tangents[i] * cos(deg_to_rad(50.0)) + into * sin(deg_to_rad(50.0))).normalized()
			dir.y = 0.0
			var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(p.x, g + 0.6, p.z))
			car.place(xf)
			car.linear_velocity = dir * 6.0
			tries += 1
			var t := 0.0
			var prev_v := 6.0
			var hit := 0.0
			var reached := false
			while t < 4.0:
				await get_tree().physics_frame
				t += 1.0 / 120.0
				var v: float = car.linear_velocity.dot(dir)
				hit = maxf(hit, (prev_v - v) * 120.0)       # deceleration, m/s²
				prev_v = v
				var pr: Array = tr.project(car.global_position, i)
				if absf(float(pr[2])) < wi - 1.5:
					reached = true
					break
			if reached:
				ok += 1
			worst = maxf(worst, hit)
		print("REJOIN %s: %d/%d back on the road, hardest stop %.0f m/s²" % [tid, ok, tries, worst])
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()
