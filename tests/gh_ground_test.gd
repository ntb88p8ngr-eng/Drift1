extends Node
## Grüne Hölle pit straight and Hohenrain: the ground beside the track on both sides (pit lane and
## garages, grandstands) lies level with the road's edge – no humps.
## Run: godot --headless --path . res://tests/gh_ground_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "gruene_hoelle", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var tr = world.track
	var terrain = world.terrain
	var fails := 0
	for side: float in [-1.0, 1.0]:
		# the drivable strip beside the road (run-off, pit lane): level with the road's edge
		var worst := 0.0
		var where := ""
		var p := -200.0
		while p <= 140.0:
			var i: int = tr.index_at(p)
			var lat := float(tr.half_w) + 1.5
			while lat <= float(tr.half_w) + 14.0:
				var q: Vector3 = tr.samples[i] + tr.rights[i] * side * lat
				# against the road's edge nearest to the spot (inside the chicane that's not the
				# edge at the same progress, and the road climbs there)
				var d: float = float(terrain.height_at(q.x, q.z)) - _edge_y(tr, q, i)
				if absf(d) > absf(worst):
					worst = d
					where = "progress %d, %.0f m out" % [int(p), lat - float(tr.half_w)]
				lat += 2.0
			p += 4.0
		print("GROUND side %+d: worst height off the road edge %.2f m (%s)" % [int(side), worst, where])
		if absf(worst) > 0.35:
			print("FAIL: a hump beside the track"); fails += 1
	print("GH GROUND TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)


static func _edge_y(tr, q: Vector3, i: int) -> float:
	var n: int = tr.sample_count()
	var hw: float = tr.half_w
	var best_d := 1e9
	var best_h := 0.0
	for j in range(i - 30, i + 30):
		for s: float in [-1.0, 1.0]:
			var a: Vector3 = tr.edge_point((j + n) % n, s * hw)
			var b: Vector3 = tr.edge_point((j + 1 + n) % n, s * hw)
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ap := Vector2(q.x - a.x, q.z - a.z)
			var u := clampf(ap.dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := (ap - ab * u).length()
			if d < best_d:
				best_d = d
				best_h = lerpf(a.y, b.y, u)
	return best_h
