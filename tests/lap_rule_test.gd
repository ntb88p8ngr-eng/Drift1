extends Node
## Driving the wrong way spoils the lap only after 10 s of it, and only past a quarter of the lap or
## within 10 % of start/finish: at 15 % (after a spin) it costs nothing, at 50 % or just past the line
## it does – but a few seconds backwards never.
## Run: godot --headless --path . res://tests/lap_rule_test.tscn

const World = preload("res://scripts/world/world.gd")


func _ready() -> void:
	Game.persist = false
	var world := World.new()
	world.setup({"track": "ridge", "mode": "free", "laps": 1, "time_of_day": "day", "weather": "dry",
		"day_cycle": 0, "weather_seed": 3, "online": false})
	add_child(world)
	if not world.is_loaded:
		await world.loaded
	var fails := 0
	var tr = world.track
	for case in [[0.15, false, 12], [0.5, true, 12], [0.05, true, 12], [0.5, false, 5]]:
		world.crossed_start = true
		world._lap_spoilt = false
		world._rev_m = 0.0
		world._rev_t = 0.0
		world._last_prog = -1.0
		var p: float = tr.length * float(case[0])
		var i: int = tr.index_at(p)
		var car = world.local_car
		# facing the wrong way, reversing down the lap 30 m
		car.place(Transform3D(Basis.looking_at(-tr.tangents[i], Vector3.UP), tr.samples[i] + Vector3(0, 0.6, 0)))
		for f in 10:
			await get_tree().physics_frame
		world._rev_m = 0.0
		world._rev_t = 0.0
		world._lap_spoilt = false
		for f in 120 * int(case[2]):
			car.linear_velocity = -(tr.tangents[tr.index_at(world.progress)] as Vector3) * 6.0
			await get_tree().physics_frame
		print("LAP RULE: backwards from %d %% of the lap for %d s: %.0f m back, spoilt %s (expected %s)" % [int(float(case[0]) * 100), int(case[2]), world._rev_m, world._lap_spoilt, case[1]])
		if world._lap_spoilt != bool(case[1]):
			print("FAIL"); fails += 1
	print("LAP RULE TEST: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit(1 if fails else 0)
