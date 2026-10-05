extends Node
## Looks for colliders standing on the driving line: a car-sized box swept along every track sample
## (five lanes) must touch nothing invisible: only cars and visible props may stand there.
## Run: godot --headless --path . res://tests/wall_probe.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var args := OS.get_cmdline_user_args()
	var tracks: Array = args if args.size() > 0 else ["playground", "utah", "harbor", "ridge"]
	var total := 0
	for tid in tracks:
		var world := World.new()
		world.setup({"track": tid, "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
			"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
		add_child(world)
		if not world.is_loaded:
			await world.loaded
		for k in 3:
			await get_tree().physics_frame
		var space := world.get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 0.6, 3.0)
		q.shape = box
		var seen := {}
		var raw := {}
		var tr = world.track
		var n: int = tr.sample_count()
		var hw: float = float(tr.half_w) - 2.0
		for i in range(0, n, 2):
			for lat in [-hw, -hw * 0.5, 0.0, hw * 0.5, hw]:
				q.transform = tr.transform_at(i, lat, 0.0)
				q.transform.origin += q.transform.basis.y * 0.55
				for h in space.intersect_shape(q, 16):
					var c = h["collider"]
					raw[str(c.name) if c is Node else str(c)] = int(raw.get(str(c.name) if c is Node else str(c), 0)) + 1
					if c is VehicleBody3D or str(c.name).begins_with("Car_") or (c is RigidBody3D and _vis(c).contains(":true")):
						continue
					var p := str(c.get_path()) if c is Node else str(c)
					var low := (str(c.name) + " " + str(c.get_parent().name if c is Node and c.get_parent() else "")).to_lower()
					if low.contains("road") or low.contains("terrain") or low.contains("ground") or low.contains("curb") or low.contains("kerb"):
						continue
					if not seen.has(p):
						seen[p] = []
					if seen[p].size() < 4:
						seen[p].append(c.get_class() + " vis=" + str(_vis(c)) + " i=%d lat=%.0f %s" % [i, lat, q.transform.origin.snapped(Vector3.ONE * 0.1)])
		print("== %s: %d colliders on the road; raw %s" % [tid, seen.size(), raw])
		for p in seen:
			print("  ", p, "  ", seen[p])
		total += seen.size()
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("WALL PROBE: %s (%d invisible colliders on the road)" % ["PASS" if total == 0 else "FAIL", total])
	get_tree().quit()


func _vis(c) -> String:
	if not (c is Node3D):
		return "?"
	var out := ""
	for ch in c.get_children():
		if ch is VisualInstance3D:
			out += "%s:%s " % [ch.get_class(), ch.is_visible_in_tree()]
	return out if out != "" else "no-mesh parent=" + str(c.get_parent().name)
