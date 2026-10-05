extends Node
## How high the road edge stands above the ground beside it (the step a car rejoining from the
## grass/sand drives into): rays down at the edge of the drivable road and up to 4 m outside it.
## "biggest single jump" is the steepest step between two rays – with the ramps it stays small.
## Run: godot --headless --path . res://tests/edge_step_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	for tid in (OS.get_environment("STEP_TRACKS").split(",") if OS.get_environment("STEP_TRACKS") != "" else ["ridge", "harbor", "playground", "utah", "gruene_hoelle"]):
		var world := World.new()
		world.setup({"track": tid, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
			"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
		add_child(world)
		if not world.is_loaded:
			await world.loaded
		for k in 3:
			await get_tree().physics_frame
		var space := world.get_world_3d().direct_space_state
		var tr = world.track
		var n: int = tr.sample_count()
		var steps := []          # per sample/side: the largest drop within 2 m outside the edge
		var slopes := []
		for i in range(0, n, 3):
			for side in [-1.0, 1.0]:
				var hw: float = float(tr.off_left[i] if side < 0.0 else tr.off_right[i]) + 0.3 if tr.raised else float(tr.hws[i])
				var top := _hit(space, tr.edge_point(i, side * (hw - 0.3)))
				if is_nan(top):
					continue
				var worst := 0.0
				var prev := top
				var steep := 0.0
				# behind a barrier is out of reach: only up to it (or through an opening)
				var lim := 99.0
				if str(tr.def.get("wall", "none")) != "none" and not tr.raised and not tr.in_wall_gap(i, side):
					lim = float(tr.off_left[i] if side < 0.0 else tr.off_right[i]) - hw - 0.3
				for o in [0.1, 0.3, 0.6, 1.0, 1.5, 2.0, 3.0, 4.0]:
					if o > lim:
						break
					var g := _hit(space, tr.edge_point(i, side * (hw + o)))
					if is_nan(g):
						break
					worst = maxf(worst, top - g)
					steep = maxf(steep, prev - g)
					prev = g
				steps.append(worst)
				if steep > 0.15 and steep < 1.0 and OS.get_environment("STEP_DUMP") != "":
					var prof := []
					for o in [0.0, 0.1, 0.3, 0.6, 1.0, 1.5, 2.0, 3.0, 4.0]:
						prof.append(snappedf(top - _hit(space, tr.edge_point(i, side * (hw + o))), 0.01))
					print("  STEP i=%d side=%d lim=%.1f drop profile %s" % [i, side, lim, prof])
				slopes.append(steep)
		steps.sort()
		slopes.sort()
		var m := steps.size()
		print("%s: ramps %d | drop within 4 m  median %.2f  p90 %.2f  p99 %.2f  max %.2f | biggest single jump p90 %.2f p99 %.2f (n=%d)" % [tid, tr.ramp_count,
			steps[m / 2], steps[m * 9 / 10], steps[m * 99 / 100], steps[m - 1], slopes[m * 9 / 10], slopes[m * 99 / 100], m])
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()


func _hit(space: PhysicsDirectSpaceState3D, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 6, 0), p - Vector3(0, 10, 0), 1)
	var h := space.intersect_ray(q)
	return float(h["position"].y) if not h.is_empty() else NAN
