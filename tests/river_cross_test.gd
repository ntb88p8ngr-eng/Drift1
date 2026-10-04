extends Node
## Utah: wherever the lap crosses the river the road is well above the water (a bridge) and the
## channel under it has depth (river bed below the water level).
## Run: godot --headless --path . res://tests/river_cross_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "utah", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false, "traffic": 0})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var tr = world.track
	var wt = tr.water
	var ok := true
	var crossings := 0
	var best := -1
	var n: int = tr.sample_count()
	for i in n + 1:
		var p: Vector3 = tr.samples[i % n]
		var r: Vector2 = wt.river_at(p.x, p.z)
		if r.x < wt.RIVER_W * 0.5 and i < n:
			if best < 0 or r.x < wt.river_at(tr.samples[best].x, tr.samples[best].z).x:
				best = i
		elif best >= 0:
			# the crossing's middle: clearance over the water, depth of the channel under it
			var q: Vector3 = tr.samples[best]
			var rq: Vector2 = wt.river_at(q.x, q.z)
			crossings += 1
			var clear: float = q.y - rq.y
			var bed: float = world.terrain.height_at(q.x, q.z)
			print("crossing %d at %s: road %.2f m over the water, bed %.2f m under it" % [crossings, q, clear, rq.y - bed])
			if clear < 2.0 or rq.y - bed < 1.5:
				ok = false
			best = -1
	print("RIVER CROSS TEST: %s (%d crossings)" % ["PASS" if ok and crossings > 0 else "FAIL", crossings])
	get_tree().quit()
